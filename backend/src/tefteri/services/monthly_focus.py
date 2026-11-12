"""Monthly theme focus planning and its read-only weekly planning seam (spec 007)."""

import uuid
from collections.abc import Callable, Iterable, Sequence
from dataclasses import dataclass
from datetime import UTC, date, datetime
from typing import Any
from zoneinfo import ZoneInfo

from sqlalchemy import delete, func, select
from sqlalchemy.ext.asyncio import AsyncSession

from tefteri.db.base import utcnow
from tefteri.db.models.key_result import KeyResultTheme
from tefteri.db.models.milestone import Milestone
from tefteri.db.models.monthly import FocusChange, MonthlyFocus, MonthlyFocusEntry
from tefteri.db.models.project_label import ProjectLabel as ProjectLabelRow
from tefteri.db.models.user import User
from tefteri.db.models.weekly import WeeklyPlan, WeeklyPlanProject
from tefteri.domain.classification import is_eligible, label_of
from tefteri.domain.enums import (
    FocusChangeKind,
    FocusEntryStatus,
    MonthState,
    ProjectLabel,
)
from tefteri.domain.monthly import (
    DoneMilestone,
    EntryWindow,
    classify_done,
    count_note,
    month_bounds,
    month_state,
    parse_target,
)
from tefteri.services.annual_plan import AnnualPlanService
from tefteri.services.errors import (
    AlreadyInFocus,
    AlreadyUndone,
    Conflict,
    DuplicateTheme,
    Invalid,
    InvalidTarget,
    LeftThisMonth,
    NotAFocusTheme,
    NotCurrentMonth,
    NotFound,
    NotInFocus,
    NotUndoable,
    PastMonth,
    UseChanges,
)
from tefteri.services.project_labels import ConnectionTree, load_trees


@dataclass(frozen=True)
class FocusDraft:
    """A theme id and its optional milestone-count target."""

    project_id: uuid.UUID
    target: object = None


@dataclass(frozen=True)
class MonthlyEntry:
    """A monthly focus entry with its current result and project-state markers."""

    id: uuid.UUID
    project_id: uuid.UUID
    connection_id: uuid.UUID
    name: str
    target: int | None
    counts_from: date
    left_on: date | None
    status: str
    done: int
    earlier_not_counted: int
    marker: str | None
    orphaned: dict[str, str] | None
    label_changed: str | None
    linked_key_results: int
    last_month_done: int


@dataclass(frozen=True)
class MonthlyKeyResult:
    """One annual key result relevant to this month's focus."""

    id: uuid.UUID
    goal_id: uuid.UUID
    goal_title: str
    metric: str
    start_value: float
    current_value: float
    current_at: datetime | None
    target: float
    deadline: date
    update_source: str
    past_deadline: bool
    theme_ids: list[uuid.UUID]
    flags: list[dict[str, Any]]


@dataclass(frozen=True)
class MonthlyPlan:
    """The planning read model for one month."""

    month: date
    start: date
    end: date
    state: str
    planning_year: int
    focus_known: bool
    count_note: str | None
    entries: list[MonthlyEntry]
    key_results: list[MonthlyKeyResult]
    themes_without_key_result: list[uuid.UUID]


@dataclass(frozen=True)
class ThemeOption:
    """One live eligible theme offered by the monthly picker."""

    project_id: uuid.UUID
    connection_id: uuid.UUID
    connection_name: str
    name: str
    in_focus: bool
    left_this_month: bool
    last_month_done: int
    key_result_ids: list[uuid.UUID]


@dataclass(frozen=True)
class TaskConnectionOption:
    """A task connection that can create a theme."""

    id: uuid.UUID
    name: str
    can_create: bool


@dataclass(frozen=True)
class ThemePicker:
    """Eligible themes, unsorted-project count and task connections for the picker."""

    themes: list[ThemeOption]
    unsorted_count: int
    task_connections: list[TaskConnectionOption]


@dataclass(frozen=True)
class FocusEffect:
    """A preview of changes to the monthly focus."""

    added: list[dict[str, object]]
    removed: list[dict[str, object]]
    targets_changed: list[dict[str, object]]
    counts_from: date
    finished_earlier_in_month: int
    finished_earlier: list[dict[str, object]]
    weekly_commitments_unchanged: int
    out_keeps_results: bool
    message: str


@dataclass(frozen=True)
class SavePlanResult:
    """The result of saving or previewing a monthly plan."""

    focus: MonthlyPlan | None
    count_note: str | None
    effect: FocusEffect | None = None


@dataclass(frozen=True)
class FocusChangeOut:
    """A row of the monthly focus history."""

    batch_id: uuid.UUID
    kind: str
    on: date
    out_name: str | None
    in_name: str | None
    target_before: int | None
    target_after: int | None
    source: str
    undone: bool
    can_undo: bool


@dataclass(frozen=True)
class FocusHistory:
    """Append-only changes of one monthly focus, oldest first."""

    month: date
    changes: list[FocusChangeOut]


def _as_draft(value: FocusDraft | tuple[uuid.UUID, object] | dict[str, object]) -> FocusDraft:
    """Normalize a service draft from a typed object, API-like mapping or tuple."""
    if isinstance(value, FocusDraft):
        return value
    if isinstance(value, dict):
        project_id = value.get("project_id")
        if not isinstance(project_id, uuid.UUID):
            project_id = uuid.UUID(str(project_id))
        return FocusDraft(project_id, value.get("target"))
    project_id, target = value
    return FocusDraft(project_id, target)


def _month_start(month: date) -> date:
    return date(month.year, month.month, 1)


def _previous_month(month: date) -> date:
    return date(month.year - 1, 12, 1) if month.month == 1 else date(month.year, month.month - 1, 1)


def _theme_rows(
    trees: Iterable[ConnectionTree],
) -> dict[uuid.UUID, tuple[ConnectionTree, ProjectLabelRow]]:
    """Return only explicit, live theme labels which have no ignored ancestor."""
    out: dict[uuid.UUID, tuple[ConnectionTree, ProjectLabelRow]] = {}
    for tree in trees:
        for row in tree.rows:
            key = str(row.id)
            node = tree.nodes.get(key)
            if (
                node is not None
                and row.label == ProjectLabel.THEME.value
                and is_eligible(tree.nodes, key)
                and label_of(tree.nodes, key) is ProjectLabel.THEME
            ):
                out[row.id] = (tree, row)
    return out


class MonthlyFocusService:
    """Save and read the theme focus of each month; never call a task backend."""

    def __init__(
        self,
        annual: AnnualPlanService,
        *,
        clock: Callable[[], datetime] | None = None,
    ) -> None:
        """Use the annual plan only for key-result reads and an injectable clock for local dates."""
        self._annual = annual
        self._clock = clock or (lambda: datetime.now(UTC))

    async def _timezone(self, db: AsyncSession, user_id: uuid.UUID, tz: str | None) -> str:
        """Resolve the user's stored time zone unless the caller supplied it."""
        if tz is not None:
            return tz
        user = await db.get(User, user_id)
        if user is None:
            raise NotFound
        return user.timezone

    async def _today(self, db: AsyncSession, user_id: uuid.UUID, tz: str | None) -> date:
        """Return the clock's local date for this user."""
        zone = ZoneInfo(await self._timezone(db, user_id, tz))
        now = self._clock()
        if now.tzinfo is None:
            now = now.replace(tzinfo=UTC)
        return now.astimezone(zone).date()

    async def _focus(
        self, db: AsyncSession, user_id: uuid.UUID, month: date
    ) -> MonthlyFocus | None:
        """Return this user's saved monthly focus."""
        return (
            await db.execute(
                select(MonthlyFocus).where(
                    MonthlyFocus.user_id == user_id,
                    MonthlyFocus.month == _month_start(month),
                )
            )
        ).scalar_one_or_none()

    async def _entries(self, db: AsyncSession, focus_id: uuid.UUID) -> list[MonthlyFocusEntry]:
        """Return focus entries in the saved display order."""
        return list(
            (
                await db.execute(
                    select(MonthlyFocusEntry)
                    .where(MonthlyFocusEntry.focus_id == focus_id)
                    .order_by(MonthlyFocusEntry.position, MonthlyFocusEntry.created_at)
                )
            ).scalars()
        )

    async def themes_for_month(
        self, db: AsyncSession, user_id: uuid.UUID, month_start: date
    ) -> set[uuid.UUID] | None:
        """Return focus theme ids, or ``None`` when the month has never been saved."""
        rows = (
            await db.execute(
                select(
                    MonthlyFocus.id,
                    MonthlyFocusEntry.project_id,
                    MonthlyFocusEntry.left_on,
                )
                .outerjoin(
                    MonthlyFocusEntry,
                    MonthlyFocusEntry.focus_id == MonthlyFocus.id,
                )
                .where(
                    MonthlyFocus.user_id == user_id,
                    MonthlyFocus.month == _month_start(month_start),
                )
            )
        ).all()
        if not rows:
            return None
        return {
            project_id
            for _, project_id, left_on in rows
            if project_id is not None and left_on is None
        }

    async def themes(
        self,
        db: AsyncSession,
        user_id: uuid.UUID,
        month: date,
        *,
        q: str | None = None,
        connection_id: uuid.UUID | None = None,
    ) -> ThemePicker:
        """List searchable live themes, current focus state and last-month done hints."""
        month = _month_start(month)
        trees = await load_trees(db, user_id, connection_id)
        eligible = _theme_rows(trees)
        focus = await self._focus(db, user_id, month)
        entries = await self._entries(db, focus.id) if focus else []
        entry_by_project = {entry.project_id: entry for entry in entries}
        start, end = month_bounds(_previous_month(month))
        done_rows = list(
            (
                await db.execute(
                    select(Milestone).where(
                        Milestone.user_id == user_id,
                        Milestone.state == "done",
                        Milestone.done_on >= start,
                        Milestone.done_on < end,
                    )
                )
            ).scalars()
        )
        counts: dict[uuid.UUID, int] = {}
        for milestone in done_rows:
            if milestone.done_theme_id is not None:
                counts[milestone.done_theme_id] = counts.get(milestone.done_theme_id, 0) + 1
        theme_ids = list(eligible)
        active_links: dict[uuid.UUID, list[uuid.UUID]] = {}
        if theme_ids:
            link_rows = list(
                (
                    await db.execute(
                        select(KeyResultTheme).where(
                            KeyResultTheme.user_id == user_id,
                            KeyResultTheme.project_id.in_(theme_ids),
                            KeyResultTheme.ended_at.is_(None),
                        )
                    )
                ).scalars()
            )
            for link in link_rows:
                active_links.setdefault(link.project_id, []).append(link.key_result_id)
        query = q.strip().casefold() if q else ""
        options = []
        for project_id, (tree, row) in eligible.items():
            if query and query not in row.name.casefold():
                continue
            entry = entry_by_project.get(project_id)
            options.append(
                ThemeOption(
                    project_id=project_id,
                    connection_id=tree.connection.id,
                    connection_name=tree.connection.display_name,
                    name=row.name,
                    in_focus=bool(entry is not None and entry.left_on is None),
                    left_this_month=bool(entry is not None and entry.left_on is not None),
                    last_month_done=counts.get(project_id, 0),
                    key_result_ids=active_links.get(project_id, []),
                )
            )
        connections = [
            TaskConnectionOption(tree.connection.id, tree.connection.display_name, True)
            for tree in trees
        ]
        unsorted = sum(
            1
            for tree in trees
            for row in tree.rows
            if row.orphaned_reason is None and row.label is None
        )
        return ThemePicker(
            themes=sorted(options, key=lambda row: (row.name.casefold(), str(row.project_id))),
            unsorted_count=unsorted,
            task_connections=connections,
        )

    async def plan(
        self, db: AsyncSession, user_id: uuid.UUID, month: date, *, tz: str | None = None
    ) -> MonthlyPlan:
        """Build the monthly focus, milestone results and annual key-result context."""
        month = _month_start(month)
        today = await self._today(db, user_id, tz)
        start, end = month_bounds(month)
        state = month_state(month, today)
        focus = await self._focus(db, user_id, month)
        stored_entries = await self._entries(db, focus.id) if focus else []
        trees = await load_trees(db, user_id)
        tree_by_project = {row.id: tree for tree in trees for row in tree.rows}
        project_by_id = {row.id: row for tree in trees for row in tree.rows}
        done_rows = list(
            (
                await db.execute(
                    select(Milestone).where(
                        Milestone.user_id == user_id,
                        Milestone.state == "done",
                        Milestone.done_on >= start,
                        Milestone.done_on < end,
                    )
                )
            ).scalars()
        )
        previous_start, previous_end = month_bounds(_previous_month(month))
        previous_done = list(
            (
                await db.execute(
                    select(Milestone.done_theme_id).where(
                        Milestone.user_id == user_id,
                        Milestone.state == "done",
                        Milestone.done_on >= previous_start,
                        Milestone.done_on < previous_end,
                        Milestone.done_theme_id.is_not(None),
                    )
                )
            ).scalars()
        )
        last_month_counts: dict[uuid.UUID, int] = {}
        for theme_id in previous_done:
            if theme_id is not None:
                last_month_counts[theme_id] = last_month_counts.get(theme_id, 0) + 1
        done = [
            DoneMilestone(
                str(row.id),
                project_by_id[row.project_id].name
                if row.project_id in project_by_id
                else str(row.project_id),
                row.done_on,
                str(row.done_theme_id) if row.done_theme_id else None,
            )
            for row in done_rows
            if row.done_on is not None
        ]
        windows = [
            EntryWindow(
                project_id=str(entry.project_id),
                name=(
                    project_by_id[entry.project_id].name
                    if entry.project_id in project_by_id
                    else entry.name
                ),
                target=entry.target,
                counts_from=entry.counts_from,
                left_on=entry.left_on,
                left_reason=FocusEntryStatus(entry.left_reason) if entry.left_reason else None,
            )
            for entry in stored_entries
        ]
        results, _ = classify_done(month, windows, done)
        result_by_id = {uuid.UUID(item.project_id): item for item in results}

        annual_plan = await self._annual.plan(
            db, user_id, month.year, tz=await self._timezone(db, user_id, tz)
        )
        focus_ids = {entry.project_id for entry in stored_entries if entry.left_on is None}
        key_results: list[MonthlyKeyResult] = []
        linked_by_theme: dict[uuid.UUID, int] = {}
        all_goals = [*annual_plan.goals, *annual_plan.retired_goals]
        for goal in all_goals:
            for key_result in goal.key_results:
                usable_links = [
                    link.project_id for link in key_result.links if link.active and link.usable
                ]
                in_focus = bool(focus_ids.intersection(usable_links))
                flags = [dict(flag) for flag in key_result.flags]
                if not in_focus:
                    flags.append({"code": "no_theme_in_focus", "actions": ["open_picker"]})
                has_006_flag = bool(key_result.flags)
                if in_focus or has_006_flag or usable_links:
                    key_results.append(
                        MonthlyKeyResult(
                            id=key_result.id,
                            goal_id=goal.id,
                            goal_title=goal.title,
                            metric=key_result.metric,
                            start_value=key_result.start_value,
                            current_value=key_result.current_value,
                            current_at=key_result.current_at,
                            target=key_result.target,
                            deadline=key_result.deadline,
                            update_source=key_result.update_source,
                            past_deadline=key_result.deadline < today,
                            theme_ids=usable_links,
                            flags=flags,
                        )
                    )
                for project_id in usable_links:
                    linked_by_theme[project_id] = linked_by_theme.get(project_id, 0) + 1
        output_entries = []
        for entry in stored_entries:
            project = project_by_id.get(entry.project_id)
            result = result_by_id[entry.project_id]
            tree = tree_by_project.get(entry.project_id)
            changed_label: str | None = None
            if project is not None and project.label != ProjectLabel.THEME.value:
                changed_label = project.label
            elif (
                project is not None
                and project.orphaned_reason is None
                and tree is not None
                and not is_eligible(tree.nodes, str(project.id))
            ):
                changed_label = ProjectLabel.IGNORED.value
            orphan = None
            if project is not None and project.orphaned_reason is not None:
                orphan = {
                    "reason": project.orphaned_reason,
                    "at": project.orphaned_at.isoformat() if project.orphaned_at else "",
                }
            output_entries.append(
                MonthlyEntry(
                    id=entry.id,
                    project_id=entry.project_id,
                    connection_id=project.connection_id if project else uuid.UUID(int=0),
                    name=project.name if project else entry.name,
                    target=entry.target,
                    counts_from=entry.counts_from,
                    left_on=entry.left_on,
                    status=(
                        FocusEntryStatus(entry.left_reason).value
                        if entry.left_reason
                        else FocusEntryStatus.IN_FOCUS.value
                    ),
                    done=result.done,
                    earlier_not_counted=len(result.earlier_not_counted),
                    marker=None if state is MonthState.FUTURE else result.marker.value,
                    orphaned=orphan,
                    label_changed=changed_label,
                    linked_key_results=linked_by_theme.get(entry.project_id, 0),
                    last_month_done=last_month_counts.get(entry.project_id, 0),
                )
            )
        linked_in_focus = {project_id for project_id in linked_by_theme if project_id in focus_ids}
        themes_without_key_result = [
            entry.project_id
            for entry in stored_entries
            if entry.left_on is None and entry.project_id not in linked_in_focus
        ]
        focused_count = sum(entry.left_on is None for entry in stored_entries)
        note = count_note(focused_count)
        # ``AnnualPlan`` already sorted its goals and key results; keep that stable ordering here.
        return MonthlyPlan(
            month=month,
            start=start,
            end=end,
            state=state.value,
            planning_year=month.year,
            focus_known=focus is not None,
            count_note=note.value if note else None,
            entries=output_entries,
            key_results=key_results,
            themes_without_key_result=themes_without_key_result,
        )

    async def save_plan(
        self,
        db: AsyncSession,
        user_id: uuid.UUID,
        month: date,
        entries: Sequence[FocusDraft | tuple[uuid.UUID, object] | dict[str, object]],
        *,
        dry_run: bool = False,
        tz: str | None = None,
    ) -> SavePlanResult:
        """Save or preview a month focus, retaining soft guidance outside three to five themes."""
        month = _month_start(month)
        today = await self._today(db, user_id, tz)
        state = month_state(month, today)
        if state is MonthState.PAST:
            raise PastMonth()
        drafts = [_as_draft(item) for item in entries]
        ids = [draft.project_id for draft in drafts]
        if len(set(ids)) != len(ids):
            raise DuplicateTheme()
        targets: dict[uuid.UUID, int | None] = {}
        try:
            for draft in drafts:
                targets[draft.project_id] = parse_target(draft.target)
        except ValueError as exc:
            raise InvalidTarget() from exc
        trees = await load_trees(db, user_id)
        eligible = _theme_rows(trees)
        projects = {row.id: row for tree in trees for row in tree.rows}
        for project_id in ids:
            if project_id not in projects:
                raise NotFound
            if project_id not in eligible:
                raise NotAFocusTheme()
        focus = await self._focus(db, user_id, month)
        existing = await self._entries(db, focus.id) if focus else []
        active = {entry.project_id: entry for entry in existing if entry.left_on is None}
        selected = set(ids)
        if focus is not None and state is MonthState.CURRENT and selected != set(active):
            raise UseChanges()
        effect = FocusEffect(
            added=[
                {"project_id": str(project_id), "name": projects[project_id].name}
                for project_id in ids
                if project_id not in active
            ],
            removed=[
                {"project_id": str(project_id), "name": entry.name}
                for project_id, entry in active.items()
                if project_id not in selected
            ],
            targets_changed=[
                {
                    "project_id": str(project_id),
                    "name": projects[project_id].name,
                    "before": active[project_id].target,
                    "after": targets[project_id],
                }
                for project_id in ids
                if project_id in active and active[project_id].target != targets[project_id]
            ],
            counts_from=month if state is not MonthState.CURRENT else today,
            finished_earlier_in_month=0,
            finished_earlier=[],
            weekly_commitments_unchanged=0,
            out_keeps_results=True,
            message=(
                "The monthly focus changes only in Tefteri. Weekly commitments and milestones "
                "stay as they are."
            ),
        )
        note = count_note(len(ids))
        if dry_run:
            return SavePlanResult(None, note.value if note else None, effect)
        if focus is None:
            focus = MonthlyFocus(user_id=user_id, month=month)
            db.add(focus)
            await db.flush()
        if state is not MonthState.CURRENT:
            query = delete(MonthlyFocusEntry).where(MonthlyFocusEntry.focus_id == focus.id)
            if selected:
                query = query.where(MonthlyFocusEntry.project_id.not_in(selected))
            await db.execute(query)
            await db.flush()
        active = {
            entry.project_id: entry
            for entry in await self._entries(db, focus.id)
            if entry.left_on is None
        }
        for position, project_id in enumerate(ids):
            old = active.get(project_id)
            if old is not None:
                old.target = targets[project_id]
                old.position = position
                old.name = projects[project_id].name
                continue
            db.add(
                MonthlyFocusEntry(
                    focus_id=focus.id,
                    project_id=project_id,
                    name=projects[project_id].name,
                    target=targets[project_id],
                    counts_from=month,
                    position=position,
                )
            )
        focus.updated_at = utcnow()
        await db.flush()
        plan = await self.plan(db, user_id, month, tz=tz)
        return SavePlanResult(plan, plan.count_note, None)

    async def change(
        self,
        db: AsyncSession,
        user_id: uuid.UUID,
        month: date,
        *,
        kind: str | FocusChangeKind,
        out_project_id: uuid.UUID | None = None,
        in_project_id: uuid.UUID | None = None,
        target: object = None,
        dry_run: bool = False,
        tz: str | None = None,
    ) -> "ChangeResult":
        """Apply or preview an add, swap, remove or target update for the current month."""
        month = _month_start(month)
        today = await self._today(db, user_id, tz)
        if month_state(month, today) is not MonthState.CURRENT:
            raise NotCurrentMonth()
        try:
            kind = FocusChangeKind(kind)
        except ValueError as exc:
            raise Invalid("Choose swap, add, remove or target.") from exc
        focus = await self._focus(db, user_id, month)
        if focus is None:
            raise Conflict("not_in_focus", "Save this month's focus before changing it.")
        stored = await self._entries(db, focus.id)
        active = {entry.project_id: entry for entry in stored if entry.left_on is None}
        trees = await load_trees(db, user_id)
        eligible = _theme_rows(trees)
        project_by_id = {row.id: row for tree in trees for row in tree.rows}
        if (
            kind in (FocusChangeKind.SWAP, FocusChangeKind.REMOVE, FocusChangeKind.TARGET)
            and out_project_id not in active
        ):
            if out_project_id is not None and out_project_id not in project_by_id:
                raise NotFound
            raise NotInFocus()
        if kind in (FocusChangeKind.ADD, FocusChangeKind.SWAP):
            if in_project_id is None:
                raise Invalid("Choose a theme to add.")
            if in_project_id not in project_by_id:
                raise NotFound
            if in_project_id not in eligible:
                raise NotAFocusTheme()
            previous = next((entry for entry in stored if entry.project_id == in_project_id), None)
            if previous is not None:
                if previous.left_on is None:
                    raise AlreadyInFocus()
                raise LeftThisMonth()
        if kind is FocusChangeKind.SWAP and out_project_id == in_project_id:
            raise Invalid("Choose two different themes.")
        parsed_target: int | None = None
        if kind in (FocusChangeKind.ADD, FocusChangeKind.SWAP, FocusChangeKind.TARGET):
            try:
                parsed_target = parse_target(target)
            except ValueError as exc:
                raise InvalidTarget() from exc
        out_entry = active.get(out_project_id) if out_project_id else None
        out_row = project_by_id.get(out_project_id) if out_project_id else None
        in_row = project_by_id.get(in_project_id) if in_project_id else None
        counts_from = (
            today
            if kind in (FocusChangeKind.ADD, FocusChangeKind.SWAP)
            else (out_entry.counts_from if out_entry else today)
        )
        earlier: list[dict[str, object]] = []
        if in_project_id is not None:
            month_start, month_end = month_bounds(month)
            milestones = list(
                (
                    await db.execute(
                        select(Milestone).where(
                            Milestone.user_id == user_id,
                            Milestone.state == "done",
                            Milestone.done_theme_id == in_project_id,
                            Milestone.done_on >= month_start,
                            Milestone.done_on < today,
                        )
                    )
                ).scalars()
            )
            earlier = [
                {
                    "milestone_id": str(item.id),
                    "name": project_by_id[item.project_id].name
                    if item.project_id in project_by_id
                    else str(item.project_id),
                    "done_on": item.done_on,
                }
                for item in milestones
                if item.done_on is not None
            ]
        weekly_count = 0
        if out_project_id is not None:
            weekly_count = int(
                (
                    await db.execute(
                        select(func.count(WeeklyPlanProject.id))
                        .join(WeeklyPlan, WeeklyPlan.id == WeeklyPlanProject.plan_id)
                        .where(
                            WeeklyPlan.user_id == user_id,
                            WeeklyPlan.week_start >= month_bounds(month)[0],
                            WeeklyPlan.week_start < month_bounds(month)[1],
                            WeeklyPlanProject.theme_project_id == out_project_id,
                        )
                    )
                ).scalar_one()
            )
        effect = FocusEffect(
            added=(
                [{"project_id": str(in_project_id), "name": in_row.name}]
                if in_project_id and in_row and kind in (FocusChangeKind.ADD, FocusChangeKind.SWAP)
                else []
            ),
            removed=(
                [{"project_id": str(out_project_id), "name": out_row.name}]
                if out_project_id
                and out_row
                and kind in (FocusChangeKind.REMOVE, FocusChangeKind.SWAP)
                else []
            ),
            targets_changed=(
                [
                    {
                        "project_id": str(out_project_id),
                        "name": out_row.name,
                        "before": out_entry.target,
                        "after": parsed_target,
                    }
                ]
                if kind is FocusChangeKind.TARGET and out_entry and out_row
                else []
            ),
            counts_from=counts_from,
            finished_earlier_in_month=len(earlier),
            finished_earlier=earlier,
            weekly_commitments_unchanged=weekly_count,
            out_keeps_results=kind in (FocusChangeKind.SWAP, FocusChangeKind.REMOVE),
            message=self._effect_message(
                kind,
                out_row.name if out_row else None,
                in_row.name if in_row else None,
                counts_from,
                len(earlier),
                weekly_count,
            ),
        )
        batch_id = uuid.uuid4()
        if dry_run:
            return ChangeResult(batch_id, effect, None)
        before = out_entry.target if out_entry else None
        if kind in (FocusChangeKind.SWAP, FocusChangeKind.REMOVE):
            assert out_entry is not None  # noqa: S101 - validated above
            out_entry.left_on = today
            out_entry.left_reason = (
                FocusEntryStatus.SWAPPED_OUT.value
                if kind is FocusChangeKind.SWAP
                else FocusEntryStatus.REMOVED.value
            )
        if kind is FocusChangeKind.TARGET:
            assert out_entry is not None  # noqa: S101 - validated above
            out_entry.target = parsed_target
        incoming_entry = None
        if kind in (FocusChangeKind.SWAP, FocusChangeKind.ADD):
            assert in_project_id is not None and in_row is not None  # noqa: S101
            incoming_entry = MonthlyFocusEntry(
                focus_id=focus.id,
                project_id=in_project_id,
                name=in_row.name,
                target=parsed_target,
                counts_from=today,
                position=max((entry.position for entry in stored), default=-1) + 1,
            )
            db.add(incoming_entry)
            await db.flush()
        db.add(
            FocusChange(
                focus_id=focus.id,
                kind=kind.value,
                changed_on=today,
                out_entry_id=out_entry.id if out_entry else None,
                in_entry_id=incoming_entry.id if incoming_entry else None,
                out_project_id=out_project_id,
                in_project_id=in_project_id,
                out_name=out_row.name if out_row else None,
                in_name=in_row.name if in_row else None,
                target_before=before,
                target_after=parsed_target,
                batch_id=batch_id,
                source="user",
            )
        )
        focus.updated_at = utcnow()
        await db.flush()
        plan = await self.plan(db, user_id, month, tz=tz)
        return ChangeResult(batch_id, effect, plan)

    @staticmethod
    def _effect_message(
        kind: FocusChangeKind,
        out_name: str | None,
        in_name: str | None,
        counts_from: date,
        earlier: int,
        weekly_count: int,
    ) -> str:
        """Describe the immutable effect of a preview in plain language."""
        if kind is FocusChangeKind.TARGET and out_name:
            return f"The target of {out_name} keeps its existing count window."
        if kind is FocusChangeKind.REMOVE and out_name:
            return (
                f"{out_name} leaves the focus. Its finished milestones and weekly commitments stay."
            )
        if kind is FocusChangeKind.ADD and in_name:
            return f"{in_name} counts from {counts_from:%-d %B}."
        message = f"The target of {in_name or 'the new theme'} counts from {counts_from:%-d %B}."
        if earlier:
            message += f" {earlier} milestone(s) finished earlier in the month do not count."
        if out_name:
            message += f" Weekly commitments under {out_name} stay as they are."
        if weekly_count:
            message = message.replace(
                "Weekly commitments under", f"{weekly_count} weekly commitments under"
            )
        return message

    async def history(
        self, db: AsyncSession, user_id: uuid.UUID, month: date, *, tz: str | None = None
    ) -> FocusHistory:
        """Read the chronological focus-change log and calculate which rows remain undoable."""
        focus = await self._focus(db, user_id, month)
        if focus is None:
            return FocusHistory(_month_start(month), [])
        rows = list(
            (
                await db.execute(
                    select(FocusChange)
                    .where(FocusChange.focus_id == focus.id)
                    .order_by(FocusChange.created_at, FocusChange.id)
                )
            ).scalars()
        )
        undone = {row.undoes_batch_id for row in rows if row.undoes_batch_id is not None}
        order = {row.batch_id: index for index, row in enumerate(rows)}
        output = []
        for index, row in enumerate(rows):
            later_touch = any(
                later.source == "user"
                and order[later.batch_id] > index
                and ({later.out_project_id, later.in_project_id} - {None}).intersection(
                    {row.out_project_id, row.in_project_id} - {None}
                )
                for later in rows
            )
            is_undone = row.batch_id in undone
            output.append(
                FocusChangeOut(
                    batch_id=row.batch_id,
                    kind=row.kind,
                    on=row.changed_on,
                    out_name=row.out_name,
                    in_name=row.in_name,
                    target_before=row.target_before,
                    target_after=row.target_after,
                    source=row.source,
                    undone=is_undone,
                    can_undo=row.source == "user" and not is_undone and not later_touch,
                )
            )
        return FocusHistory(_month_start(month), output)

    async def undo(
        self,
        db: AsyncSession,
        user_id: uuid.UUID,
        month: date,
        batch_id: uuid.UUID,
        *,
        tz: str | None = None,
    ) -> "UndoResult":
        """Reverse a non-conflicting focus-change batch by appending an undo log row."""
        focus = await self._focus(db, user_id, month)
        if focus is None:
            raise NotFound
        rows = list(
            (
                await db.execute(
                    select(FocusChange)
                    .where(FocusChange.focus_id == focus.id)
                    .order_by(FocusChange.created_at, FocusChange.id)
                )
            ).scalars()
        )
        target = next(
            (row for row in rows if row.batch_id == batch_id and row.source == "user"), None
        )
        if target is None:
            raise NotFound
        if any(row.undoes_batch_id == batch_id for row in rows):
            raise AlreadyUndone()
        target_ids = {target.out_project_id, target.in_project_id} - {None}
        if any(
            row.source == "user"
            and row.batch_id != batch_id
            and row.created_at > target.created_at
            and target_ids.intersection({row.out_project_id, row.in_project_id} - {None})
            for row in rows
        ):
            raise NotUndoable()
        today = await self._today(db, user_id, tz)
        out_entry = (
            await db.get(MonthlyFocusEntry, target.out_entry_id) if target.out_entry_id else None
        )
        in_entry = (
            await db.get(MonthlyFocusEntry, target.in_entry_id) if target.in_entry_id else None
        )
        if target.kind in (FocusChangeKind.SWAP.value, FocusChangeKind.REMOVE.value):
            if out_entry is None:
                raise NotUndoable()
            out_entry.left_on = None
            out_entry.left_reason = None
        if target.kind == FocusChangeKind.TARGET.value:
            if out_entry is None:
                raise NotUndoable()
            out_entry.target = target.target_before
        if target.kind in (FocusChangeKind.SWAP.value, FocusChangeKind.ADD.value):
            if in_entry is None:
                raise NotUndoable()
            await db.delete(in_entry)
        db.add(
            FocusChange(
                focus_id=focus.id,
                kind=target.kind,
                changed_on=today,
                out_entry_id=target.out_entry_id,
                in_entry_id=target.in_entry_id,
                out_project_id=target.out_project_id,
                in_project_id=target.in_project_id,
                out_name=target.out_name,
                in_name=target.in_name,
                target_before=target.target_after,
                target_after=target.target_before,
                batch_id=uuid.uuid4(),
                undoes_batch_id=batch_id,
                source="undo",
            )
        )
        focus.updated_at = utcnow()
        await db.flush()
        return UndoResult(target.kind, await self.plan(db, user_id, month, tz=tz))


@dataclass(frozen=True)
class ChangeResult:
    """The preview or result of one focus change."""

    batch_id: uuid.UUID
    effect: FocusEffect
    focus: MonthlyPlan | None


@dataclass(frozen=True)
class UndoResult:
    """The effect of undoing a focus change."""

    undone: str
    focus: MonthlyPlan
