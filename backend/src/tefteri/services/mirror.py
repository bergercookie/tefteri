"""Conversion of remote items to the column values of their cached (mirror) rows."""

import uuid
from dataclasses import replace
from datetime import UTC, datetime, time
from typing import Any
from zoneinfo import ZoneInfo

from tefteri.domain.entities import RemoteEntry, RemoteNote, RemoteTask
from tefteri.domain.planning_time import BLOCK_LENGTH


def to_utc(value: datetime) -> datetime:
    """Return ``value`` as an aware UTC time. A time without an offset is taken as UTC."""
    return value.replace(tzinfo=UTC) if value.tzinfo is None else value.astimezone(UTC)


def utc(value: datetime | None) -> datetime | None:
    """Return ``value`` as UTC, for storing in the cache.

    The cache drops the offset of a time and keeps the wall-clock part: SQLite has no time zone.
    A time such as ``11:00+02:00`` would be stored as 11:00 and read back as 11:00 UTC, two hours
    late. Apps send such offsets when their server runs in another time zone than UTC. A time
    without an offset is taken as UTC.
    """
    return None if value is None else to_utc(value)


def task_values(item: RemoteTask, container_row_id: uuid.UUID | None) -> dict[str, Any]:
    """Return the mirror-row values for a remote task.

    ``scheduled_start`` and ``scheduled_end`` are derived from the due date and are never sent
    to a task application: a timed task is planned from one hour before its due time.
    """
    due = utc(item.due_at)
    timed = due is not None and not item.all_day
    return {
        "container_id": container_row_id,
        "title": item.title,
        "description": item.description,
        "status": "done" if item.done else "open",
        "due_at": due,
        "scheduled_start": due - BLOCK_LENGTH if timed and due else None,
        "scheduled_end": due if timed else None,
        "all_day": item.all_day,
        "labels": list(item.labels),
    }


def entry_values(item: RemoteEntry, container_row_id: uuid.UUID | None) -> dict[str, Any]:
    """Return the mirror-row values for a remote calendar entry."""
    return {
        "container_id": container_row_id,
        "title": item.title,
        "start": utc(item.start),
        "end": utc(item.end),
        "all_day": item.all_day,
        "recurrence": item.recurrence,
        "location": item.location,
    }


def note_values(item: RemoteNote) -> dict[str, Any]:
    """Return the mirror-row values for a remote note."""
    return {"title": item.title, "body": item.body, "note_date": item.note_date}


def anchor_all_day(item: RemoteEntry, tz_name: str) -> RemoteEntry:
    """Put an all-day event on the user's local days.

    An app sends an all-day event as dates (``2026-11-05`` to ``2026-11-06``). The cache holds
    instants, so the dates become midnight in the user's time zone. Taken as UTC midnight, the
    event would start two hours late and end two hours into the next day in Athens.
    """
    if not item.all_day:
        return item
    zone = ZoneInfo(tz_name)

    def midnight(value: datetime) -> datetime:
        return datetime.combine(value.date(), time(0), tzinfo=zone)

    return replace(item, start=midnight(item.start), end=midnight(item.end))
