"""Response models for cached items."""

import uuid
from datetime import UTC, datetime
from typing import Annotated, Any, Literal
from zoneinfo import ZoneInfo

from pydantic import AfterValidator, BaseModel

from tefteri.db.models.calendar_entry import CalendarEntry
from tefteri.db.models.note import Note
from tefteri.db.models.task import Task
from tefteri.domain.planning_time import block_for
from tefteri.domain.timeutil import day_bounds


def _as_utc(value: datetime) -> datetime:
    """Mark a time without a zone as UTC. The cache keeps UTC but SQLite drops the zone."""
    return value if value.tzinfo else value.replace(tzinfo=UTC)


UtcDatetime = Annotated[datetime, AfterValidator(_as_utc)]
"""A time that the API sends with its zone (``...Z``).

Without the zone a client reads the time as its own local time, and shows every cached time
shifted by its offset from UTC (two hours early in Athens, for example). Use this type for every
time in a response that comes from the cache.
"""


class TaskOut(BaseModel):
    """A cached task."""

    id: uuid.UUID
    connection_id: uuid.UUID
    title: str
    description: str
    status: str
    due_at: UtcDatetime | None
    scheduled_start: UtcDatetime | None
    scheduled_end: UtcDatetime | None
    sync_state: str
    goal_id: uuid.UUID | None = None
    project: str | None = None
    project_color: str | None = None
    """The color of its project in the task app, as ``#rrggbb``."""
    labels: list[str] = []
    url: str | None = None

    @classmethod
    def of(
        cls,
        t: Task,
        project: str | None = None,
        url: str | None = None,
        project_color: str | None = None,
    ) -> "TaskOut":
        """Build from the ORM row.

        ``project``, ``project_color`` and ``url`` come from the task's container and
        connection; the endpoints fill them.
        """
        return cls(
            id=t.id,
            connection_id=t.connection_id,
            title=t.title,
            description=t.description,
            status=t.status,
            due_at=t.due_at,
            scheduled_start=t.scheduled_start,
            scheduled_end=t.scheduled_end,
            sync_state=t.sync_state,
            goal_id=t.goal_id,
            project=project,
            project_color=project_color,
            labels=list(t.labels or []),
            url=url,
        )


class EntryOut(BaseModel):
    """A cached calendar entry."""

    id: uuid.UUID
    connection_id: uuid.UUID
    title: str
    start: UtcDatetime
    end: UtcDatetime
    all_day: bool
    color: str | None = None
    """The color of its calendar in the calendar app, as ``#rrggbb``."""
    read_only: bool = False
    """Its calendar is read-only: the user cannot move or change it."""
    location: str
    sync_state: str

    @classmethod
    def of(
        cls,
        e: CalendarEntry,
        colors: dict[uuid.UUID, str] | None = None,
        read_only: set[uuid.UUID] | None = None,
    ) -> "EntryOut":
        """Build from the ORM row. ``colors`` maps container ids to calendar colors."""
        return cls(
            id=e.id,
            connection_id=e.connection_id,
            title=e.title,
            start=e.start,
            end=e.end,
            all_day=e.all_day,
            color=(colors or {}).get(e.container_id) if e.container_id else None,
            read_only=bool(read_only and e.container_id in read_only),
            location=e.location,
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
    sync_state: str

    @classmethod
    def of(cls, n: Note) -> "NoteOut":
        """Build from the ORM row."""
        return cls(
            id=n.id,
            connection_id=n.connection_id,
            kind=n.kind,
            title=n.title,
            body=n.body,
            note_date=n.note_date.isoformat() if n.note_date else None,
            sync_state=n.sync_state,
        )


class CalendarItemOut(BaseModel):
    """A calendar view item: an entry, or a scheduled task shown next to entries."""

    type: Literal["entry", "task"]
    id: uuid.UUID
    connection_id: uuid.UUID
    container_id: uuid.UUID | None = None
    """The calendar of an entry, or the project of a task, when known."""
    title: str
    start: UtcDatetime
    end: UtcDatetime
    all_day: bool
    status: str | None = None
    clipped_start: bool = False
    project: str | None = None
    """For a task: the name of its project in the task app."""
    color: str | None = None
    """The color of its calendar (an entry) or of its project (a task), as ``#rrggbb``."""
    read_only: bool = False
    """For an entry: its calendar is read-only, so the user cannot move or change it."""

    @classmethod
    def of_entry(
        cls,
        e: CalendarEntry,
        colors: dict[uuid.UUID, str] | None = None,
        read_only: set[uuid.UUID] | None = None,
    ) -> "CalendarItemOut":
        """Build from an entry. ``colors`` maps container ids to calendar colors."""
        return cls(
            color=(colors or {}).get(e.container_id) if e.container_id else None,
            read_only=bool(read_only and e.container_id in read_only),
            type="entry",
            id=e.id,
            connection_id=e.connection_id,
            container_id=e.container_id,
            title=e.title,
            start=e.start,
            end=e.end,
            all_day=e.all_day,
        )

    @classmethod
    def of_task(
        cls, t: Task, tz_name: str, project: str | None = None, color: str | None = None
    ) -> "CalendarItemOut":
        """Build from a task with a due date (``due_at`` must be set).

        A timed task becomes the block that ends at its due time. An all-day task covers its
        local day and has ``all_day`` set.
        """
        assert t.due_at is not None  # noqa: S101
        due = aware(t.due_at)
        if t.all_day:
            start, end = day_bounds(due.astimezone(ZoneInfo(tz_name)).date(), tz_name)
            clipped = False
        else:
            block = block_for(due, tz_name)
            start, end, clipped = block.start, block.end, block.clipped_start
        return cls(
            type="task",
            id=t.id,
            connection_id=t.connection_id,
            container_id=t.container_id,
            title=t.title,
            start=start,
            end=end,
            all_day=t.all_day,
            status=t.status,
            clipped_start=clipped,
            project=project,
            color=color,
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
