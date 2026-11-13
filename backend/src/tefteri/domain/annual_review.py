"""Pure rules of the annual review (spec 008). No database and no adapter import.

The review reads stored monthly snapshots and the annual plan. Every value on the screen is
derived here from those stored values; nothing is recomputed from tasks. The functions are
tolerant: missing or old data gives ``None`` or a gap and never raises.

Feature 005 owns :func:`tefteri.domain.work_categories.percentages`, feature 006 owns
:func:`tefteri.domain.key_results.is_met` and :func:`tefteri.domain.annual_plan.year_state`.
They are imported, never restated.
"""

from collections.abc import Iterable, Mapping, Sequence
from dataclasses import dataclass
from datetime import UTC, date, datetime, time, timedelta
from zoneinfo import ZoneInfo

from tefteri.domain.enums import (
    DeadlineState,
    KeyResultOutcome,
    MonthStatus,
    ThemeHint,
)
from tefteri.domain.key_results import is_met
from tefteri.domain.snapshot_view import KeyResultEntry, SnapshotView
from tefteri.domain.work_categories import CategoryCounts, Percentages, percentages

MONTHS = tuple(f"{number:02d}" for number in range(1, 13))
"""The twelve month numbers of a year, as used in ``YYYY-MM`` keys."""

DIFFER_THRESHOLD = 0.25
"""The share below (or above) which milestone work and movement "differ strongly" (R-05)."""


def month_key(value: object) -> str:
    """Return ``YYYY-MM`` for a snapshot month, a date or an ISO string, or ``""``."""
    if isinstance(value, datetime | date):
        return value.strftime("%Y-%m")
    if isinstance(value, str) and len(value) >= 7:
        try:
            date.fromisoformat(f"{value[:7]}-01")
        except ValueError:
            return ""
        return value[:7]
    return ""


def months_of(year: int) -> list[str]:
    """Return the twelve month keys of ``year``."""
    return [f"{year}-{month}" for month in MONTHS]


def month_end(month: str) -> date:
    """Return the last day of a ``YYYY-MM`` month."""
    start = date.fromisoformat(f"{month}-01")
    if start.month == 12:
        return date(start.year, 12, 31)
    return date(start.year, start.month + 1, 1) - timedelta(days=1)


def end_of_day(day: date, tz: ZoneInfo | None = None) -> datetime:
    """Return the last instant of ``day`` in ``tz`` (UTC by default)."""
    zone = tz or UTC
    return datetime.combine(day, time(23, 59, 59, 999999), zone)


# -- outcomes --------------------------------------------------------------------------------


@dataclass(frozen=True)
class LastValue:
    """The last stored snapshot value of a key result in the year."""

    value: float
    month: str
    at: datetime


def _entry_at(snapshot: SnapshotView, key_result_id: str) -> KeyResultEntry | None:
    return snapshot.key_results.get(key_result_id)


def last_value(
    snapshots: Sequence[SnapshotView], key_result_id: str
) -> LastValue | None:
    """Return the newest snapshot value with a time stamp, or ``None`` (FR-003, R-03).

    The start value is never used: a key result with no stored value has no last value. The
    month is the ``month`` of the snapshot, never the time stamp of the value.
    """
    best: LastValue | None = None
    for snapshot in snapshots:
        month = month_key(snapshot.month)
        entry = _entry_at(snapshot, key_result_id)
        if not month or entry is None:
            continue
        if entry.latest_value is None or entry.latest_at is None:
            continue
        candidate = LastValue(float(entry.latest_value), month, entry.latest_at)
        if best is None or month >= best.month:
            best = candidate
    return best


def key_result_outcome(
    *,
    year_state: str,
    key_result_status: str,
    goal_status: str,
    start_value: float,
    target: float,
    last: LastValue | None,
) -> KeyResultOutcome:
    """Return the fixed outcome of one key result (FR-003, FR-013, R-03).

    A retired key result or goal is ``retired`` and is never ``missed``. The current year is
    ``in_progress``: no final result is claimed before the year has ended. Without a stored value
    the outcome is ``no_value`` and the start value is never shown as a last value.
    """
    if key_result_status != "active" or goal_status != "active":
        return KeyResultOutcome.RETIRED
    if year_state == "current":
        return KeyResultOutcome.IN_PROGRESS
    if last is None:
        return KeyResultOutcome.NO_VALUE
    if is_met(start_value, target, last.value):
        return KeyResultOutcome.HIT
    return KeyResultOutcome.MISSED


@dataclass(frozen=True)
class DeadlineLine:
    """The "reached by deadline" line of one key result (FR-025)."""

    state: DeadlineState
    value: float | None = None
    month: str | None = None


def deadline_line(
    snapshots: Sequence[SnapshotView],
    key_result_id: str,
    *,
    start_value: float,
    target: float,
    deadline: date | None,
    year: int,
    today: date,
    tz: ZoneInfo | None = None,
) -> DeadlineLine:
    """Return whether the last value on or before the deadline reached the target (R-03).

    ``open`` means the deadline is after the stored data or after the year end, or it is still
    in the future in the year in progress. ``no_value`` means nothing was stored by the deadline.
    The line never changes the hit or missed outcome.
    """
    if deadline is None:
        return DeadlineLine(DeadlineState.OPEN)
    snapshot_months = sorted({month_key(s.month) for s in snapshots if month_key(s.month)})
    stored_until = month_end(snapshot_months[-1]) if snapshot_months else None
    year_end = date(year, 12, 31)
    if deadline > year_end:
        return DeadlineLine(DeadlineState.OPEN)
    if today < deadline:
        return DeadlineLine(DeadlineState.OPEN)
    if stored_until is None or deadline > stored_until:
        return DeadlineLine(DeadlineState.OPEN)
    limit = end_of_day(deadline, tz)
    best: tuple[str, datetime, KeyResultEntry] | None = None
    for snapshot in snapshots:
        month = month_key(snapshot.month)
        entry = _entry_at(snapshot, key_result_id)
        if entry is None or entry.latest_value is None or entry.latest_at is None:
            continue
        at = entry.latest_at
        if at.tzinfo is None:
            at = at.replace(tzinfo=UTC)
        if at > limit:
            continue
        if best is None or (month, at) >= (best[0], best[1]):
            best = (month, at, entry)
    if best is None:
        return DeadlineLine(DeadlineState.NO_VALUE)
    month, _, entry = best
    value = float(entry.latest_value or 0.0)
    state = (
        DeadlineState.REACHED
        if is_met(start_value, target, value)
        else DeadlineState.NOT_REACHED
    )
    return DeadlineLine(state, value, month)


# -- the series -------------------------------------------------------------------------------


def month_statuses(
    year: int, stored_months: Iterable[object], today: date
) -> list[MonthStatus]:
    """Return the status of the twelve months of ``year`` (FR-010, R-13).

    A stored month is ``stored``; a month before today's month without a snapshot is ``missing``;
    the current month without a snapshot is ``open``; a later month is ``future``.
    """
    stored = {month_key(month) for month in stored_months}
    statuses: list[MonthStatus] = []
    for month in months_of(year):
        if month in stored:
            statuses.append(MonthStatus.STORED)
        elif (year, int(month[-2:])) < (today.year, today.month):
            statuses.append(MonthStatus.MISSING)
        elif (year, int(month[-2:])) == (today.year, today.month):
            statuses.append(MonthStatus.OPEN)
        else:
            statuses.append(MonthStatus.FUTURE)
    return statuses


@dataclass(frozen=True)
class SeriesPoint:
    """One month of the twelve point series of a key result (FR-004)."""

    month: str
    status: MonthStatus
    value: float | None
    not_stored: bool = False


def series(
    snapshots: Sequence[SnapshotView],
    key_result_id: str,
    *,
    year: int,
    today: date,
) -> list[SeriesPoint]:
    """Return twelve points, one per month, with gaps left as gaps (FR-004, R-13)."""
    by_month = {month_key(s.month): s for s in snapshots if month_key(s.month)}
    statuses = month_statuses(year, by_month, today)
    points: list[SeriesPoint] = []
    for month, status in zip(months_of(year), statuses, strict=True):
        snapshot = by_month.get(month)
        if snapshot is None:
            points.append(SeriesPoint(month, status, None))
            continue
        entry = _entry_at(snapshot, key_result_id)
        if entry is None or entry.latest_value is None:
            points.append(SeriesPoint(month, status, None, not_stored=True))
            continue
        points.append(SeriesPoint(month, status, float(entry.latest_value)))
    return points


@dataclass(frozen=True)
class Peak:
    """The best value in the direction of the target, with its month."""

    value: float
    month: str


def peak(points: Sequence[SeriesPoint], start_value: float, target: float) -> Peak | None:
    """Return the best value of the series, or ``None`` when it equals the last value.

    The direction is the one from the start value to the target. A gap is never filled.
    """
    known = [point for point in points if point.value is not None]
    if not known:
        return None
    if target > start_value:
        best = max(known, key=lambda point: (point.value or 0.0, point.month))
    else:
        best = min(known, key=lambda point: (point.value or 0.0, point.month))
    last = known[-1]
    if best.value == last.value:
        return None
    return Peak(float(best.value or 0.0), best.month)


# -- links and contributions ------------------------------------------------------------------


@dataclass(frozen=True)
class MonthRange:
    """One active range of a link, with the months it covers (FR-006)."""

    start: date
    end: date | None
    months: list[str]


def link_months(start: date, end: date | None, year: int) -> list[str]:
    """Return the months of ``year`` in which a link was active (R-04)."""
    first = max(start, date(year, 1, 1))
    last = min(end or date(year, 12, 31), date(year, 12, 31))
    if first > last:
        return []
    out: list[str] = []
    cursor = date(first.year, first.month, 1)
    while cursor <= last:
        key = cursor.strftime("%Y-%m")
        if key >= first.strftime("%Y-%m") and key <= last.strftime("%Y-%m"):
            out.append(key)
        cursor = date(cursor.year + (cursor.month == 12), cursor.month % 12 + 1, 1)
    return out


@dataclass(frozen=True)
class Movement:
    """The movement of a key result over the months of one theme link (R-05)."""

    from_value: float
    to_value: float
    fraction: float
    months: int


def movement(
    *,
    start_value: float,
    target: float,
    first_base: float | None,
    last_value: float | None,
    months: int,
    complete: bool = True,
) -> Movement | None:
    """Return the movement and its signed fraction, or ``None`` when it cannot be shown.

    The span is ``target - start_value``; the sign of the direction makes a move away negative.
    A month without a value, a zero span or an empty month list gives ``None``.
    """
    if not complete or months <= 0 or first_base is None or last_value is None:
        return None
    span = target - start_value
    if span == 0:
        return None
    move = last_value - first_base
    return Movement(float(first_base), float(last_value), move / span, months)


def theme_hint(
    *,
    shipped: int,
    target_sum: int | None,
    move: Movement | None,
    months_with_target: int,
) -> ThemeHint | None:
    """Return the neutral hint for a theme contribution, or ``None`` (FR-007, R-05).

    No hint with a zero span, with no month that holds a theme target, or with an incomplete
    movement. The mirror hint needs no shipped milestone and a movement of at least 25%.
    """
    if move is None or months_with_target == 0 or target_sum is None or target_sum <= 0:
        return None
    if shipped >= 1 and shipped >= target_sum and move.fraction < DIFFER_THRESHOLD:
        return ThemeHint.MUCH_SHIPPED_LITTLE_MOVEMENT
    if shipped == 0 and move.fraction >= DIFFER_THRESHOLD:
        return ThemeHint.MOVEMENT_NOT_FROM_THEME
    return None


@dataclass(frozen=True)
class ThemeContribution:
    """What one theme did for one key result (FR-005, FR-006)."""

    project_id: str | None
    name: str
    ranges: list[MonthRange]
    shipped: int
    shipped_outside_focus: int
    target_sum: int | None
    months_with_target: int
    move: Movement | None
    hint: ThemeHint | None
    milestones: list[object]


def contribution(
    *,
    project_id: str | None,
    name: str,
    ranges: Sequence[MonthRange],
    snapshots: Sequence[SnapshotView],
    key_result_id: str,
    start_value: float,
    target: float,
) -> ThemeContribution:
    """Build the contribution of one theme link from stored snapshots (R-04, R-05)."""
    active_months = {month for month_range in ranges for month in month_range.months}
    by_month = {month_key(s.month): s for s in snapshots if month_key(s.month)}
    shipped = 0
    outside = 0
    target_sum = 0
    months_with_target = 0
    milestones: list[object] = []
    for month in sorted(active_months):
        snapshot = by_month.get(month)
        if snapshot is None:
            continue
        theme = next(
            (
                entry
                for entry in snapshot.themes
                if (entry.project_id or "") == (project_id or "")
            ),
            None,
        )
        if theme is not None:
            for milestone in theme.milestones:
                if milestone.done_on is None:
                    continue
                if any(
                    month_range.start <= milestone.done_on <= (month_range.end or date.max)
                    for month_range in ranges
                ):
                    shipped += 1
                    milestones.append(milestone)
            if theme.target is not None:
                target_sum += theme.target
                months_with_target += 1
        for outside_entry in snapshot.outside_focus:
            if (outside_entry.theme_project_id or "") != (project_id or ""):
                continue
            if outside_entry.done_on is None:
                continue
            if any(
                month_range.start <= outside_entry.done_on <= (month_range.end or date.max)
                for month_range in ranges
            ):
                outside += 1
    first_base: float | None = None
    last: float | None = None
    complete = True
    known_months = [month for month in sorted(active_months) if month in by_month]
    for index, month in enumerate(known_months):
        entry = _entry_at(by_month[month], key_result_id)
        if entry is None:
            complete = False
            continue
        if index == 0:
            first_base = entry.base_value
        last = entry.latest_value
        if entry.latest_value is None or entry.base_value is None:
            complete = False
    move = movement(
        start_value=start_value,
        target=target,
        first_base=first_base,
        last_value=last,
        months=len(known_months),
        complete=complete,
    )
    return ThemeContribution(
        project_id=project_id,
        name=name,
        ranges=list(ranges),
        shipped=shipped,
        shipped_outside_focus=outside,
        target_sum=target_sum if months_with_target else None,
        months_with_target=months_with_target,
        move=move,
        hint=theme_hint(
            shipped=shipped,
            target_sum=target_sum if months_with_target else None,
            move=move,
            months_with_target=months_with_target,
        ),
        milestones=milestones,
    )


def distinct_milestones(snapshots: Sequence[SnapshotView]) -> int:
    """Return the number of distinct milestone ids over all snapshots (FR-006)."""
    found: set[str] = set()
    for snapshot in snapshots:
        for theme in snapshot.themes:
            for milestone in theme.milestones:
                if milestone.milestone_id:
                    found.add(milestone.milestone_id)
        for outside in snapshot.outside_focus:
            if outside.milestone_id:
                found.add(outside.milestone_id)
    return len(found)


# -- the year split ---------------------------------------------------------------------------


@dataclass(frozen=True)
class SplitMonth:
    """One month row of the year split."""

    month: str
    status: MonthStatus
    counts: CategoryCounts | None
    not_stored: bool


@dataclass(frozen=True)
class YearSplit:
    """The sum of the stored category counts of the months that hold them (FR-008)."""

    months_covered: int
    counts: CategoryCounts
    hidden: int
    percentages: Percentages
    months: list[SplitMonth]
    total: int


def year_split(
    snapshots: Sequence[SnapshotView], *, year: int, today: date
) -> YearSplit:
    """Build the year split from stored counts only; the hidden count stays apart (R-06)."""
    by_month = {month_key(s.month): s for s in snapshots if month_key(s.month)}
    statuses = month_statuses(year, by_month, today)
    rows: list[SplitMonth] = []
    total_counts = CategoryCounts()
    covered = 0
    for month, status in zip(months_of(year), statuses, strict=True):
        snapshot = by_month.get(month)
        counts = snapshot.categories if snapshot is not None else None
        if snapshot is not None and counts is None:
            rows.append(SplitMonth(month, status, None, True))
            continue
        if counts is None:
            rows.append(SplitMonth(month, status, None, False))
            continue
        rows.append(SplitMonth(month, status, counts, False))
        total_counts = total_counts + counts
        covered += 1
    return YearSplit(
        months_covered=covered,
        counts=total_counts,
        hidden=total_counts.hidden,
        percentages=percentages(total_counts),
        months=rows,
        total=total_counts.total,
    )


# -- coverage and empty state -----------------------------------------------------------------


@dataclass(frozen=True)
class Coverage:
    """How many months of the year hold a snapshot (FR-010)."""

    stored: int
    expected: int
    missing: list[str]


def coverage(statuses: Sequence[MonthStatus], *, year: int, today: date) -> Coverage:
    """Return the stored, expected and missing months of the review (R-13)."""
    stored = sum(1 for status in statuses if status is MonthStatus.STORED)
    if year < today.year:
        expected = 12
    elif year == today.year:
        expected = today.month
    else:
        expected = 0
    missing = [
        month
        for month, status in zip(months_of(year), statuses, strict=True)
        if status is MonthStatus.MISSING
    ]
    return Coverage(stored, expected, missing)


def empty_reason(
    *,
    year_state: str,
    goals: int,
    snapshots: int,
) -> str | None:
    """Return the empty reason of the review, or ``None`` when it has data (FR-011, R-13)."""
    if year_state == "future":
        return "future_year"
    if snapshots == 0 and goals == 0:
        return "no_goals"
    if snapshots == 0:
        return "no_snapshots"
    return None


def moved_after_snapshot(
    last: LastValue | None,
    *,
    current_value: float | None,
    current_at: datetime | None,
    year_state: str,
) -> dict[str, object] | None:
    """Return the live newer value of a past year, or ``None`` (FR-029)."""
    if year_state != "past" or last is None or current_value is None or current_at is None:
        return None
    at = current_at
    if at.tzinfo is None:
        at = at.replace(tzinfo=UTC)
    last_at = last.at
    if last_at.tzinfo is None:
        last_at = last_at.replace(tzinfo=UTC)
    if at <= last_at or float(current_value) == last.value:
        return None
    return {"value": float(current_value), "at": at}


def counts_by_month(snapshots: Sequence[SnapshotView]) -> Mapping[str, CategoryCounts]:
    """Return the stored category counts by month, for the service and the split."""
    return {
        month_key(snapshot.month): snapshot.categories
        for snapshot in snapshots
        if month_key(snapshot.month) and snapshot.categories is not None
    }
