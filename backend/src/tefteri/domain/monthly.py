"""Pure domain rules and immutable values for monthly planning and review.

This module depends only on the standard library and the domain enums. It has no database,
service, or task-provider knowledge so the same rules can build live views and saved snapshots.
"""

from collections.abc import Iterable, Mapping, Sequence
from dataclasses import dataclass
from datetime import UTC, date, datetime, tzinfo

from tefteri.domain.enums import (
    CountNote,
    FocusChangeKind,
    FocusEntryStatus,
    KeyResultUpdate,
    MonthState,
    TargetMarker,
    ThemeDecision,
    TrendState,
)

type Identifier = str


class InvalidTarget(ValueError):
    """A monthly target is not empty or a non-negative whole number."""


def parse_target(raw: object) -> int | None:
    """Parse a blank or non-negative whole milestone count, rejecting booleans and decimals."""
    if raw is None:
        return None
    if isinstance(raw, bool):
        raise InvalidTarget("A target must be a whole number of milestones, 0 or more.")
    if isinstance(raw, int):
        if raw >= 0:
            return raw
        raise InvalidTarget("A target must be a whole number of milestones, 0 or more.")
    if isinstance(raw, str):
        value = raw.strip()
        if not value:
            return None
        if value.isascii() and value.isdigit():
            return int(value)
    raise InvalidTarget("A target must be a whole number of milestones, 0 or more.")


def result_marker(target: int | None, done: int) -> TargetMarker:
    """Compare the count of done milestones with an optional target."""
    if target is None:
        return TargetMarker.NO_TARGET
    if done < target:
        return TargetMarker.MISSED
    if done == target:
        return TargetMarker.MET
    return TargetMarker.BEATEN


def count_note(count: int) -> CountNote | None:
    """Return soft guidance for a focus count; this rule never rejects a plan."""
    if count == 0:
        return CountNote.EMPTY
    if count < 3:
        return CountNote.BELOW
    if count > 5:
        return CountNote.ABOVE
    return None


def month_bounds(month: date) -> tuple[date, date]:
    """Return the local inclusive start and exclusive end dates for the month containing month."""
    start = date(month.year, month.month, 1)
    end = date(month.year + 1, 1, 1) if month.month == 12 else date(month.year, month.month + 1, 1)
    return start, end


def month_state(month: date, today: date) -> MonthState:
    """Classify a month by its first day and the user's local date today."""
    start, _ = month_bounds(month)
    today_start, _ = month_bounds(today)
    if start < today_start:
        return MonthState.PAST
    if start > today_start:
        return MonthState.FUTURE
    return MonthState.CURRENT


def local_day(value: datetime, tz: tzinfo) -> date:
    """Return the calendar date of a timestamp in the user's time zone."""
    if value.tzinfo is None:
        value = value.replace(tzinfo=UTC)
    return value.astimezone(tz).date()


def planning_year_of(month: date) -> int:
    """Return the planning year that owns the month."""
    return month.year


@dataclass(frozen=True)
class DoneMilestone:
    """A milestone that is already known to be done, with its local done date and theme at done."""

    id: Identifier
    name: str
    done_on: date
    theme_project_id: Identifier | None

    @property
    def milestone_id(self) -> Identifier:
        """Return the stable id using the snapshot field's name."""
        return self.id


@dataclass(frozen=True)
class EntryWindow:
    """The count window and copied display facts for a monthly focus entry."""

    project_id: Identifier
    name: str
    target: int | None
    counts_from: date
    left_on: date | None = None
    left_reason: FocusEntryStatus | None = None


@dataclass(frozen=True)
class ThemeResult:
    """The completed milestones counted for one focus entry."""

    project_id: Identifier
    name: str
    target: int | None
    counts_from: date
    left_on: date | None
    milestones: tuple[DoneMilestone, ...]
    earlier_not_counted: tuple[DoneMilestone, ...]
    marker: TargetMarker

    @property
    def done(self) -> int:
        """Return the number of counted milestones."""
        return len(self.milestones)


@dataclass(frozen=True)
class OutsideItem:
    """A done milestone that did not count toward a focus entry."""

    milestone: DoneMilestone
    theme_project_id: Identifier | None
    theme_name: str | None


def classify_done(
    month: date,
    entries: Sequence[EntryWindow],
    milestones: Iterable[DoneMilestone],
) -> tuple[tuple[ThemeResult, ...], tuple[OutsideItem, ...]]:
    """Split done milestones into counted, earlier-not-counted, and outside-focus results.

    The caller supplies only milestones in state ``done``. The theme stored on each milestone is
    authoritative; a later project move does not change the result.
    """
    start, end = month_bounds(month)
    by_project = {entry.project_id: entry for entry in entries}
    counted: dict[str, list[DoneMilestone]] = {entry.project_id: [] for entry in entries}
    earlier: dict[str, list[DoneMilestone]] = {entry.project_id: [] for entry in entries}
    outside: list[OutsideItem] = []
    for milestone in milestones:
        if milestone.done_on < start or milestone.done_on >= end:
            continue
        project_id = milestone.theme_project_id
        entry = by_project.get(project_id) if project_id is not None else None
        if entry is None:
            outside.append(OutsideItem(milestone, project_id, None))
        elif milestone.done_on < entry.counts_from:
            earlier[entry.project_id].append(milestone)
        elif entry.left_on is not None and milestone.done_on > entry.left_on:
            outside.append(OutsideItem(milestone, entry.project_id, entry.name))
        else:
            counted[entry.project_id].append(milestone)

    results = tuple(
        ThemeResult(
            project_id=entry.project_id,
            name=entry.name,
            target=entry.target,
            counts_from=entry.counts_from,
            left_on=entry.left_on,
            milestones=tuple(counted[entry.project_id]),
            earlier_not_counted=tuple(earlier[entry.project_id]),
            marker=result_marker(entry.target, len(counted[entry.project_id])),
        )
        for entry in entries
    )
    return results, tuple(outside)


@dataclass(frozen=True)
class SeriesValue:
    """One value in a key result series, ordered by local date and sequence."""

    value: float
    on_date: date
    at: datetime
    seq: int


def _latest_value(values: Iterable[SeriesValue]) -> SeriesValue | None:
    """Return the latest series value by local date and sequence."""
    return max(values, key=lambda value: (value.on_date, value.seq), default=None)


def key_result_status(
    latest_at: datetime | None, month_start: date, tz: tzinfo = UTC
) -> KeyResultUpdate:
    """Return updated when a series value is dated on or after the month's first local day."""
    if latest_at is not None and local_day(latest_at, tz) >= month_start:
        return KeyResultUpdate.UPDATED
    return KeyResultUpdate.NOT_UPDATED


def after_month_end(latest_at: datetime | None, month_end: date, tz: tzinfo = UTC) -> bool:
    """Return whether the latest series value is dated on or after the exclusive month end."""
    return latest_at is not None and local_day(latest_at, tz) >= month_end


def base_value(start_value: float, values: Iterable[SeriesValue], month_start: date) -> float:
    """Return the latest series value dated on or before month start, else the start value."""
    base = max(
        (value for value in values if value.on_date <= month_start),
        key=lambda value: (value.on_date, value.seq),
        default=None,
    )
    return start_value if base is None else base.value


def key_result_change(latest_value: float, base: float) -> float:
    """Return the difference between the latest key result value and its month base."""
    return latest_value - base


def shared_key_results(
    linked_themes: Mapping[Identifier, Iterable[Identifier]],
    focus_theme_ids: Iterable[Identifier],
) -> frozenset[Identifier]:
    """Return key result ids linked to more than one of the month's focus themes."""
    in_focus = set(focus_theme_ids)
    return frozenset(
        key_result_id
        for key_result_id, theme_ids in linked_themes.items()
        if len(in_focus.intersection(theme_ids)) > 1
    )


def key_result_flags(
    usable_linked_theme_ids: Iterable[Identifier],
    focus_theme_ids: Iterable[Identifier],
    existing_flags: Iterable[str] = (),
) -> tuple[str, ...]:
    """Keep 006 flags and add ``no_theme_in_focus`` when no usable linked theme is in focus."""
    flags = list(dict.fromkeys(existing_flags))
    if (
        not set(usable_linked_theme_ids).intersection(focus_theme_ids)
        and "no_theme_in_focus" not in flags
    ):
        flags.append("no_theme_in_focus")
    return tuple(flags)


@dataclass(frozen=True)
class CategoryCounts:
    """Monthly work-category counts; hidden tasks are excluded from the work total."""

    goal_aligned: int = 0
    maintenance: int = 0
    off_plan: int = 0
    hidden: int = 0

    @property
    def total(self) -> int:
        """Return the total of visible work categories, excluding hidden tasks."""
        return self.goal_aligned + self.maintenance + self.off_plan


def off_plan_share(counts: CategoryCounts) -> float | None:
    """Return the off-plan proportion of visible completed work, or None when there is no work."""
    if counts.total == 0:
        return None
    return counts.off_plan / counts.total


def trend(current: CategoryCounts, previous: Sequence[CategoryCounts]) -> TrendState:
    """Compare current off-plan share strictly with the two immediately preceding months."""
    if len(previous) != 2:
        return TrendState.NOT_ENOUGH_HISTORY
    current_share = off_plan_share(current)
    previous_shares = tuple(off_plan_share(counts) for counts in previous)
    if current_share is None or any(share is None for share in previous_shares):
        return TrendState.NOT_ENOUGH_HISTORY
    if all(current_share > share for share in previous_shares if share is not None):
        return TrendState.RISING
    return TrendState.NOT_RISING


@dataclass(frozen=True)
class DecisionInput:
    """A review decision and the theme data needed for suggestions and snapshots."""

    project_id: Identifier
    name: str
    decision: ThemeDecision
    target: int | None = None
    replacement_project_id: Identifier | None = None
    replacement_name: str | None = None


@dataclass(frozen=True)
class SuggestionEligibility:
    """Whether a proposed next-month theme can still be selected."""

    eligible: bool
    reason: str | None = None


@dataclass(frozen=True)
class SuggestionResult:
    """Next-month suggestions, ineligible suggestions, and their source month."""

    from_month: date | None
    suggestions: tuple[dict[str, object], ...]
    skipped: tuple[dict[str, str], ...]


def decision_effect(
    decision: ThemeDecision, *, target: int | None = None, replacement_name: str | None = None
) -> str:
    """Return one plain sentence explaining the effect of a month-end decision."""
    if decision is ThemeDecision.CARRY:
        if target is None:
            return "Carry this theme into next month with no target."
        noun = "milestone" if target == 1 else "milestones"
        return f"Carry this theme into next month with a target of {target} {noun}."
    if decision is ThemeDecision.DROP:
        return "Drop this theme next month."
    if decision is ThemeDecision.REPLACE:
        if replacement_name is None:
            raise ValueError("A replacement decision needs a replacement theme name.")
        return f"Replace this theme with {replacement_name} next month."
    return "Decide about this theme later."


def build_suggestions(
    month: date,
    from_month: date | None,
    decisions: Iterable[DecisionInput],
    eligibility: Mapping[Identifier, SuggestionEligibility],
) -> SuggestionResult:
    """Build next-month suggestions from carry and replace decisions in a saved review."""
    suggestions: list[dict[str, object]] = []
    skipped: list[dict[str, str]] = []
    if from_month is None:
        return SuggestionResult(None, (), ())

    for item in decisions:
        if item.decision is ThemeDecision.CARRY:
            proposed_id, proposed_name = item.project_id, item.name
            proposed_target = item.target
            reason = "carry"
            replaces = None
        elif item.decision is ThemeDecision.REPLACE:
            if item.replacement_project_id is None or item.replacement_name is None:
                continue
            proposed_id, proposed_name = item.replacement_project_id, item.replacement_name
            proposed_target = None
            reason = "replace"
            replaces = {"project_id": item.project_id, "name": item.name}
        else:
            continue

        eligible = eligibility.get(proposed_id, SuggestionEligibility(False, "missing"))
        if not eligible.eligible:
            skipped.append(
                {
                    "project_id": proposed_id,
                    "name": proposed_name,
                    "reason": eligible.reason or "ineligible",
                }
            )
            continue
        suggestions.append(
            {
                "project_id": proposed_id,
                "name": proposed_name,
                "target": proposed_target,
                "reason": reason,
                "replaces": replaces,
            }
        )
    return SuggestionResult(from_month, tuple(suggestions), tuple(skipped))


@dataclass(frozen=True)
class ThemeInput:
    """Stored theme facts used to create one theme section of the review snapshot."""

    project_id: Identifier
    name: str
    target: int | None
    counts_from: date
    done: tuple[DoneMilestone, ...] = ()
    earlier_not_counted: tuple[DoneMilestone, ...] = ()
    left_on: date | None = None
    status: FocusEntryStatus = FocusEntryStatus.IN_FOCUS
    orphaned: str | None = None
    label_changed: str | None = None
    key_result_ids: tuple[Identifier, ...] = ()


@dataclass(frozen=True)
class FocusChangeInput:
    """One immutable focus-change fact included in a monthly snapshot."""

    kind: FocusChangeKind
    changed_on: date
    out_project_id: Identifier | None = None
    out_name: str | None = None
    in_project_id: Identifier | None = None
    in_name: str | None = None
    target_before: int | None = None
    target_after: int | None = None
    undone: bool = False


@dataclass(frozen=True)
class OutsideFocusInput:
    """A milestone outside the focus, including its done-time theme identity."""

    milestone: DoneMilestone
    theme_name: str | None = None


@dataclass(frozen=True)
class KeyResultInput:
    """The values and saved facts for one key result at review time."""

    key_result_id: Identifier
    goal_id: Identifier
    goal_title: str
    metric: str
    update_source: str
    start_value: float
    base_value: float
    latest_value: float
    latest_at: datetime | None
    target: float
    deadline: date
    theme_ids: tuple[Identifier, ...] = ()
    status: KeyResultUpdate = KeyResultUpdate.NOT_UPDATED
    entered_in_review: bool = False
    after_month_end: bool = False
    past_deadline: bool = False
    retired: bool = False
    shared: bool = False
    flags: tuple[str, ...] = ()


@dataclass(frozen=True)
class MonthlyReviewInput:
    """All already-loaded facts for a version-one monthly review snapshot."""

    month: date
    taken_at: datetime
    themes: tuple[ThemeInput, ...]
    changes: tuple[FocusChangeInput, ...] = ()
    outside_focus: tuple[OutsideFocusInput, ...] = ()
    categories: CategoryCounts = CategoryCounts()
    key_results: tuple[KeyResultInput, ...] = ()
    decisions: tuple[DecisionInput, ...] = ()


def _iso_date(value: date | None) -> str | None:
    """Serialize a date as an ISO date string."""
    return value.isoformat() if value is not None else None


def _iso_datetime(value: datetime | None) -> str | None:
    """Serialize a timestamp in UTC with the JSON-friendly Z suffix."""
    if value is None:
        return None
    utc = value.astimezone(UTC) if value.tzinfo else value.replace(tzinfo=UTC)
    return utc.isoformat().replace("+00:00", "Z")


def _milestone_payload(milestone: DoneMilestone) -> dict[str, object]:
    """Serialize the immutable milestone facts of a snapshot item."""
    return {
        "milestone_id": milestone.id,
        "name": milestone.name,
        "done_on": milestone.done_on.isoformat(),
    }


def _theme_payload(theme: ThemeInput) -> dict[str, object]:
    """Serialize one focus entry with counts and names from the review input."""
    marker = result_marker(theme.target, len(theme.done))
    orphan = None if theme.orphaned is None else {"reason": theme.orphaned}
    return {
        "project_id": theme.project_id,
        "name": theme.name,
        "target": theme.target,
        "counts_from": theme.counts_from.isoformat(),
        "left_on": _iso_date(theme.left_on),
        "status": theme.status.value,
        "orphaned": orphan,
        "label_changed": theme.label_changed,
        "done": len(theme.done),
        "marker": marker.value,
        "milestones": [_milestone_payload(item) for item in theme.done],
        "earlier_not_counted": [_milestone_payload(item) for item in theme.earlier_not_counted],
        "key_result_ids": list(theme.key_result_ids),
    }


def build_payload(review: MonthlyReviewInput) -> dict[str, object]:
    """Build a plain JSON-compatible schema-version-one monthly review payload."""
    start, end = month_bounds(review.month)
    categories = review.categories
    theme_ids = {theme.project_id for theme in review.themes}
    changes = [
        {
            "kind": item.kind.value,
            "on": item.changed_on.isoformat(),
            "out_project_id": item.out_project_id,
            "out_name": item.out_name,
            "in_project_id": item.in_project_id,
            "in_name": item.in_name,
            "target_before": item.target_before,
            "target_after": item.target_after,
            "undone": item.undone,
        }
        for item in review.changes
    ]
    outside = [
        {
            **_milestone_payload(item.milestone),
            "theme_project_id": item.milestone.theme_project_id,
            "theme_name": item.theme_name,
        }
        for item in review.outside_focus
    ]
    key_results = [
        {
            "key_result_id": item.key_result_id,
            "goal_id": item.goal_id,
            "goal_title": item.goal_title,
            "metric": item.metric,
            "update_source": item.update_source,
            "start_value": item.start_value,
            "base_value": item.base_value,
            "latest_value": item.latest_value,
            "latest_at": _iso_datetime(item.latest_at),
            "change": key_result_change(item.latest_value, item.base_value),
            "status": item.status.value,
            "entered_in_review": item.entered_in_review,
            "after_month_end": item.after_month_end,
            "target": item.target,
            "deadline": item.deadline.isoformat(),
            "past_deadline": item.past_deadline,
            "retired": item.retired,
            "theme_ids": list(item.theme_ids),
            "shared": item.shared or len(theme_ids.intersection(item.theme_ids)) > 1,
            "flags": list(item.flags),
        }
        for item in review.key_results
    ]
    decisions = [
        {
            "project_id": item.project_id,
            "name": item.name,
            "decision": item.decision.value,
            "replacement_project_id": item.replacement_project_id,
            "replacement_name": item.replacement_name,
        }
        for item in review.decisions
        if item.project_id in theme_ids
    ]
    decided_themes = {item["project_id"] for item in decisions}
    for theme in review.themes:
        if theme.project_id not in decided_themes:
            decisions.append(
                {
                    "project_id": theme.project_id,
                    "name": theme.name,
                    "decision": ThemeDecision.LATER.value,
                    "replacement_project_id": None,
                    "replacement_name": None,
                }
            )
    return {
        "schema_version": 1,
        "month": start.isoformat(),
        "month_end": end.isoformat(),
        "taken_at": _iso_datetime(review.taken_at),
        "themes": [_theme_payload(theme) for theme in review.themes],
        "changes": changes,
        "outside_focus": outside,
        "categories": {
            "goal_aligned": categories.goal_aligned,
            "maintenance": categories.maintenance,
            "off_plan": categories.off_plan,
            "hidden": categories.hidden,
        },
        "key_results": key_results,
        "decisions": decisions,
    }
