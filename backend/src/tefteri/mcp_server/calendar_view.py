"""Pure helpers for the calendar tools: one event once, and the free time of a day."""

from collections.abc import Iterable, Mapping, Sequence
from datetime import datetime, timedelta
from typing import Any


def unique_events(items: Iterable[Mapping[str, Any]]) -> list[dict[str, Any]]:
    """Return each event once, with the calendars that hold it.

    An event that is in more than one calendar has the same ``uid`` in each, and the API
    returns a copy for each calendar. Without a ``uid``, the same title at the same time is
    one event. Only calendar entries count; tasks are left out.
    """
    found: dict[tuple[str, str], dict[str, Any]] = {}
    for item in items:
        if item.get("type") != "entry":
            continue
        identity = item.get("uid") or f"{str(item.get('title', '')).casefold()}|{item.get('end')}"
        key = (str(identity), str(item.get("start")))
        calendar = item.get("calendar")
        if key in found:
            names = found[key].setdefault("calendars", [])
            if calendar and calendar not in names:
                names.append(calendar)
            if found[key].get("read_only") and not item.get("read_only"):
                # The copy that the user can change is the one to change.
                found[key]["id"] = item.get("id")
                found[key]["read_only"] = False
            continue
        event = {k: v for k, v in item.items() if k not in ("type", "uid", "calendar")}
        event["calendars"] = [calendar] if calendar else []
        found[key] = event
    return sorted(found.values(), key=lambda e: (str(e.get("start")), str(e.get("title"))))


def _merge(spans: Sequence[tuple[datetime, datetime]]) -> list[tuple[datetime, datetime]]:
    merged: list[tuple[datetime, datetime]] = []
    for start, end in sorted(spans):
        if merged and start <= merged[-1][1]:
            merged[-1] = (merged[-1][0], max(merged[-1][1], end))
        else:
            merged.append((start, end))
    return merged


def free_slots(
    busy: Iterable[tuple[datetime, datetime]],
    window_start: datetime,
    window_end: datetime,
    minimum: timedelta,
) -> list[tuple[datetime, datetime]]:
    """Return the gaps of at least ``minimum`` between ``window_start`` and ``window_end``.

    ``busy`` holds the events and the planned tasks. They may overlap and may reach out of the
    window.
    """
    inside = [
        (max(s, window_start), min(e, window_end))
        for s, e in busy
        if e > window_start and s < window_end
    ]
    cursor = window_start
    gaps: list[tuple[datetime, datetime]] = []
    for start, end in _merge(inside):
        if start - cursor >= minimum:
            gaps.append((cursor, start))
        cursor = max(cursor, end)
    if window_end - cursor >= minimum:
        gaps.append((cursor, window_end))
    return gaps
