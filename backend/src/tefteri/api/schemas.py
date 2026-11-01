"""Response models for cached items. ``effective_context`` is resolved per item."""

import uuid
from datetime import UTC, datetime, timedelta
from typing import Any, Literal

from pydantic import BaseModel

from tefteri.db.models.calendar_entry import CalendarEntry
from tefteri.db.models.note import Note
from tefteri.db.models.task import Task
from tefteri.services.context import ContextMaps


class TaskOut(BaseModel):
    """A cached task."""

    id: uuid.UUID
    connection_id: uuid.UUID
    title: str
    description: str
    status: str
    due_at: datetime | None
    scheduled_start: datetime | None
    scheduled_end: datetime | None
    context: str | None
    effective_context: str
    sync_state: str
    goal_id: uuid.UUID | None = None

    @classmethod
    def of(cls, t: Task, maps: ContextMaps) -> "TaskOut":
        """Build from the ORM row."""
        return cls(
            id=t.id,
            connection_id=t.connection_id,
            title=t.title,
            description=t.description,
            status=t.status,
            due_at=t.due_at,
            scheduled_start=t.scheduled_start,
            scheduled_end=t.scheduled_end,
            context=t.context,
            effective_context=maps.effective(t.context, t.container_id, t.connection_id)[0].value,
            sync_state=t.sync_state,
            goal_id=t.goal_id,
        )


class EntryOut(BaseModel):
    """A cached calendar entry."""

    id: uuid.UUID
    connection_id: uuid.UUID
    title: str
    start: datetime
    end: datetime
    all_day: bool
    location: str
    context: str | None
    effective_context: str
    sync_state: str

    @classmethod
    def of(cls, e: CalendarEntry, maps: ContextMaps) -> "EntryOut":
        """Build from the ORM row."""
        return cls(
            id=e.id,
            connection_id=e.connection_id,
            title=e.title,
            start=e.start,
            end=e.end,
            all_day=e.all_day,
            location=e.location,
            context=e.context,
            effective_context=maps.effective(e.context, e.container_id, e.connection_id)[0].value,
            sync_state=e.sync_state,
        )


class NoteOut(BaseModel):
    """A cached note."""

    id: uuid.UUID
    connection_id: uuid.UUID
    kind: str
    title: str
    body: str
    note_date: str | None
    context: str | None
    effective_context: str
    sync_state: str

    @classmethod
    def of(cls, n: Note, maps: ContextMaps) -> "NoteOut":
        """Build from the ORM row."""
        return cls(
            id=n.id,
            connection_id=n.connection_id,
            kind=n.kind,
            title=n.title,
            body=n.body,
            note_date=n.note_date.isoformat() if n.note_date else None,
            context=n.context,
            effective_context=maps.effective(n.context, None, n.connection_id)[0].value,
            sync_state=n.sync_state,
        )


class CalendarItemOut(BaseModel):
    """A calendar view item: an entry, or a scheduled task shown next to entries."""

    type: Literal["entry", "task"]
    id: uuid.UUID
    connection_id: uuid.UUID
    title: str
    start: datetime
    end: datetime
    all_day: bool
    context: str | None
    effective_context: str

    @classmethod
    def of_entry(cls, e: CalendarEntry, maps: ContextMaps) -> "CalendarItemOut":
        """Build from an entry."""
        return cls(
            type="entry",
            id=e.id,
            connection_id=e.connection_id,
            title=e.title,
            start=e.start,
            end=e.end,
            all_day=e.all_day,
            context=e.context,
            effective_context=maps.effective(e.context, e.container_id, e.connection_id)[0].value,
        )

    @classmethod
    def of_task(cls, t: Task, maps: ContextMaps) -> "CalendarItemOut":
        """Build from a scheduled task (``scheduled_start`` must be set)."""
        assert t.scheduled_start is not None  # noqa: S101
        start = t.scheduled_start
        end = t.scheduled_end or start + timedelta(hours=1)
        return cls(
            type="task",
            id=t.id,
            connection_id=t.connection_id,
            title=t.title,
            start=start,
            end=end,
            all_day=t.all_day,
            context=t.context,
            effective_context=maps.effective(t.context, t.container_id, t.connection_id)[0].value,
        )


def aware(value: datetime) -> datetime:
    """Return ``value`` as an aware UTC datetime (SQLite drops the zone)."""
    return value if value.tzinfo else value.replace(tzinfo=UTC)


class DayView(BaseModel):
    """Aggregated data for the daily view."""

    date: str
    entries: list[EntryOut]
    tasks: list[TaskOut]
    note: NoteOut | None


Json = dict[str, Any]
