"""Conversion of remote items to the column values of their cached (mirror) rows."""

import uuid
from typing import Any

from tefteri.domain.entities import RemoteEntry, RemoteNote, RemoteTask
from tefteri.domain.planning_time import BLOCK_LENGTH


def task_values(item: RemoteTask, container_row_id: uuid.UUID | None) -> dict[str, Any]:
    """Return the mirror-row values for a remote task.

    ``scheduled_start`` and ``scheduled_end`` are derived from the due date and are never sent
    to a task application: a timed task is planned from one hour before its due time.
    """
    timed = item.due_at is not None and not item.all_day
    return {
        "container_id": container_row_id,
        "title": item.title,
        "description": item.description,
        "status": "done" if item.done else "open",
        "due_at": item.due_at,
        "scheduled_start": item.due_at - BLOCK_LENGTH if timed and item.due_at else None,
        "scheduled_end": item.due_at if timed else None,
        "all_day": item.all_day,
    }


def entry_values(item: RemoteEntry, container_row_id: uuid.UUID | None) -> dict[str, Any]:
    """Return the mirror-row values for a remote calendar entry."""
    return {
        "container_id": container_row_id,
        "title": item.title,
        "start": item.start,
        "end": item.end,
        "all_day": item.all_day,
        "recurrence": item.recurrence,
        "location": item.location,
    }


def note_values(item: RemoteNote) -> dict[str, Any]:
    """Return the mirror-row values for a remote note."""
    return {"title": item.title, "body": item.body, "note_date": item.note_date}
