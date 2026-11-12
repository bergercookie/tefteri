"""The annual plan (spec 006): read model, bulk create, goal edits, undo and history.

The plan screen is built here from the rows of one planning year. Every user change is one
batch of ``plan_changes`` rows (R-05); ``undo`` reverses such a batch by writing the opposite
rows with ``source = 'undo'``. Writes in a past year are refused (R-09); reading never is.
"""

import uuid
from collections.abc import Callable, Iterable, Sequence
from dataclasses import dataclass
from datetime import UTC, date, datetime
from typing import Any

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from tefteri.db.base import utcnow
from tefteri.db.models.goal import Goal
from tefteri.db.models.key_result import KeyResult, KeyResultTheme, KeyResultValue, PlanChange
from tefteri.domain.annual_plan import (
    MAX_ACTIVE_KEY_RESULTS,
    GoalSuggestion,
    PastGoal,
    PastKeyResult,
    next_free_slot,
    suggest,
    today_in,
    year_state,
)
from tefteri.domain.classification import ProjectNode
from tefteri.domain.enums import (
    ChangeSource,
    GoalState,
    LinkEndReason,
    PlanChangeKind,
    ProjectLabel,
    UpdateSource,
    YearState,
)
from tefteri.domain.key_results import (
    Flag,
    LinkView,
    ValidationError,
    ValueEntry,
    current_value,
    goal_flags,
    goal_progress,
    is_met,
    is_usable_link,
    key_result_flags,
    link_state,
    progress,
    validate,
)
from tefteri.services.classification import ClassificationService
from tefteri.services.errors import Conflict, Invalid, NotFound
from tefteri.services.key_results import KeyResultService
from tefteri.services.plan_changes import RetireEffect, change, write_batch
from tefteri.services.project_labels import load_trees

PAST_YEAR_MESSAGE = "This year is over. Its plan can be read, but not changed."
KEY_RESULT_LIMIT_MESSAGE = "A goal can have three key results. Retire one first."


def require_open(year: int, today: date) -> None:
    """Raise ``past_year`` when the planning year is over (R-09)."""
    if year_state(year, today) == YearState.PAST.value:
        raise Conflict("past_year", PAST_YEAR_MESSAGE)


@dataclass(frozen=True)
class LinkOut:
    """One link period of a key result, as the plan shows it (R-04)."""

    id: uuid.UUID
    project_id: uuid.UUID
    name: str
    active: bool
    usable: bool
    state: str
    label: str | None
    started_at: datetime
    ended_at: datetime | None


@dataclass(frozen=True)
class KeyResultOut:
    """One key result with its derived values and its flags (R-02, R-11, R-12)."""

    id: uuid.UUID
    goal_id: uuid.UUID
    metric: str
    start_value: float
    target: float
    deadline: date
    update_source: str
    status: str
    current_value: float
    current_at: datetime | None
    progress: float
    met: bool
    retired_at: datetime | None
    flags: list[dict[str, Any]]
    links: list[LinkOut]


@dataclass(frozen=True)
class GoalOut:
    """One goal of the plan with its key results."""

    id: uuid.UUID
    title: str
    status: str
    legacy_done: bool
    criteria_suggestion: str | None
    progress: float | None
    flags: list[dict[str, Any]]
    notes: list[str]
    updated_at: datetime
    key_results: list[KeyResultOut]


@dataclass(frozen=True)
class ThemeUsageOut:
    """Which key results a theme project is linked to right now (FR-011)."""

    project_id: uuid.UUID
    name: str
    key_result_ids: list[uuid.UUID]


@dataclass(frozen=True)
class AnnualPlan:
    """The read model of one planning year."""

    year: int
    state: str
    editable: bool
    goals: list[GoalOut]
    retired_goals: list[GoalOut]
    theme_usage: list[ThemeUsageOut]


@dataclass(frozen=True)
class RetireOutcome:
    """The answer of a goal retire: the effect and, when written, the batch (FR-021)."""

    effect: RetireEffect
    batch_id: uuid.UUID | None


@dataclass(frozen=True)
class RestoreSkip:
    """One theme that a restore could not re-link, and why (FR-021)."""

    project_id: uuid.UUID
    name: str
    state: str


@dataclass(frozen=True)
class RestoreOutcome:
    """The answer of a goal restore: what came back and which themes were skipped."""

    restored: int
    links_restored: int
    links_skipped: list[RestoreSkip]


@dataclass(frozen=True)
class ThemeOption:
    """One theme the user can link a key result to (FR-012)."""

    project_id: uuid.UUID
    name: str
    connection_id: uuid.UUID
    key_result_ids: list[uuid.UUID]
    connection_name: str = ""
    """The name of the task connection, for a user with more than one."""


@dataclass(frozen=True)
class ThemeConnection:
    """One task connection in the theme picker."""

    id: uuid.UUID
    name: str
    can_create: bool


@dataclass(frozen=True)
class ThemePicker:
    """The answer of ``GET /annual/themes`` (R-13)."""

    themes: list[ThemeOption]
    unsorted_count: int
    task_connections: list[ThemeConnection]


@dataclass(frozen=True)
class BulkGoalDraft:
    """One goal of a bulk create, with its key results and their themes."""

    title: str
    key_results: Sequence["BulkKeyResultDraft"] = ()


@dataclass(frozen=True)
class BulkKeyResultDraft:
    """One key result of a bulk create."""

    metric: str
    start_value: float
    target: float
    deadline: date
    update_source: UpdateSource = UpdateSource.MANUAL
    theme_ids: Sequence[uuid.UUID] = ()
    seeded_from_id: uuid.UUID | None = None
    """The key result of year N that this one was copied from, when seeding."""


@dataclass(frozen=True)
class PlanChangeOut:
    """One row of the plan history, as the API answers it (FR-019)."""

    id: uuid.UUID
    at: datetime
    kind: str
    year: int
    goal_id: uuid.UUID | None
    key_result_id: uuid.UUID | None
    link_id: uuid.UUID | None
    field: str | None
    old_value: str | None
    new_value: str | None
    reason: str | None
    batch_id: uuid.UUID | None
    source: str
    undone: bool


class AnnualPlanService:
    """Read, create, change, retire, restore and undo the plan of a year."""

    def __init__(
        self,
        key_results: KeyResultService,
        classification: ClassificationService,
        clock: Callable[[], datetime] = lambda: datetime.now(UTC),
    ) -> None:
        """``key_results`` owns the key result write paths; ``classification`` creates themes."""
        self._key_results = key_results
        self._classification = classification
        self._clock = clock

    def require_open(self, year: int, *, tz: str) -> None:
        """Apply the shared past-year write guard for operations owned by key results (R-09)."""
        require_open(year, today_in(tz, self._clock()))

    # -- reading ------------------------------------------------------------------------------

    async def _goal_rows(self, db: AsyncSession, user_id: uuid.UUID, year: int) -> list[Goal]:
        rows = list(
            (
                await db.execute(
                    select(Goal).where(
                        Goal.user_id == user_id,
                        Goal.period_type == "year",
                        Goal.period_start == date(year, 1, 1),
                    )
                )
            ).scalars()
        )
        return sorted(rows, key=lambda g: (g.position, g.title, str(g.id)))

    async def plan(self, db: AsyncSession, user_id: uuid.UUID, year: int, *, tz: str) -> AnnualPlan:
        """Build the whole plan of one year, flags included, and change nothing (FR-014)."""
        today = today_in(tz, self._clock())
        state = year_state(year, today)
        goal_rows = await self._goal_rows(db, user_id, year)
        active_rows = [g for g in goal_rows if g.status != GoalState.RETIRED.value]
        retired_rows = [g for g in goal_rows if g.status == GoalState.RETIRED.value]
        key_result_rows = await _key_results_of(
            db, user_id, [g.id for g in goal_rows], order_by=KeyResult.position
        )
        kr_ids = [k.id for k in key_result_rows]
        value_rows = list(
            (
                await db.execute(
                    select(KeyResultValue)
                    .where(
                        KeyResultValue.user_id == user_id,
                        KeyResultValue.key_result_id.in_(_or_none(kr_ids)),
                    )
                    .order_by(KeyResultValue.on_date, KeyResultValue.seq)
                )
            ).scalars()
        )
        link_rows = list(
            (
                await db.execute(
                    select(KeyResultTheme)
                    .where(
                        KeyResultTheme.user_id == user_id,
                        KeyResultTheme.key_result_id.in_(_or_none(kr_ids)),
                    )
                    .order_by(KeyResultTheme.started_at, KeyResultTheme.id)
                )
            ).scalars()
        )
        trees = await load_trees(db, user_id)
        names = {row.id: row.name for tree in trees for row in tree.rows}
        nodes: dict[str, ProjectNode] = {}
        for tree in trees:
            nodes.update(tree.nodes)

        entries_by_kr: dict[uuid.UUID, list[ValueEntry]] = {}
        at_by_kr: dict[uuid.UUID, datetime] = {}
        for row in value_rows:
            entries_by_kr.setdefault(row.key_result_id, []).append(
                ValueEntry(row.value, row.on_date, row.seq)
            )
            at_by_kr[row.key_result_id] = row.at
        links_by_kr: dict[uuid.UUID, list[KeyResultTheme]] = {}
        for row in link_rows:
            links_by_kr.setdefault(row.key_result_id, []).append(row)

        def key_result_out(row: KeyResult) -> KeyResultOut:
            entries = entries_by_kr.get(row.id, [])
            current = current_value(row.start_value, entries)
            met = is_met(row.start_value, row.target, current)
            views = [_link_view(link, names) for link in links_by_kr.get(row.id, [])]
            flags = key_result_flags(
                status=row.status,
                deadline=row.deadline,
                met=met,
                today=today,
                nodes=nodes,
                links=views,
            )
            return KeyResultOut(
                id=row.id,
                goal_id=row.goal_id,
                metric=row.metric,
                start_value=row.start_value,
                target=row.target,
                deadline=row.deadline,
                update_source=row.update_source,
                status=row.status,
                current_value=current,
                current_at=utc(at_by_kr.get(row.id)),
                progress=progress(row.start_value, row.target, current),
                met=met,
                retired_at=utc(row.retired_at),
                flags=[_flag_dict(f) for f in flags],
                links=[_link_out(link, names, nodes) for link in links_by_kr.get(row.id, [])],
            )

        key_results_by_goal: dict[uuid.UUID, list[KeyResultOut]] = {}
        for row in key_result_rows:
            key_results_by_goal.setdefault(row.goal_id, []).append(key_result_out(row))
        usage: dict[uuid.UUID, ThemeUsageOut] = {}
        for row in link_rows:
            if row.ended_at is not None:
                continue
            out = usage.setdefault(
                row.project_id, ThemeUsageOut(row.project_id, names.get(row.project_id, ""), [])
            )
            out.key_result_ids.append(row.key_result_id)

        def goal_out(row: Goal) -> GoalOut:
            krs = key_results_by_goal.get(row.id, [])
            active_krs = [k for k in krs if k.status == GoalState.ACTIVE.value]
            return GoalOut(
                id=row.id,
                title=row.title,
                status=row.status,
                legacy_done=row.status == "done",
                criteria_suggestion=row.criteria if not krs else None,
                progress=goal_progress(k.progress for k in active_krs),
                flags=[_flag_dict(f) for f in goal_flags(active_key_results=len(active_krs))],
                notes=_notes(active_krs),
                updated_at=utc(row.updated_at),
                key_results=krs,
            )

        return AnnualPlan(
            year=year,
            state=state,
            editable=state != YearState.PAST.value,
            goals=[goal_out(g) for g in active_rows],
            retired_goals=[goal_out(g) for g in retired_rows],
            theme_usage=sorted(usage.values(), key=lambda u: u.name),
        )

    async def goal_titles_for(
        self, db: AsyncSession, user_id: uuid.UUID, goal_ids: Iterable[uuid.UUID]
    ) -> dict[uuid.UUID, tuple[str, bool]]:
        """Return ``(title, is_annual)`` for the given goal ids (tasks router, FR-027)."""
        ids = list(dict.fromkeys(goal_ids))
        if not ids:
            return {}
        rows = list(
            (
                await db.execute(select(Goal).where(Goal.user_id == user_id, Goal.id.in_(ids)))
            ).scalars()
        )
        return {row.id: (row.title, row.period_type == "year") for row in rows}

    async def linkable_goal(
        self, db: AsyncSession, user_id: uuid.UUID, goal_id: uuid.UUID, *, tz: str = "UTC"
    ) -> Goal | None:
        """Return the goal when a task may be linked to it, else ``None`` (FR-026).

        Only an annual goal of the current year that is not retired can be linked. A goal
        marked complete before annual planning counts as active (R-01).
        """
        row = await db.get(Goal, goal_id)
        if row is None or row.user_id != user_id or row.period_type != "year":
            return None
        if row.status == GoalState.RETIRED.value:
            return None
        if row.period_start.year != today_in(tz, self._clock()).year:
            return None
        return row

    async def legacy_goals(
        self,
        db: AsyncSession,
        user_id: uuid.UUID,
        *,
        period_type: str | None = None,
        period_start: date | None = None,
    ) -> list[Goal]:
        """Return the month and week goals of the history, oldest first (FR-022)."""
        query = select(Goal).where(Goal.user_id == user_id, Goal.period_type != "year")
        if period_type is not None:
            query = query.where(Goal.period_type == period_type)
        if period_start is not None:
            query = query.where(Goal.period_start == period_start)
        return list((await db.execute(query.order_by(Goal.period_start))).scalars())

    # -- creating (FR-002, FR-016) ------------------------------------------------------------

    async def bulk_create(
        self,
        db: AsyncSession,
        user_id: uuid.UUID,
        year: int,
        drafts: Sequence[BulkGoalDraft],
        *,
        seeded_from: int | None = None,
        tz: str,
        batch_id: uuid.UUID | None = None,
    ) -> list[GoalOut]:
        """Create several goals with their key results and links in one batch (FR-002, FR-016).

        Everything is written or nothing is: the caller rolls the transaction back on error.
        The source of the history rows is ``seed`` when the plan was seeded from year N, else
        ``user``. Only an open year accepts goals.
        """
        require_open(year, today_in(tz, self._clock()))
        trees = await load_trees(db, user_id)
        usable = self._key_results.eligible_theme_keys(trees)
        now = self._clock()
        batch_id = batch_id or uuid.uuid4()
        if seeded_from is not None and seeded_from >= year:
            raise Invalid("The source year must be earlier than the new year.")
        seed_sources = {
            kr.seeded_from_id
            for draft in drafts
            for kr in draft.key_results
            if kr.seeded_from_id is not None
        }
        if seed_sources:
            owned = set(
                (
                    await db.execute(
                        select(KeyResult.id).where(
                            KeyResult.user_id == user_id, KeyResult.id.in_(seed_sources)
                        )
                    )
                ).scalars()
            )
            if owned != seed_sources:
                raise NotFound
        source = ChangeSource.SEED.value if seeded_from is not None else ChangeSource.USER.value
        existing = await self._goal_rows(db, user_id, year)
        position = len(existing)
        changes: list[PlanChange] = []
        created: list[tuple[Goal, list[KeyResult]]] = []
        for draft in drafts:
            title = draft.title.strip()
            if not title or len(title) > 500:
                raise Invalid("The title must be 1 to 500 characters.")
            goal = Goal(
                id=uuid.uuid4(),
                user_id=user_id,
                period_type="year",
                period_start=date(year, 1, 1),
                title=title,
                status=GoalState.ACTIVE.value,
                position=position,
            )
            position += 1
            db.add(goal)
            changes.append(
                change(user_id, year, PlanChangeKind.GOAL_CREATED, goal_id=goal.id, new_value=title)
            )
            if len(draft.key_results) > MAX_ACTIVE_KEY_RESULTS:
                raise Conflict("key_result_limit", KEY_RESULT_LIMIT_MESSAGE)
            key_result_rows: list[KeyResult] = []
            for slot_number, kr in enumerate(draft.key_results, start=1):
                metric = kr.metric.strip()
                _validate(
                    metric=metric,
                    start_value=kr.start_value,
                    target=kr.target,
                    deadline=kr.deadline,
                    year=year,
                )
                row = KeyResult(
                    id=uuid.uuid4(),
                    user_id=user_id,
                    goal_id=goal.id,
                    year=year,
                    metric=metric,
                    start_value=kr.start_value,
                    target=kr.target,
                    deadline=kr.deadline,
                    update_source=kr.update_source.value,
                    status=GoalState.ACTIVE.value,
                    slot=slot_number,
                    position=slot_number - 1,
                    seeded_from_id=kr.seeded_from_id,
                )
                db.add(row)
                key_result_rows.append(row)
                changes.append(
                    change(
                        user_id,
                        year,
                        PlanChangeKind.KEY_RESULT_CREATED,
                        goal_id=goal.id,
                        key_result_id=row.id,
                        new_value=metric,
                    )
                )
                for theme_id in dict.fromkeys(kr.theme_ids):
                    if theme_id not in usable:
                        raise Invalid("That project is not a live theme.", "not_a_theme")
                    link = KeyResultTheme(
                        id=uuid.uuid4(),
                        user_id=user_id,
                        key_result_id=row.id,
                        project_id=theme_id,
                        year=year,
                        started_at=now,
                    )
                    db.add(link)
                    changes.append(
                        change(
                            user_id,
                            year,
                            PlanChangeKind.LINK_ADDED,
                            key_result_id=row.id,
                            link_id=link.id,
                        )
                    )
            created.append((goal, key_result_rows))
        await db.flush()
        await write_batch(db, changes, batch_id=batch_id, source=source, now=now)
        return [
            GoalOut(
                id=goal.id,
                title=goal.title,
                status=goal.status,
                legacy_done=False,
                criteria_suggestion=None,
                progress=goal_progress(0.0 for _ in krs),
                flags=[_flag_dict(f) for f in goal_flags(active_key_results=len(krs))],
                notes=[],
                updated_at=utc(goal.updated_at),
                key_results=[
                    KeyResultOut(
                        id=row.id,
                        goal_id=row.goal_id,
                        metric=row.metric,
                        start_value=row.start_value,
                        target=row.target,
                        deadline=row.deadline,
                        update_source=row.update_source,
                        status=row.status,
                        current_value=row.start_value,
                        current_at=None,
                        progress=0.0,
                        met=False,
                        retired_at=None,
                        flags=[],
                        links=[],
                    )
                    for row in krs
                ],
            )
            for goal, krs in created
        ]

    # -- goal edits (FR-018) ------------------------------------------------------------------

    async def _goal(self, db: AsyncSession, user_id: uuid.UUID, goal_id: uuid.UUID) -> Goal:
        row = await db.get(Goal, goal_id)
        if row is None or row.user_id != user_id or row.period_type != "year":
            raise NotFound
        return row

    async def edit_goal(
        self, db: AsyncSession, user_id: uuid.UUID, goal_id: uuid.UUID, title: str, *, tz: str
    ) -> Goal:
        """Change the title of an annual goal; one history row records it (FR-018)."""
        goal = await self._goal(db, user_id, goal_id)
        require_open(goal.period_start.year, today_in(tz, self._clock()))
        title = title.strip()
        if not title or len(title) > 500:
            raise Invalid("The title must be 1 to 500 characters.")
        old = goal.title
        if old == title:
            return goal
        goal.title = title
        goal.updated_at = utcnow()
        await db.flush()
        await write_batch(
            db,
            [
                change(
                    user_id,
                    goal.period_start.year,
                    PlanChangeKind.GOAL_EDITED,
                    goal_id=goal.id,
                    field_name="title",
                    old_value=old,
                    new_value=title,
                )
            ],
            batch_id=uuid.uuid4(),
            source=ChangeSource.USER.value,
            now=self._clock(),
        )
        return goal

    # -- retiring and restoring (FR-021, R-06) ------------------------------------------------

    async def retire_goal(
        self,
        db: AsyncSession,
        user_id: uuid.UUID,
        goal_id: uuid.UUID,
        reason: str | None,
        *,
        dry_run: bool = False,
        tz: str,
    ) -> RetireOutcome:
        """Retire a goal with its key results and links, or only say what that would do (R-06).

        Everything lands in one batch, so ``undo`` can bring the whole retire back (FR-021).
        """
        goal = await self._goal(db, user_id, goal_id)
        today = today_in(tz, self._clock())
        require_open(goal.period_start.year, today)
        key_results = list(
            (
                await db.execute(
                    select(KeyResult).where(
                        KeyResult.goal_id == goal.id, KeyResult.status == GoalState.ACTIVE.value
                    )
                )
            ).scalars()
        )
        links_of = {
            row.id: list(await self._key_results.active_links(db, row)) for row in key_results
        }
        trees = await load_trees(db, user_id)
        nodes: dict[str, ProjectNode] = {}
        for tree in trees:
            nodes.update(tree.nodes)
        effect = await self._key_results.retire_effect(
            db,
            user_id,
            key_results,
            reason=reason,
            today=today,
            nodes=nodes,
            links_of=links_of,
        )
        if not key_results and "no_key_result" not in effect.flags_removed:
            effect.flags_removed = ["no_key_result"]
        if dry_run:
            return RetireOutcome(effect, None)
        now = self._clock()
        batch_id = uuid.uuid4()
        await self._key_results.retire_key_results(
            db,
            key_results,
            reason=reason,
            now=now,
            batch_id=batch_id,
            source=ChangeSource.USER.value,
            link_reason=LinkEndReason.GOAL_RETIRED,
        )
        goal.status = GoalState.RETIRED.value
        goal.retired_at = now
        goal.retired_reason = reason
        goal.updated_at = utcnow()
        await db.flush()
        await write_batch(
            db,
            [
                change(
                    user_id,
                    goal.period_start.year,
                    PlanChangeKind.GOAL_RETIRED,
                    goal_id=goal.id,
                    reason=reason,
                )
            ],
            batch_id=batch_id,
            source=ChangeSource.USER.value,
            now=now,
        )
        return RetireOutcome(effect, batch_id)

    async def restore_goal(
        self, db: AsyncSession, user_id: uuid.UUID, goal_id: uuid.UUID, *, tz: str
    ) -> RestoreOutcome:
        """Restore a retired goal with the key results and links of its retire batch (FR-021)."""
        goal = await self._goal(db, user_id, goal_id)
        require_open(goal.period_start.year, today_in(tz, self._clock()))
        if goal.status != GoalState.RETIRED.value:
            raise Conflict("already_retired", "This goal is not retired.")
        batch = await self._goal_retirement_batch(db, user_id, goal.id)
        key_results = list(
            (
                await db.execute(
                    select(KeyResult).where(
                        KeyResult.user_id == user_id,
                        KeyResult.goal_id == goal.id,
                        KeyResult.status == GoalState.RETIRED.value,
                    )
                )
            ).scalars()
        )
        if batch is not None:
            # Only the key results of the retire batch come back (FR-021).
            retired_in_batch = set(
                (
                    await db.execute(
                        select(PlanChange.key_result_id).where(
                            PlanChange.user_id == user_id,
                            PlanChange.batch_id == batch,
                            PlanChange.kind == PlanChangeKind.KEY_RESULT_RETIRED.value,
                        )
                    )
                ).scalars()
            )
            key_results = [row for row in key_results if row.id in retired_in_batch]
        # The slots must be free before anything is written (R-03).
        taken = await _taken_slots(db, goal.id)
        free = MAX_ACTIVE_KEY_RESULTS - len(taken)
        if free < len(key_results):
            raise Conflict("key_result_limit", KEY_RESULT_LIMIT_MESSAGE)
        goal.status = GoalState.ACTIVE.value
        goal.retired_at = None
        goal.retired_reason = None
        goal.updated_at = utcnow()
        await db.flush()
        now = self._clock()
        batch_id = uuid.uuid4()
        await write_batch(
            db,
            [
                change(
                    user_id, goal.period_start.year, PlanChangeKind.GOAL_RESTORED, goal_id=goal.id
                )
            ],
            batch_id=batch_id,
            source=ChangeSource.USER.value,
            now=now,
        )
        trees = await load_trees(db, user_id)
        links_restored, skipped = await self._key_results.restore_key_results(
            db,
            key_results,
            batch=batch,
            now=now,
            batch_id=batch_id,
            source=ChangeSource.USER.value,
            trees=trees,
        )
        return RestoreOutcome(len(key_results) + 1, links_restored, skipped)

    async def _goal_retirement_batch(
        self, db: AsyncSession, user_id: uuid.UUID, goal_id: uuid.UUID
    ) -> uuid.UUID | None:
        """Return the batch that retired the goal, from the history."""
        row = (
            await db.execute(
                select(PlanChange)
                .where(
                    PlanChange.user_id == user_id,
                    PlanChange.goal_id == goal_id,
                    PlanChange.kind == PlanChangeKind.GOAL_RETIRED.value,
                )
                .order_by(PlanChange.at.desc())
                .limit(1)
            )
        ).scalar_one_or_none()
        return row.batch_id if row else None

    # -- undo (FR-020) ------------------------------------------------------------------------

    _REVERSIBLE = {
        PlanChangeKind.GOAL_RETIRED.value,
        PlanChangeKind.KEY_RESULT_RETIRED.value,
        PlanChangeKind.LINK_REMOVED.value,
        PlanChangeKind.LINK_ADDED.value,
    }

    async def undo(
        self, db: AsyncSession, user_id: uuid.UUID, batch_id: uuid.UUID, *, tz: str
    ) -> int:
        """Reverse one batch of changes; the reverse is written with ``source = 'undo'`` (FR-020).

        A batch is undone once. A goal retire brings its key results and links back; a re-link
        is reversed the other way round. Returns how many goals, key results and links came
        back.
        """
        rows = list(
            (
                await db.execute(
                    select(PlanChange)
                    .where(PlanChange.user_id == user_id, PlanChange.batch_id == batch_id)
                    .order_by(PlanChange.at)
                )
            ).scalars()
        )
        if not rows:
            raise NotFound
        if any(row.source == ChangeSource.UNDO.value for row in rows):
            raise Conflict("already_undone", "This change was already undone.")
        if any(row.kind not in self._REVERSIBLE for row in rows):
            raise Conflict("not_undoable", "This change cannot be undone.")
        require_open(rows[0].year, today_in(tz, self._clock()))

        now = self._clock()
        changes: list[PlanChange] = []
        restored = 0

        # 1. End the links the batch added (a re-link is reversed the other way round).
        added_links = await _links_by_id(
            db, user_id, [row.link_id for row in rows if row.kind == "link_added" and row.link_id]
        )
        for link in added_links:
            if link.ended_at is None:
                link.ended_at = now
                link.end_reason = LinkEndReason.REMOVED.value
                changes.append(
                    change(
                        user_id,
                        link.year,
                        PlanChangeKind.LINK_REMOVED,
                        key_result_id=link.key_result_id,
                        link_id=link.id,
                    )
                )

        # 2. The goals of the batch come back.
        goal_ids = list(
            dict.fromkeys(row.goal_id for row in rows if row.kind == "goal_retired" and row.goal_id)
        )
        for goal_id in goal_ids:
            goal = await db.get(Goal, goal_id)
            if goal is None or goal.status != GoalState.RETIRED.value:
                continue
            goal.status = GoalState.ACTIVE.value
            goal.retired_at = None
            goal.retired_reason = None
            goal.updated_at = utcnow()
            restored += 1
            changes.append(
                change(
                    user_id, goal.period_start.year, PlanChangeKind.GOAL_RESTORED, goal_id=goal.id
                )
            )

        # 3. The key results of the batch come back; their slots must be free (R-03).
        kr_ids = list(
            dict.fromkeys(
                row.key_result_id
                for row in rows
                if row.kind == "key_result_retired" and row.key_result_id
            )
        )
        key_results: list[KeyResult] = []
        for kr_id in kr_ids:
            row = await db.get(KeyResult, kr_id)
            if row is not None and row.status == GoalState.RETIRED.value:
                key_results.append(row)
        wanted: dict[uuid.UUID, int] = {}
        for row in key_results:
            wanted[row.goal_id] = wanted.get(row.goal_id, 0) + 1
        for goal_id, count in wanted.items():
            taken = await _taken_slots(db, goal_id)
            if MAX_ACTIVE_KEY_RESULTS - len(taken) < count:
                raise Conflict("key_result_limit", KEY_RESULT_LIMIT_MESSAGE)
        for row in key_results:
            slot = next_free_slot(await _taken_slots(db, row.goal_id))
            if slot is None:
                raise Conflict("key_result_limit", KEY_RESULT_LIMIT_MESSAGE)
            row.status = GoalState.ACTIVE.value
            row.slot = slot
            row.retired_at = None
            row.retired_reason = None
            row.updated_at = utcnow()
            restored += 1
            changes.append(
                change(
                    user_id,
                    row.year,
                    PlanChangeKind.KEY_RESULT_RESTORED,
                    goal_id=row.goal_id,
                    key_result_id=row.id,
                )
            )
        await db.flush()

        # 4. The links the batch ended start again, for themes that are still usable.
        removed_links = await _links_by_id(
            db, user_id, [row.link_id for row in rows if row.kind == "link_removed" and row.link_id]
        )
        if removed_links:
            trees = await load_trees(db, user_id)
            usable = self._key_results.eligible_theme_keys(trees)
            for link in removed_links:
                if link.project_id not in usable:
                    continue
                key_result = await db.get(KeyResult, link.key_result_id)
                if key_result is None or key_result.status != GoalState.ACTIVE.value:
                    continue
                new_link = KeyResultTheme(
                    id=uuid.uuid4(),
                    user_id=user_id,
                    key_result_id=link.key_result_id,
                    project_id=link.project_id,
                    year=key_result.year,
                    started_at=now,
                )
                db.add(new_link)
                restored += 1
                changes.append(
                    change(
                        user_id,
                        key_result.year,
                        PlanChangeKind.LINK_ADDED,
                        key_result_id=link.key_result_id,
                        link_id=new_link.id,
                    )
                )
        await db.flush()
        await write_batch(db, changes, batch_id=batch_id, source=ChangeSource.UNDO.value, now=now)
        return restored

    # -- history (FR-019) ---------------------------------------------------------------------

    async def history(
        self,
        db: AsyncSession,
        user_id: uuid.UUID,
        year: int,
        *,
        goal_id: uuid.UUID | None = None,
        key_result_id: uuid.UUID | None = None,
    ) -> list[PlanChangeOut]:
        """Return the history of the year in time order, each row marked ``undone`` (FR-019)."""
        query = (
            select(PlanChange)
            .where(PlanChange.user_id == user_id, PlanChange.year == year)
            .order_by(PlanChange.at, PlanChange.id)
        )
        if goal_id is not None:
            query = query.where(PlanChange.goal_id == goal_id)
        if key_result_id is not None:
            query = query.where(PlanChange.key_result_id == key_result_id)
        rows = list((await db.execute(query)).scalars())
        undone_batches = {
            row.batch_id
            for row in rows
            if row.source == ChangeSource.UNDO.value and row.batch_id is not None
        }
        return [
            PlanChangeOut(
                id=row.id,
                at=utc(row.at),
                kind=row.kind,
                year=row.year,
                goal_id=row.goal_id,
                key_result_id=row.key_result_id,
                link_id=row.link_id,
                field=row.field,
                old_value=row.old_value,
                new_value=row.new_value,
                reason=row.reason,
                batch_id=row.batch_id,
                source=row.source,
                undone=row.batch_id in undone_batches,
            )
            for row in rows
        ]

    # -- seeding (FR-016, FR-017, R-10) -------------------------------------------------------

    async def suggestions(
        self, db: AsyncSession, user_id: uuid.UUID, year: int, *, from_year: int
    ) -> list[GoalSuggestion]:
        """Work out what the new year can inherit from year N. Reads and writes nothing."""
        goal_rows = await self._goal_rows(db, user_id, from_year)
        key_result_rows = await _key_results_of(db, user_id, [g.id for g in goal_rows])
        kr_ids = [k.id for k in key_result_rows]
        value_rows = list(
            (
                await db.execute(
                    select(KeyResultValue)
                    .where(
                        KeyResultValue.user_id == user_id,
                        KeyResultValue.key_result_id.in_(_or_none(kr_ids)),
                    )
                    .order_by(KeyResultValue.on_date, KeyResultValue.seq)
                )
            ).scalars()
        )
        link_rows = list(
            (
                await db.execute(
                    select(KeyResultTheme).where(
                        KeyResultTheme.user_id == user_id,
                        KeyResultTheme.key_result_id.in_(_or_none(kr_ids)),
                        KeyResultTheme.ended_at.is_(None),
                    )
                )
            ).scalars()
        )
        trees = await load_trees(db, user_id)
        names = {row.id: row.name for tree in trees for row in tree.rows}
        entries_by_kr: dict[uuid.UUID, list[ValueEntry]] = {}
        for row in value_rows:
            entries_by_kr.setdefault(row.key_result_id, []).append(
                ValueEntry(row.value, row.on_date, row.seq)
            )
        links_by_kr: dict[uuid.UUID, list[KeyResultTheme]] = {}
        for row in link_rows:
            links_by_kr.setdefault(row.key_result_id, []).append(row)
        past_goals = [
            PastGoal(
                id=str(row.id),
                status=row.status,
                title=row.title,
                key_results=tuple(
                    PastKeyResult(
                        id=str(kr.id),
                        status=kr.status,
                        metric=kr.metric,
                        start_value=kr.start_value,
                        target=kr.target,
                        deadline=kr.deadline,
                        entries=tuple(entries_by_kr.get(kr.id, ())),
                        links=tuple(_link_view(link, names) for link in links_by_kr.get(kr.id, ())),
                    )
                    for kr in key_result_rows
                    if kr.goal_id == row.id
                ),
            )
            for row in goal_rows
        ]
        nodes: dict[str, ProjectNode] = {}
        for tree in trees:
            nodes.update(tree.nodes)
        return suggest(past_goals, year=year, from_year=from_year, nodes=nodes)

    async def suggestions_view(
        self, db: AsyncSession, user_id: uuid.UUID, year: int, *, from_year: int
    ) -> dict[str, Any]:
        """Return the suggestions of year N in the shape of ``GET /annual/{year}/suggestions``.

        ``has_plan`` is false when year N has no goal. Each key result carries the themes whose
        link is still usable, by id and name, and its update source. Nothing is written.
        """
        has_plan = bool(await self._goal_rows(db, user_id, from_year))
        found = await self.suggestions(db, user_id, year, from_year=from_year)
        kr_ids = [uuid.UUID(kr.key_result_id) for g in found for kr in g.key_results]
        sources = {
            row.id: row.update_source for row in await _key_results_by_id(db, user_id, kr_ids)
        }
        trees = await load_trees(db, user_id)
        names = {str(row.id): row.name for tree in trees for row in tree.rows}
        return {
            "year": year,
            "from_year": from_year,
            "has_plan": has_plan,
            "goals": [
                {
                    "goal_id": g.goal_id,
                    "title": g.title,
                    "key_results": [
                        {
                            "key_result_id": kr.key_result_id,
                            "metric": kr.metric,
                            "start_value": kr.start_value,
                            "target": kr.target,
                            "deadline": kr.deadline,
                            "update_source": sources.get(
                                uuid.UUID(kr.key_result_id), UpdateSource.MANUAL.value
                            ),
                            "themes": [
                                {"project_id": key, "name": names.get(key, "")}
                                for key in kr.theme_keys
                            ],
                        }
                        for kr in g.key_results
                    ],
                }
                for g in found
            ],
        }

    # -- themes (FR-012, R-13) ----------------------------------------------------------------

    async def themes(self, db: AsyncSession, user_id: uuid.UUID, *, year: int) -> ThemePicker:
        """List the live themes the user can link a key result to (R-13)."""
        trees = await load_trees(db, user_id)
        links = list(
            (
                await db.execute(
                    select(KeyResultTheme).where(
                        KeyResultTheme.user_id == user_id,
                        KeyResultTheme.ended_at.is_(None),
                        KeyResultTheme.year == year,
                    )
                )
            ).scalars()
        )
        by_project: dict[uuid.UUID, list[uuid.UUID]] = {}
        for link in links:
            by_project.setdefault(link.project_id, []).append(link.key_result_id)
        options: list[ThemeOption] = []
        unsorted = 0
        connections: list[ThemeConnection] = []
        for tree in trees:
            connections.append(
                ThemeConnection(
                    tree.connection.id,
                    tree.connection.display_name,
                    True,
                )
            )
            for row in tree.rows:
                if row.orphaned_reason is not None:
                    continue
                node = tree.nodes.get(str(row.id))
                if node is not None and node.label is None:
                    unsorted += 1
                if not is_usable_link(tree.nodes, str(row.id)):
                    continue
                options.append(
                    ThemeOption(
                        row.id,
                        row.name,
                        tree.connection.id,
                        by_project.get(row.id, []),
                        tree.connection.display_name,
                    )
                )
        return ThemePicker(
            themes=sorted(options, key=lambda o: o.name),
            unsorted_count=unsorted,
            task_connections=connections,
        )

    async def create_theme(
        self, db: AsyncSession, user_id: uuid.UUID, connection_id: uuid.UUID, name: str
    ) -> ThemeOption:
        """Create a project in the task app and label it as a theme (FR-012, the rule of 003).

        A live theme with the same name in the connection is refused with its row.
        """
        title = name.strip()
        if not title:
            raise Invalid("Give the theme a name.")
        trees = await load_trees(db, user_id, connection_id)
        for tree in trees:
            for row in tree.rows:
                if (
                    row.orphaned_reason is None
                    and row.label == ProjectLabel.THEME.value
                    and row.name.casefold() == title.casefold()
                ):
                    raise Conflict(
                        "theme_exists",
                        "A theme with this name already exists.",
                        extra={"existing": {"project_id": str(row.id), "name": row.name}},
                    )
        view = await self._classification.create_and_label(
            db, user_id, connection_id, title, None, ProjectLabel.THEME
        )
        connection_name = next(
            (t.connection.display_name for t in trees if t.connection.id == connection_id), ""
        )
        return ThemeOption(view.row.id, view.row.name, connection_id, [], connection_name)


# -- module helpers ---------------------------------------------------------------------------


def _or_none(ids: Sequence[uuid.UUID]) -> list[uuid.UUID]:
    """Return the ids, or one dummy id so ``in_`` never sees an empty list."""
    return list(ids) or [uuid.uuid4()]


async def _key_results_of(
    db: AsyncSession,
    user_id: uuid.UUID,
    goal_ids: Sequence[uuid.UUID],
    *,
    order_by: Any = None,
) -> list[KeyResult]:
    query = select(KeyResult).where(
        KeyResult.user_id == user_id, KeyResult.goal_id.in_(_or_none(goal_ids))
    )
    if order_by is not None:
        query = query.order_by(order_by, KeyResult.id)
    return list((await db.execute(query)).scalars())


async def _key_results_by_id(
    db: AsyncSession, user_id: uuid.UUID, ids: Sequence[uuid.UUID]
) -> list[KeyResult]:
    """Return the user's key results with the given ids."""
    return list(
        (
            await db.execute(
                select(KeyResult).where(
                    KeyResult.user_id == user_id, KeyResult.id.in_(_or_none(ids))
                )
            )
        ).scalars()
    )


async def _taken_slots(db: AsyncSession, goal_id: uuid.UUID) -> list[int]:
    """Return the slots the active key results of a goal use (R-03)."""
    return list(
        (
            await db.execute(
                select(KeyResult.slot).where(
                    KeyResult.goal_id == goal_id, KeyResult.status == GoalState.ACTIVE.value
                )
            )
        ).scalars()
    )


async def _links_by_id(
    db: AsyncSession, user_id: uuid.UUID, link_ids: Sequence[uuid.UUID]
) -> list[KeyResultTheme]:
    ids = list(dict.fromkeys(link_ids))
    if not ids:
        return []
    rows = list(
        (
            await db.execute(
                select(KeyResultTheme).where(
                    KeyResultTheme.user_id == user_id, KeyResultTheme.id.in_(ids)
                )
            )
        ).scalars()
    )
    return sorted(rows, key=lambda r: r.started_at)


def _link_view(link: KeyResultTheme, names: dict[uuid.UUID, str]) -> LinkView:
    return LinkView(
        name=names.get(link.project_id, ""),
        key=str(link.project_id),
        active=link.ended_at is None,
    )


def _link_out(
    link: KeyResultTheme, names: dict[uuid.UUID, str], nodes: dict[str, ProjectNode]
) -> LinkOut:
    state, new_label = link_state(nodes, str(link.project_id))
    return LinkOut(
        id=link.id,
        project_id=link.project_id,
        name=names.get(link.project_id, ""),
        active=link.ended_at is None,
        usable=state == "ok",
        state=state,
        label=_current_label(nodes, link.project_id, new_label),
        started_at=utc(link.started_at),
        ended_at=utc(link.ended_at),
    )


def _current_label(
    nodes: dict[str, ProjectNode], project_id: uuid.UUID, new_label: ProjectLabel | None
) -> str | None:
    """The stored label of a linked project now: the new one when it was relabelled."""
    if new_label is not None:
        return new_label.value
    node = nodes.get(str(project_id))
    return node.label.value if node is not None and node.label is not None else None


def utc(value: datetime | None) -> datetime | None:
    """Return ``value`` as an aware UTC time; SQLite gives naive ones (stored as UTC)."""
    if value is None or value.tzinfo is not None:
        return value
    return value.replace(tzinfo=UTC)


def _flag_dict(flag: Flag) -> dict[str, Any]:
    return {
        "code": flag.code,
        "actions": list(flag.actions),
        "reasons": [
            {
                "project_id": reason.project_id,
                "name": reason.name,
                "state": reason.state,
                "label": reason.label.value if reason.label is not None else None,
            }
            for reason in flag.reasons
        ],
    }


def _notes(key_results: Sequence[KeyResultOut]) -> list[str]:
    """Return the quiet notes of a goal: the same metric text twice (FR-014)."""
    seen: set[str] = set()
    for row in key_results:
        folded = row.metric.casefold()
        if folded in seen:
            return ["duplicate_metric"]
        seen.add(folded)
    return []


def _validate(*, metric: str, start_value: float, target: float, deadline: date, year: int) -> None:
    """Turn a domain ``ValidationError`` into the API answer (FR-005)."""
    try:
        validate(
            metric=metric, start_value=start_value, target=target, deadline=deadline, year=year
        )
    except ValidationError as exc:
        raise Invalid(exc.args[0], "invalid") from exc
