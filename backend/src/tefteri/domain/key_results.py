"""The pure rules of key results (spec 006). No database and no adapter import.

A key result is a number with a start value, a target and a deadline. Its values form a dated
series; the current value and the progress are derived (R-02), never stored. The three flags
(``no_key_result``, ``no_usable_theme``, ``overdue``) are computed on read (R-12) and never
raise: a warning must never break the screen.
"""

import math
from collections.abc import Iterable, Mapping
from dataclasses import dataclass
from datetime import date, datetime, timezone
from zoneinfo import ZoneInfo

from tefteri.domain.classification import ProjectNode, _ancestors, is_eligible, label_of
from tefteri.domain.enums import ProjectLabel


class ValidationError(ValueError):
    """A key result field breaks a rule (FR-005). The message names the field."""

    def __init__(self, field: str, message: str) -> None:
        """Store the field that was refused and the message for the user."""
        super().__init__(message)
        self.field = field


@dataclass(frozen=True)
class ValueEntry:
    """One stored value of the series, in the order the rules see it."""

    value: float
    on_date: date
    seq: int


@dataclass(frozen=True)
class LinkView:
    """One stored link of a key result as the flag rules see it.

    ``key`` is the tree key of the project (the ``project_labels.id``), or ``None`` when the
    project is unknown. ``active`` is ``ended_at is None``.
    """

    name: str
    key: str | None
    active: bool


@dataclass(frozen=True)
class FlagReason:
    """Why the ``no_usable_theme`` flag shows, for one project."""

    project_id: str | None
    name: str | None
    state: str  # 'no_links' | 'orphaned' | 'ignored' | 'relabelled' | 'unclassified'
    label: ProjectLabel | None = None
    """The new label when the project was relabelled, else ``None``."""


@dataclass(frozen=True)
class Flag:
    """A warning. Flags never change the status code of a route (FR-014)."""

    code: str  # 'no_key_result' | 'no_usable_theme' | 'overdue'
    reasons: tuple[FlagReason, ...] = ()
    actions: tuple[str, ...] = ()


# -- progress, met and overdue (FR-008, R-11) --------------------------------------------------


def progress(start_value: float, target: float, current: float) -> float:
    """Return ``(current - start) / (target - start)``.

    Not capped. Negative when the value moves away from the target.
    """
    return (current - start_value) / (target - start_value)


def is_met(start_value: float, target: float, current: float) -> bool:
    """Return whether the current value reached the target in the direction of the plan."""
    if target > start_value:
        return current >= target
    return current <= target


def is_overdue(deadline: date | None, today: date, *, met: bool, active: bool) -> bool:
    """Return whether an active key result passed its deadline without being met (R-11)."""
    if not active or deadline is None or met:
        return False
    return deadline < today


# -- the series (FR-007, FR-034, R-02) --------------------------------------------------------


def current_value(start_value: float, entries: Iterable[ValueEntry]) -> float:
    """Return the value of the latest entry, or the start value when the series is empty.

    On equal dates the higher ``seq`` wins (the value entered later).
    """
    best: ValueEntry | None = None
    for entry in entries:
        if best is None or (entry.on_date, entry.seq) > (best.on_date, best.seq):
            best = entry
    return start_value if best is None else best.value


def value_on_or_before(
    start_value: float, entries: Iterable[ValueEntry], day: date
) -> ValueEntry | None:
    """Return the last entry with ``on_date`` on or before ``day``, or ``None``.

    The start value is never assumed: before the first value there is no answer (FR-034).
    """
    best: ValueEntry | None = None
    for entry in entries:
        if entry.on_date > day:
            continue
        if best is None or (entry.on_date, entry.seq) > (best.on_date, best.seq):
            best = entry
    return best


def _as_number(field: str, raw: object) -> float:
    """Coerce ``raw`` to a finite float or raise a ``ValidationError`` naming the field."""
    if isinstance(raw, bool) or not isinstance(raw, (int, float)):
        raise ValidationError(field, f"{field} must be a number.")
    value = float(raw)
    if not math.isfinite(value):
        raise ValidationError(field, f"{field} must be a finite number.")
    return value


def validate(
    *,
    metric: str,
    start_value: object,
    target: object,
    deadline: date | None,
    year: int,
) -> None:
    """Check the rules of a key result (FR-005) and raise ``ValidationError`` on the first hit."""
    if not metric.strip() or len(metric) > 500:
        raise ValidationError("metric", "The metric text must be 1 to 500 characters.")
    start = _as_number("start_value", start_value)
    target_value = _as_number("target", target)
    if target_value == start:
        raise ValidationError("target", "The target must not equal the start value.")
    if deadline is None:
        raise ValidationError("deadline", "A key result needs a deadline.")
    if deadline.year != year:
        raise ValidationError("deadline", f"The deadline must fall inside the year {year}.")


def stamp_manual_value(
    value_date: date,
    today: date,
    tz: ZoneInfo | timezone,  # noqa: A002
) -> datetime:
    """Return the time stamp of a manually entered value (R-08).

    The date is entered without a time: today takes the current time in the user zone, a past
    day takes noon of that day in the user zone. A future date is refused before this runs.
    """
    if value_date >= today:
        return datetime.now(tz)
    return datetime(value_date.year, value_date.month, value_date.day, 12, tzinfo=tz)


# -- links and flags (FR-012, FR-014, R-12) ---------------------------------------------------


def is_usable_link(nodes: Mapping[str, ProjectNode], key: str) -> bool:
    """Return whether a link to the project is usable now (R-12).

    The project has the *stored* label ``theme`` (an unclassified proposal is not enough), it is
    not orphaned and no ancestor is ignored (feature 003 ``is_eligible``).
    """
    node = nodes.get(key)
    if node is None:
        return False
    return node.label is ProjectLabel.THEME and is_eligible(nodes, key)


def link_state(
    nodes: Mapping[str, ProjectNode], key: str | None
) -> tuple[str, ProjectLabel | None]:
    """Return the state of a linked project and, when relabelled, its new label.

    States: ``ok`` (a usable theme), ``orphaned`` (no longer in the task app), ``ignored``
    (ignored itself or through an ancestor), ``relabelled`` (the user chose another label) and
    ``unclassified`` (no stored label any more). A project that is not in the tree is orphaned.
    """
    node = nodes.get(key) if key is not None else None
    if node is None:
        return "orphaned", None
    if node.orphaned:
        return "orphaned", None
    if node.label is ProjectLabel.IGNORED or any(
        label_of(nodes, a.key) is ProjectLabel.IGNORED for a in _ancestors(nodes, node.key)
    ):
        return "ignored", None
    if node.label is ProjectLabel.THEME:
        return "ok", None
    if node.label is None:
        return "unclassified", None
    return "relabelled", node.label


def key_result_flags(
    *,
    status: str,
    deadline: date | None,
    met: bool,
    today: date,
    nodes: Mapping[str, ProjectNode],
    links: Iterable[LinkView],
) -> tuple[Flag, ...]:
    """Return the flags of one key result (R-12). A retired key result has no flags."""
    if status != "active":
        return ()
    flags: list[Flag] = []

    reasons: list[FlagReason] = []
    active_links = [link for link in links if link.active]
    if not active_links:
        reasons.append(FlagReason(None, None, "no_links"))
    else:
        for link in active_links:
            state, new_label = link_state(nodes, link.key)
            if state == "ok" and link.key is not None and is_usable_link(nodes, link.key):
                continue
            reasons.append(FlagReason(link.key, link.name, state, new_label))
    if reasons:
        flags.append(
            Flag(
                "no_usable_theme",
                tuple(reasons),
                ("link_theme", "create_theme"),
            )
        )

    if is_overdue(deadline, today, met=met, active=True):
        flags.append(Flag("overdue", (), ("update_value",)))
    return tuple(flags)


def goal_flags(*, active_key_results: int) -> tuple[Flag, ...]:
    """Return the flags of one goal: ``no_key_result`` while no active key result exists."""
    if active_key_results > 0:
        return ()
    return (Flag("no_key_result", (), ("add_key_result",)),)


def goal_progress(values: Iterable[float]) -> float | None:
    """Return the mean of the key result progresses for display, each limited to 0 to 1.

    ``None`` when the goal has no key results.
    """
    capped = [min(max(v, 0.0), 1.0) for v in values]
    if not capped:
        return None
    return sum(capped) / len(capped)
