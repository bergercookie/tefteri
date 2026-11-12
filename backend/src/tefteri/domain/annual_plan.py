"""The pure rules of the annual plan (spec 006). No database and no adapter import.

The year state drives the past-year rule (R-09), the slot numbers drive the limit of three
(R-03), and ``suggest`` works out what a new year can inherit from year N (R-10).
"""

from collections.abc import Iterable, Mapping, Sequence
from dataclasses import dataclass
from datetime import UTC, date, datetime
from zoneinfo import ZoneInfo

from tefteri.domain.classification import ProjectNode
from tefteri.domain.key_results import LinkView, ValidationError, ValueEntry, current_value, is_met

MAX_ACTIVE_KEY_RESULTS = 3
"""A goal has at most three active key results (FR-003)."""


def today_in(tz: str | ZoneInfo, now: datetime | None = None) -> date:
    """Return today's date in the user time zone."""
    zone = ZoneInfo(tz) if isinstance(tz, str) else tz
    return (now if now is not None else datetime.now(UTC)).astimezone(zone).date()


def year_state(year: int, today: date) -> str:
    """Return ``past``, ``current`` or ``future`` for the planning year (FR-033)."""
    if year < today.year:
        return "past"
    if year > today.year:
        return "future"
    return "current"


def next_free_slot(taken: Iterable[int]) -> int | None:
    """Return the lowest slot of 1 to 3 that no active key result uses, or ``None``.

    Only the slots of the *active* key results are passed in: a retired key result has no slot
    and frees its place (R-03).
    """
    used = set(taken)
    for slot in range(1, MAX_ACTIVE_KEY_RESULTS + 1):
        if slot not in used:
            return slot
    return None


def shift_deadline(deadline: date, year: int) -> date:
    """Move a deadline into ``year`` with the same month and day (R-10).

    29 February becomes 28 February when the new year is not a leap year.
    """
    if deadline.month == 2 and deadline.day == 29:
        try:
            return date(year, 2, 29)
        except ValueError:
            return date(year, 2, 28)
    return date(year, deadline.month, deadline.day)


@dataclass(frozen=True)
class PastKeyResult:
    """A key result of year N as the seeding rules see it."""

    id: str
    status: str  # 'active' | 'retired'
    metric: str
    start_value: float
    target: float
    deadline: date
    entries: tuple[ValueEntry, ...] = ()
    links: tuple[LinkView, ...] = ()
    """The active links of the key result."""


@dataclass(frozen=True)
class PastGoal:
    """A goal of year N as the seeding rules see it."""

    id: str
    status: str  # 'active' | 'retired'
    title: str = ""
    key_results: tuple[PastKeyResult, ...] = ()


@dataclass(frozen=True)
class KeyResultSuggestion:
    """What a new key result of ``year`` inherits from one of year N."""

    key_result_id: str
    metric: str
    start_value: float
    """The last value of year N, editable before the save."""
    target: float
    deadline: date
    """The deadline of year N moved into ``year``."""
    theme_keys: tuple[str, ...] = ()
    """The tree keys of the themes whose link is still usable now."""


@dataclass(frozen=True)
class GoalSuggestion:
    """What a new goal of ``year`` inherits from one of year N."""

    goal_id: str
    title: str
    key_results: tuple[KeyResultSuggestion, ...] = ()


def suggest(
    goals: Sequence[PastGoal],
    *,
    year: int,
    from_year: int,
    nodes: Mapping[str, ProjectNode],
) -> list[GoalSuggestion]:
    """Work out what year ``year`` can inherit from ``from_year`` (FR-016, FR-017, R-10).

    Reading suggestions writes nothing. A key result is offered when it is active and *unmet*
    (its last value did not reach the target; the start value counts when the series is empty).
    A met key result is not offered, but its goal is. Retired goals and key results are not
    offered, and a link to a theme that is not usable now is dropped. ``from_year`` must be
    earlier than ``year``.
    """
    if from_year >= year:
        raise ValidationError("from_year", "The source year must be earlier than the new year.")
    out: list[GoalSuggestion] = []
    for goal in goals:
        if goal.status != "active":
            continue
        offered: list[KeyResultSuggestion] = []
        for kr in goal.key_results:
            if kr.status != "active":
                continue
            last = current_value(kr.start_value, kr.entries)
            if is_met(kr.start_value, kr.target, last):
                continue
            themes = tuple(
                link.key
                for link in kr.links
                if link.active
                and link.key is not None
                and nodes.get(link.key) is not None
                and _usable(nodes, link.key)
            )
            offered.append(
                KeyResultSuggestion(
                    key_result_id=kr.id,
                    metric=kr.metric,
                    start_value=last,
                    target=kr.target,
                    deadline=shift_deadline(kr.deadline, year),
                    theme_keys=themes,
                )
            )
        out.append(GoalSuggestion(goal_id=goal.id, title=goal.title, key_results=tuple(offered)))
    return out


def _usable(nodes: Mapping[str, ProjectNode], key: str) -> bool:
    """Return whether the linked project is a stored theme that is eligible now."""
    from tefteri.domain.key_results import is_usable_link

    return is_usable_link(nodes, key)
