"""Plain domain value objects exchanged with adapters."""

from dataclasses import dataclass, field
from datetime import date, datetime

from tefteri.domain.enums import ConnectionStatus


@dataclass(frozen=True)
class Container:
    """A Vikunja project, a Google calendar or a Trilium subtree."""

    remote_id: str
    name: str


@dataclass(frozen=True)
class ConnectionHealth:
    """Result of checking a connection."""

    status: ConnectionStatus
    detail: str = ""


@dataclass(frozen=True)
class RemoteTask:
    """A task as stored in the task application."""

    remote_id: str
    container_id: str
    title: str
    version: str
    description: str = ""
    done: bool = False
    due_at: datetime | None = None
    all_day: bool = False


@dataclass(frozen=True)
class TaskDraft:
    """Data needed to create a task."""

    container_id: str
    title: str
    description: str = ""
    due_at: datetime | None = None


@dataclass(frozen=True)
class TaskPatch:
    """Partial task update; ``None`` means unchanged."""

    title: str | None = None
    description: str | None = None
    due_at: datetime | None = None


@dataclass(frozen=True)
class TaskPage:
    """Result of listing tasks, with the cursor for the next incremental sync."""

    items: list[RemoteTask] = field(default_factory=list)
    next_version: str | None = None


@dataclass(frozen=True)
class RemoteEntry:
    """A calendar event."""

    remote_id: str
    container_id: str
    title: str
    start: datetime
    end: datetime
    version: str
    all_day: bool = False
    recurrence: str | None = None
    location: str = ""


@dataclass(frozen=True)
class EntryDraft:
    """Data needed to create a calendar event."""

    container_id: str
    title: str
    start: datetime
    end: datetime
    all_day: bool = False
    location: str = ""


@dataclass(frozen=True)
class EntryPatch:
    """Partial calendar event update."""

    title: str | None = None
    start: datetime | None = None
    end: datetime | None = None
    location: str | None = None


@dataclass(frozen=True)
class EntryPage:
    """Result of listing events, with the sync token for the next call."""

    items: list[RemoteEntry] = field(default_factory=list)
    sync_token: str | None = None


@dataclass(frozen=True)
class RemoteNote:
    """A note as stored in the note application."""

    remote_id: str
    title: str
    body: str
    version: str
    note_date: date | None = None


@dataclass(frozen=True)
class NoteDraft:
    """Data needed to create a note."""

    title: str
    body: str = ""
    note_date: date | None = None


@dataclass(frozen=True)
class NotePatch:
    """Partial note update."""

    title: str | None = None
    body: str | None = None
