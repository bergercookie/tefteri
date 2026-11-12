"""Key results (spec 006): create, edit, links to themes, retire, restore and the value series.

The current value is derived from the series, never stored (R-02). The limit of three active
key results per goal is held by the database (a unique constraint on ``goal_id`` and ``slot``,
R-03); the service only picks the lowest free slot and turns the integrity error into a clear
answer. Every change appends ``plan_changes`` rows in one batch (R-05).
"""

import uuid
from collections.abc import Callable, Iterable, Mapping, Sequence
from dataclasses import dataclass
from datetime import UTC, date, datetime
from typing import Any
from zoneinfo import ZoneInfo

from sqlalchemy import func, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from tefteri.db.base import utcnow
from tefteri.db.models.goal import Goal
from tefteri.db.models.key_result import KeyResult, KeyResultTheme, KeyResultValue, PlanChange
from tefteri.db.models.project_label import ProjectLabel as ProjectLabelRow
from tefteri.domain.annual_plan import next_free_slot
from tefteri.domain.classification import ProjectNode
from tefteri.domain.enums import (
    ChangeSource,
    GoalState,
    LinkEndReason,
    PlanChangeKind,
    UpdateSource,
    ValueSource,
)
from tefteri.domain.key_results import (
    LinkView,
    ValidationError,
    ValueEntry,
    current_value,
    is_met,
    is_overdue,
    key_result_flags,
    progress,
    stamp_manual_value,
    validate,
)
from tefteri.services.errors import Conflict, Invalid, NotFound
from tefteri.services.plan_changes import (
    MICROSECOND,
    LinkSetEffect,
    RetireEffect,
    ThemeEntry,
    change,
    end_link,
    end_links,
    start_link,
    write_batch,
)
from tefteri.services.project_labels import ConnectionTree

KEY_RESULT_LIMIT_MESSAGE = "A goal can have three key results. Retire one first."


class SlotLimit(Exception):
    """A key result could not get a slot: the goal already has three active ones."""


@dataclass(frozen=True)
class SeriesPoint:
    """One value of the series, as the API answers it."""

    id: uuid.UUID
    value: float
    at: datetime
    on_date: date
    source: str
    seq: int


@dataclass(frozen=True)
class ValueOn:
    """The answer of ``value_on``: the last value on or before a date, or nothing (FR-034)."""

    key_result_id: uuid.UUID
    date: date
    value: float | None
    at: datetime | None
    source: str | None


@dataclass(frozen=True)
class RetireResult:
    """The effect of a retire, and the batch when it was really written."""

    effect: RetireEffect
    batch_id: uuid.UUID | None


@dataclass(frozen=True)
class RestoreResult:
    """What a restore brought back and which links were skipped (FR-021)."""

    restored: int
    links_restored: int
    links_skipped: list[ThemeEntry]


class KeyResultService:
    """Create, change, retire, restore and read key results and their series."""

    def __init__(self, clock: Callable[[], datetime] = lambda: datetime.now(UTC)) -> None:
        """Use ``clock`` for the stamps; it is injectable for tests."""
        self._clock = clock

    # -- reading ------------------------------------------------------------------------------

    async def get(
        self, db: AsyncSession, user_id: uuid.UUID, key_result_id: uuid.UUID
    ) -> KeyResult:
        """Return one of the user's key results or raise ``NotFound``."""
        row = await db.get(KeyResult, key_result_id)
        if row is None or row.user_id != user_id:
            raise NotFound
        return row

    async def entries(self, db: AsyncSession, key_result: KeyResult) -> list[ValueEntry]:
        """Return the series of a key result as the rules see it (oldest last)."""
        rows = list(
            (
                await db.execute(
                    select(KeyResultValue)
                    .where(KeyResultValue.key_result_id == key_result.id)
                    .order_by(KeyResultValue.on_date, KeyResultValue.seq)
                )
            ).scalars()
        )
        return [ValueEntry(r.value, r.on_date, r.seq) for r in rows]

    def current(self, key_result: KeyResult, entries: Iterable[ValueEntry]) -> float:
        """Return the derived current value: the latest entry, else the start value (R-02)."""
        return current_value(key_result.start_value, list(entries))

    async def series(
        self, db: AsyncSession, user_id: uuid.UUID, key_result: KeyResult
    ) -> list[SeriesPoint]:
        """Return the full series, newest first."""
        rows = list(
            (
                await db.execute(
                    select(KeyResultValue)
                    .where(
                        KeyResultValue.key_result_id == key_result.id,
                        KeyResultValue.user_id == user_id,
                    )
                    .order_by(KeyResultValue.on_date.desc(), KeyResultValue.seq.desc())
                )
            ).scalars()
        )
        return [SeriesPoint(r.id, r.value, r.at, r.on_date, r.source, r.seq) for r in rows]

    async def value_on(
        self, db: AsyncSession, user_id: uuid.UUID, key_result_id: uuid.UUID, day: date
    ) -> ValueOn:
        """Return the last value of the series on or before ``day``, or none (FR-034).

        The start value is never assumed. Feature 007 calls this in process.
        """
        await self.get(db, user_id, key_result_id)
        rows = list(
            (
                await db.execute(
                    select(KeyResultValue)
                    .where(
                        KeyResultValue.key_result_id == key_result_id,
                        KeyResultValue.on_date <= day,
                    )
                    .order_by(KeyResultValue.on_date.desc(), KeyResultValue.seq.desc())
                    .limit(1)
                )
            ).scalars()
        )
        if not rows:
            return ValueOn(key_result_id, day, None, None, None)
        row = rows[0]
        return ValueOn(key_result_id, day, row.value, row.at, row.source)

    # -- creating and editing -----------------------------------------------------------------

    async def _next_seq(self, db: AsyncSession, key_result_id: uuid.UUID) -> int:
        highest = (
            await db.execute(
                select(func.max(KeyResultValue.seq)).where(
                    KeyResultValue.key_result_id == key_result_id
                )
            )
        ).scalar_one()
        return (highest or 0) + 1

    async def _insert_value(
        self,
        db: AsyncSession,
        key_result: KeyResult,
        *,
        value: float,
        at: datetime,
        on_date: date,
        source: ValueSource,
    ) -> KeyResultValue:
        row = KeyResultValue(
            user_id=key_result.user_id,
            key_result_id=key_result.id,
            value=value,
            at=at,
            on_date=on_date,
            source=source.value,
            seq=await self._next_seq(db, key_result.id),
        )
        db.add(row)
        await db.flush()
        return row

    def _require_active(self, key_result: KeyResult) -> None:
        if key_result.status != GoalState.ACTIVE.value:
            raise Conflict("retired", "A retired key result accepts no change.")

    async def create(
        self,
        db: AsyncSession,
        user_id: uuid.UUID,
        goal: Goal,
        *,
        metric: str,
        start_value: float,
        target: float,
        deadline: date,
        update_source: UpdateSource = UpdateSource.MANUAL,
        theme_ids: Sequence[uuid.UUID] = (),
        trees: Iterable[ConnectionTree] | None = None,
        source: str = ChangeSource.USER.value,
        position: int = 0,
    ) -> KeyResult:
        """Create a key result of an annual goal, with its links (FR-003, FR-006).

        The series starts empty: the current value is the start value. The fourth active key
        result of a goal is refused. ``trees`` checks the theme ids; ``source`` says whether
        the user or the seeding asked for it.
        """
        metric = metric.strip()
        _validate_key_result(
            metric=metric,
            start_value=start_value,
            target=target,
            deadline=deadline,
            year=goal.period_start.year,
        )
        slot = await _take_slot(db, goal.id)
        if slot is None:
            raise Conflict("key_result_limit", KEY_RESULT_LIMIT_MESSAGE)
        row = KeyResult(
            user_id=user_id,
            goal_id=goal.id,
            year=goal.period_start.year,
            metric=metric,
            start_value=start_value,
            target=target,
            deadline=deadline,
            update_source=update_source.value,
            status=GoalState.ACTIVE.value,
            slot=slot,
            position=position,
        )
        db.add(row)
        await db.flush()
        if trees is not None:
            await self._apply_links(db, user_id, row, theme_ids, trees)
        return row

    async def edit(
        self,
        db: AsyncSession,
        user_id: uuid.UUID,
        key_result: KeyResult,
        *,
        metric: str | None = None,
        target: float | None = None,
        deadline: date | None = None,
        update_source: UpdateSource | None = None,
        now: datetime | None = None,
    ) -> list[PlanChange]:
        """Change the editable fields; each changed field adds one history row (FR-018).

        ``start_value`` is not editable: the series keeps its meaning. A retired key result
        accepts no change.
        """
        self._require_active(key_result)
        now = now or self._clock()
        changes: list[PlanChange] = []
        edits: dict[str, Any] = {}
        if metric is not None:
            stripped = metric.strip()
            if not stripped or len(stripped) > 500:
                raise Invalid("The metric text must be 1 to 500 characters.", "invalid")
            edits["metric"] = stripped
        if target is not None:
            edits["target"] = target
        if deadline is not None:
            edits["deadline"] = deadline
        if update_source is not None:
            edits["update_source"] = update_source.value
        if not edits:
            return []
        # Validate the full key result with the new values (FR-005).
        _validate_key_result(
            metric=edits.get("metric", key_result.metric),
            start_value=key_result.start_value,
            target=edits.get("target", key_result.target),
            deadline=edits.get("deadline", key_result.deadline),
            year=key_result.year,
        )
        for field_name, new in edits.items():
            old = getattr(key_result, field_name)
            if _edit_text(field_name, old) == _edit_text(field_name, new):
                continue
            changes.append(
                change(
                    user_id,
                    key_result.year,
                    PlanChangeKind.KEY_RESULT_EDITED,
                    key_result_id=key_result.id,
                    field_name=field_name,
                    old_value=_edit_text(field_name, old),
                    new_value=_edit_text(field_name, new),
                )
            )
            setattr(key_result, field_name, new)
        key_result.updated_at = utcnow()
        await db.flush()
        await write_batch(
            db, changes, batch_id=uuid.uuid4(), source=ChangeSource.USER.value, now=now
        )
        return changes

    async def retire(
        self,
        db: AsyncSession,
        user_id: uuid.UUID,
        key_result: KeyResult,
        reason: str | None = None,
        *,
        dry_run: bool = False,
        today: date,
        nodes: Mapping[str, ProjectNode],
        links_of: Mapping[uuid.UUID, Sequence[KeyResultTheme]],
    ) -> RetireResult:
        """Retire a key result, or only say what that would do (``dry_run``, R-06).

        The retire frees the slot, ends its links with ``key_result_retired`` and keeps the
        series and the history (FR-021).
        """
        self._require_active(key_result)
        effect = await self.retire_effect(
            db, user_id, [key_result], reason=reason, today=today, nodes=nodes, links_of=links_of
        )
        if dry_run:
            return RetireResult(effect, None)
        now = self._clock()
        batch_id = uuid.uuid4()
        await self.retire_key_results(
            db,
            [key_result],
            reason=reason,
            now=now,
            batch_id=batch_id,
            source=ChangeSource.USER.value,
            link_reason=LinkEndReason.KEY_RESULT_RETIRED,
        )
        return RetireResult(effect, batch_id)

    async def retire_effect(
        self,
        db: AsyncSession,
        user_id: uuid.UUID,
        key_results: Sequence[KeyResult],
        *,
        reason: str | None,
        today: date,
        nodes: Mapping[str, ProjectNode],
        links_of: Mapping[uuid.UUID, Sequence[KeyResultTheme]],
    ) -> RetireEffect:
        """Compute what retiring these key results would change, without writing."""
        effect = RetireEffect(key_results_retired=len(key_results))
        names = {row.id: row.name for row in await _project_rows(db, user_id)}
        for row in key_results:
            entries = await self.entries(db, row)
            met = is_met(row.start_value, row.target, self.current(row, entries))
            links = [self._link_view(link, names) for link in links_of.get(row.id, ())]
            flags = key_result_flags(
                status=row.status,
                deadline=row.deadline,
                met=met,
                today=today,
                nodes=nodes,
                links=links,
            )
            for flag in flags:
                if flag.code not in effect.flags_removed:
                    effect.flags_removed.append(flag.code)
        effect.links_ended = sum(
            1 for row in key_results for link in links_of.get(row.id, ()) if link.ended_at is None
        )
        return effect

    async def retire_key_results(
        self,
        db: AsyncSession,
        key_results: Sequence[KeyResult],
        *,
        reason: str | None,
        now: datetime,
        batch_id: uuid.UUID,
        source: str,
        link_reason: LinkEndReason,
    ) -> list[PlanChange]:
        """Retire the given key results into ``batch_id``: fields, links and history rows.

        This is the one write path for a retire; the goal retire of ``annual_plan`` calls it
        with its own batch and ``goal_retired`` as the link reason (T033). Returns the
        ``key_result_retired`` history rows.
        """
        changes: list[PlanChange] = []
        for row in key_results:
            row.status = GoalState.RETIRED.value
            row.slot = None
            row.retired_at = now
            row.retired_reason = reason
            row.updated_at = utcnow()
            changes.append(
                change(
                    row.user_id,
                    row.year,
                    PlanChangeKind.KEY_RESULT_RETIRED,
                    goal_id=row.goal_id,
                    key_result_id=row.id,
                    reason=reason,
                )
            )
        await db.flush()
        # The links are ended first, so the ``at`` stamps of the two writes do not collide.
        links = [link for row in key_results for link in await self.active_links(db, row)]
        await end_links(db, links, link_reason, now=now, batch_id=batch_id, source=source)
        await write_batch(
            db, changes, batch_id=batch_id, source=source, now=now + MICROSECOND * (len(links) + 1)
        )
        return changes

    # -- links (FR-012, FR-013, R-04) ---------------------------------------------------------

    async def active_links(self, db: AsyncSession, key_result: KeyResult) -> list[KeyResultTheme]:
        """Return the active links of a key result, oldest first."""
        return list(
            (
                await db.execute(
                    select(KeyResultTheme)
                    .where(
                        KeyResultTheme.key_result_id == key_result.id,
                        KeyResultTheme.ended_at.is_(None),
                    )
                    .order_by(KeyResultTheme.started_at)
                )
            ).scalars()
        )

    async def all_links(self, db: AsyncSession, key_result_id: uuid.UUID) -> list[KeyResultTheme]:
        """Return every link row of a key result, active and ended, oldest first."""
        return list(
            (
                await db.execute(
                    select(KeyResultTheme)
                    .where(KeyResultTheme.key_result_id == key_result_id)
                    .order_by(KeyResultTheme.started_at, KeyResultTheme.id)
                )
            ).scalars()
        )

    def _link_view(self, link: KeyResultTheme, names: Mapping[uuid.UUID, str]) -> LinkView:
        """Return a link as the pure rules see it."""
        return LinkView(
            name=names.get(link.project_id, ""),
            key=str(link.project_id),
            active=link.ended_at is None,
        )

    def _eligible_theme_keys(
        self, trees: Iterable[ConnectionTree]
    ) -> dict[uuid.UUID, tuple[str, uuid.UUID]]:
        """Return the usable themes by row id: ``(name, connection_id)`` (FR-012).

        A theme that is orphaned, ignored, relabelled or unclassified is not usable (R-12).
        """
        from tefteri.domain.key_results import is_usable_link

        out: dict[uuid.UUID, tuple[str, uuid.UUID]] = {}
        for tree in trees:
            for row in tree.rows:
                key = str(row.id)
                if is_usable_link(tree.nodes, key):
                    out[row.id] = (row.name, tree.connection.id)
        return out

    async def _apply_links(
        self,
        db: AsyncSession,
        user_id: uuid.UUID,
        key_result: KeyResult,
        theme_ids: Sequence[uuid.UUID],
        trees: Iterable[ConnectionTree] | None,
    ) -> list[KeyResultTheme]:
        """Create the active links of a new key result. ``not_a_theme`` for a bad id (FR-012)."""
        if not theme_ids:
            return []
        if trees is None:
            raise Invalid("That project is not a live theme.", "not_a_theme")
        usable = self._eligible_theme_keys(trees)
        now = self._clock()
        batch_id = uuid.uuid4()
        links: list[KeyResultTheme] = []
        for theme_id in theme_ids:
            if theme_id not in usable:
                raise Invalid("That project is not a live theme.", "not_a_theme")
            links.append(
                await start_link(
                    db,
                    user_id,
                    key_result.id,
                    theme_id,
                    key_result.year,
                    now=now,
                    batch_id=batch_id,
                    source=ChangeSource.USER.value,
                )
            )
        return links

    async def set_themes(
        self,
        db: AsyncSession,
        user_id: uuid.UUID,
        key_result: KeyResult,
        theme_ids: Sequence[uuid.UUID],
        *,
        dry_run: bool = False,
        trees: Iterable[ConnectionTree],
        today: date,
        nodes: Mapping[str, ProjectNode],
    ) -> LinkSetEffect | None:
        """Set the active links of a key result, or only say what that would do (``dry_run``).

        Missing links are added and links that are not in the list are ended, in one batch: a
        re-link is a removal and an addition together (FR-013). A theme that is not usable now
        gives ``not_a_theme``.
        """
        self._require_active(key_result)
        usable = self._eligible_theme_keys(trees)
        wanted: dict[uuid.UUID, str] = {}
        for theme_id in theme_ids:
            if theme_id not in usable:
                raise Invalid(f"{_theme_name(trees, theme_id)} is not a live theme.", "not_a_theme")
            wanted[theme_id] = usable[theme_id][0]
        active = await self.active_links(db, key_result)
        active_by_project = {link.project_id: link for link in active}
        effect = LinkSetEffect()
        for theme_id, name in wanted.items():
            if theme_id not in active_by_project:
                effect.added.append(ThemeEntry(theme_id, name))
        for link in active:
            if link.project_id not in wanted:
                effect.ended.append(ThemeEntry(link.project_id, usable[link.project_id][0]))
        if dry_run:
            return effect
        now = self._clock()
        batch_id = uuid.uuid4()
        for entry in effect.ended:
            await end_link(
                db,
                active_by_project[entry.project_id],
                LinkEndReason.RELINKED if effect.added else LinkEndReason.REMOVED,
                now=now,
                batch_id=batch_id,
                source=ChangeSource.USER.value,
            )
        for entry in effect.added:
            await start_link(
                db,
                user_id,
                key_result.id,
                entry.project_id,
                key_result.year,
                now=now,
                batch_id=batch_id,
                source=ChangeSource.USER.value,
            )
        key_result.updated_at = utcnow()
        return effect

    # -- restoring (FR-021) -------------------------------------------------------------------

    async def restore(
        self,
        db: AsyncSession,
        user_id: uuid.UUID,
        key_result: KeyResult,
        *,
        trees: Iterable[ConnectionTree],
    ) -> RestoreResult:
        """Restore a retired key result; it needs a free slot (R-03).

        The links that its retirement batch ended start again as new rows, but only for themes
        that are still usable now; the skipped ones are listed.
        """
        if key_result.status == GoalState.ACTIVE.value:
            raise Conflict("already_retired", "This key result is not retired.")
        batch = await self._retirement_batch(db, user_id, key_result.id)
        slot = await _take_slot(db, key_result.goal_id)
        if slot is None:
            raise Conflict("key_result_limit", KEY_RESULT_LIMIT_MESSAGE)
        now = self._clock()
        batch_id = uuid.uuid4()
        restored_links, skipped = await self.restore_key_results(
            db,
            [key_result],
            batch=batch,
            now=now,
            batch_id=batch_id,
            source=ChangeSource.USER.value,
            trees=trees,
        )
        return RestoreResult(1, restored_links, skipped)

    async def restore_key_results(
        self,
        db: AsyncSession,
        key_results: Sequence[KeyResult],
        *,
        batch: uuid.UUID | None,
        now: datetime,
        batch_id: uuid.UUID,
        source: str,
        trees: Iterable[ConnectionTree],
    ) -> tuple[int, list[ThemeEntry]]:
        """Restore the given key results into one batch: fields, history and links again.

        This is the one write path for a restore; the goal restore of ``annual_plan`` calls it
        with its own batch (T033). Returns how many links came back and which themes were
        skipped because they are no longer usable (FR-021).
        """
        changes = [
            change(
                row.user_id,
                row.year,
                PlanChangeKind.KEY_RESULT_RESTORED,
                goal_id=row.goal_id,
                key_result_id=row.id,
            )
            for row in key_results
        ]
        for row in key_results:
            slot = await _take_slot(db, row.goal_id)
            if slot is None:
                raise Conflict("key_result_limit", KEY_RESULT_LIMIT_MESSAGE)
            row.status = GoalState.ACTIVE.value
            row.slot = slot
            row.retired_at = None
            row.retired_reason = None
            row.updated_at = utcnow()
        await db.flush()
        await write_batch(db, changes, batch_id=batch_id, source=source, now=now)
        links_restored = 0
        skipped: list[ThemeEntry] = []
        trees_list = list(trees)
        usable = self._eligible_theme_keys(trees_list)
        nodes: dict[str, ProjectNode] = {}
        for tree in trees_list:
            nodes.update(tree.nodes)
        for row in key_results:
            ended = list(
                (
                    await db.execute(
                        select(KeyResultTheme).where(
                            KeyResultTheme.key_result_id == row.id,
                            KeyResultTheme.batch_id == batch,
                            KeyResultTheme.ended_at.is_not(None),
                        )
                    )
                ).scalars()
            )
            for link in ended:
                if link.project_id not in usable:
                    skipped.append(ThemeEntry(link.project_id, await _name_of(db, link.project_id)))
                    continue
                await start_link(
                    db,
                    row.user_id,
                    row.id,
                    link.project_id,
                    row.year,
                    now=now,
                    batch_id=batch_id,
                    source=source,
                )
                links_restored += 1
        return links_restored, skipped

    async def _retirement_batch(
        self, db: AsyncSession, user_id: uuid.UUID, key_result_id: uuid.UUID
    ) -> uuid.UUID | None:
        """Return the batch that retired the key result, from the history."""
        row = (
            await db.execute(
                select(PlanChange)
                .where(
                    PlanChange.user_id == user_id,
                    PlanChange.key_result_id == key_result_id,
                    PlanChange.kind == PlanChangeKind.KEY_RESULT_RETIRED.value,
                )
                .order_by(PlanChange.at.desc())
                .limit(1)
            )
        ).scalar_one_or_none()
        return row.batch_id if row else None

    # -- values (FR-009, R-08) ----------------------------------------------------------------

    async def enter_value(
        self,
        db: AsyncSession,
        user_id: uuid.UUID,
        key_result: KeyResult,
        value: float,
        on_date: date | None,
        *,
        tz: str,
        source: ValueSource = ValueSource.MANUAL,
    ) -> tuple[KeyResultValue, date]:
        """Store a value of the series. Allowed in a past year too (FR-033).

        The date is today in the user time zone unless one is given; a future date is refused.
        The stamp of a past day is noon of that day in the user zone (R-08).
        """
        if key_result.status == GoalState.RETIRED.value:
            raise Conflict("retired", "A retired key result accepts no new value.")
        if not _finite(value):
            raise Invalid("The value must be a finite number.")
        zone = ZoneInfo(tz)
        today = datetime.now(zone).date()
        if on_date is None:
            on_date = today
        if on_date > today:
            raise Invalid("The date must not be in the future.", "future_date")
        at = (
            stamp_manual_value(on_date, today, zone)
            if source is ValueSource.MANUAL
            else datetime.now(zone)
        )
        row = await self._insert_value(
            db, key_result, value=value, at=at, on_date=on_date, source=source
        )
        return row, on_date


def _finite(value: float) -> bool:
    return value == value and value not in (float("inf"), float("-inf"))


def _validate_key_result(
    *, metric: str, start_value: float, target: float, deadline: date, year: int
) -> None:
    """Turn a domain ``ValidationError`` into the API answer (FR-005)."""
    try:
        validate(
            metric=metric, start_value=start_value, target=target, deadline=deadline, year=year
        )
    except ValidationError as exc:
        raise Invalid(exc.args[0], "invalid") from exc


async def _take_slot(db: AsyncSession, goal_id: uuid.UUID) -> int | None:
    """Return the lowest free slot of the goal, or ``None`` when all three are taken (R-03)."""
    taken = list(
        (
            await db.execute(
                select(KeyResult.slot).where(
                    KeyResult.goal_id == goal_id, KeyResult.status == GoalState.ACTIVE.value
                )
            )
        ).scalars()
    )
    return next_free_slot(taken)


def _edit_text(field_name: str, value: Any) -> str:
    """Return an old or new value of an edit as the history stores it."""
    if field_name == "deadline" and isinstance(value, date):
        return value.isoformat()
    return str(value)


async def _trees_for(db: AsyncSession, user_id: uuid.UUID) -> list[ConnectionTree]:
    from tefteri.services.project_labels import load_trees

    return await load_trees(db, user_id)


def _theme_name(trees: Iterable[ConnectionTree], theme_id: uuid.UUID) -> str:
    for tree in trees:
        for row in tree.rows:
            if row.id == theme_id:
                return row.name
    return "That project"


async def _project_rows(db: AsyncSession, user_id: uuid.UUID) -> Sequence[ProjectLabelRow]:
    return list(
        (
            await db.execute(select(ProjectLabelRow).where(ProjectLabelRow.user_id == user_id))
        ).scalars()
    )


async def _name_of(db: AsyncSession, project_id: uuid.UUID) -> str:
    """Return the stored name of a project, or a placeholder."""
    row = await db.get(ProjectLabelRow, project_id)
    return row.name if row else "That project"


async def integrity_to_limit(call: Callable[[], Any]) -> Any:
    """Run a write and turn the slot clash of the database into ``key_result_limit`` (R-03)."""
    try:
        return await call()
    except IntegrityError as exc:
        if "uq_key_results_goal_slot" in str(exc):
            raise Conflict("key_result_limit", KEY_RESULT_LIMIT_MESSAGE) from exc
        raise


def progress_of(key_result: KeyResult, current: float) -> float:
    """Return the progress of a key result (not capped, R-11)."""
    return progress(key_result.start_value, key_result.target, current)


def met_of(key_result: KeyResult, current: float) -> bool:
    """Return whether the key result is met (R-11)."""
    return is_met(key_result.start_value, key_result.target, current)


def overdue_of(key_result: KeyResult, current: float, today: date) -> bool:
    """Return whether the key result is overdue today (R-11)."""
    return is_overdue(
        key_result.deadline,
        today,
        met=met_of(key_result, current),
        active=key_result.status == GoalState.ACTIVE.value,
    )
