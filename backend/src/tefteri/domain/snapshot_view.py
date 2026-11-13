"""Tolerant reading of one stored monthly-review snapshot (spec 008, R-02).

The payload belongs to feature 007. This module depends on the standard library and the
work-category value object only. Every field is optional: an old snapshot loads as far as its
keys allow and a missing or malformed field becomes ``None``. It never raises.
"""

from dataclasses import dataclass, field
from datetime import date, datetime
from typing import Any

from tefteri.domain.work_categories import CategoryCounts


def _mapping(value: object) -> dict[str, Any]:
    return dict(value) if isinstance(value, dict) else {}


def _items(value: object) -> list[dict[str, Any]]:
    if not isinstance(value, list):
        return []
    return [dict(item) for item in value if isinstance(item, dict)]


def _text(value: object) -> str | None:
    return value if isinstance(value, str) and value else None


def _number(value: object) -> float | None:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        return None
    return float(value)


def _whole(value: object) -> int | None:
    if isinstance(value, bool) or not isinstance(value, int):
        return None
    return value


def _day(value: object) -> date | None:
    if not isinstance(value, str):
        return None
    try:
        return date.fromisoformat(value)
    except ValueError:
        return None


def _moment(value: object) -> datetime | None:
    if not isinstance(value, str):
        return None
    try:
        return datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        return None


def _flag(value: object) -> bool:
    return value is True


@dataclass(frozen=True)
class MilestoneRef:
    """One milestone as a snapshot lists it."""

    milestone_id: str | None
    name: str
    done_on: date | None


@dataclass(frozen=True)
class ThemeEntry:
    """One theme entry of a monthly snapshot."""

    project_id: str | None
    name: str
    target: int | None
    done: int | None
    status: str | None
    milestones: list[MilestoneRef] = field(default_factory=list)
    orphaned_reason: str | None = None
    label_changed: str | None = None
    key_result_ids: list[str] = field(default_factory=list)


@dataclass(frozen=True)
class OutsideEntry:
    """One done milestone outside the month's focus."""

    milestone_id: str | None
    name: str
    done_on: date | None
    theme_project_id: str | None
    theme_name: str | None


@dataclass(frozen=True)
class KeyResultEntry:
    """The snapshot copy of one key result in one month."""

    key_result_id: str
    start_value: float | None
    base_value: float | None
    latest_value: float | None
    latest_at: datetime | None
    target: float | None
    deadline: date | None
    retired: bool
    status: str | None
    update_source: str | None


@dataclass(frozen=True)
class SnapshotView:
    """One tolerant, typed monthly snapshot."""

    month: str | None
    version: int | None
    taken_at: datetime | None
    schema_version: int | None
    themes: list[ThemeEntry]
    outside_focus: list[OutsideEntry]
    categories: CategoryCounts | None
    key_results: dict[str, KeyResultEntry]


def _milestone(raw: dict[str, Any]) -> MilestoneRef:
    return MilestoneRef(
        milestone_id=_text(raw.get("milestone_id")),
        name=_text(raw.get("name")) or "",
        done_on=_day(raw.get("done_on")),
    )


def _theme(raw: dict[str, Any]) -> ThemeEntry:
    orphaned = _mapping(raw.get("orphaned"))
    return ThemeEntry(
        project_id=_text(raw.get("project_id")),
        name=_text(raw.get("name")) or "",
        target=_whole(raw.get("target")),
        done=_whole(raw.get("done")),
        status=_text(raw.get("status")),
        milestones=[_milestone(item) for item in _items(raw.get("milestones"))],
        orphaned_reason=_text(orphaned.get("reason")),
        label_changed=_text(raw.get("label_changed")),
        key_result_ids=[text for item in raw.get("key_result_ids") or [] if (text := _text(item))],
    )


def _outside(raw: dict[str, Any]) -> OutsideEntry:
    return OutsideEntry(
        milestone_id=_text(raw.get("milestone_id")),
        name=_text(raw.get("name")) or "",
        done_on=_day(raw.get("done_on")),
        theme_project_id=_text(raw.get("theme_project_id")),
        theme_name=_text(raw.get("theme_name")),
    )


def _key_result(raw: dict[str, Any]) -> KeyResultEntry | None:
    key_result_id = _text(raw.get("key_result_id"))
    if key_result_id is None:
        return None
    return KeyResultEntry(
        key_result_id=key_result_id,
        start_value=_number(raw.get("start_value")),
        base_value=_number(raw.get("base_value")),
        latest_value=_number(raw.get("latest_value")),
        latest_at=_moment(raw.get("latest_at")),
        target=_number(raw.get("target")),
        deadline=_day(raw.get("deadline")),
        retired=_flag(raw.get("retired")),
        status=_text(raw.get("status")),
        update_source=_text(raw.get("update_source")),
    )


def _categories(value: object) -> CategoryCounts | None:
    raw = _mapping(value)
    if not raw:
        return None
    numbers: list[int] = []
    for key in ("goal_aligned", "maintenance", "off_plan", "hidden"):
        number = _whole(raw.get(key))
        if number is None:
            return None
        numbers.append(number)
    return CategoryCounts(*numbers)


def read_snapshot(
    payload: object, *, version: int | None = None, taken_at: object = None
) -> SnapshotView:
    """Read one snapshot payload without failing on an old or malformed field."""
    raw = _mapping(payload)
    key_results: dict[str, KeyResultEntry] = {}
    for item in _items(raw.get("key_results")):
        entry = _key_result(item)
        if entry is not None:
            key_results[entry.key_result_id] = entry
    return SnapshotView(
        month=_text(raw.get("month")),
        version=version,
        taken_at=_moment(raw.get("taken_at")) or _moment(taken_at) or None,
        schema_version=_whole(raw.get("schema_version")),
        themes=[_theme(item) for item in _items(raw.get("themes"))],
        outside_focus=[_outside(item) for item in _items(raw.get("outside_focus"))],
        categories=_categories(raw.get("categories")),
        key_results=key_results,
    )
