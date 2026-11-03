"""Ports (adapter interfaces) that core code depends on, per contracts/backend-ports.md."""

from datetime import date, datetime
from typing import Protocol

from tefteri.domain.entities import (
    ConnectionHealth,
    Container,
    EntryDraft,
    EntryPage,
    EntryPatch,
    NoteDraft,
    NotePatch,
    RemoteEntry,
    RemoteNote,
    RemoteTask,
    TaskDraft,
    TaskPage,
    TaskPatch,
)
from tefteri.domain.enums import Capability


class Backend(Protocol):
    """Operations common to every backend."""

    def capabilities(self) -> set[Capability]:
        """Return the optional features this backend supports."""
        ...

    async def list_containers(self) -> list[Container]:
        """List projects, calendars or note subtrees."""
        ...

    async def check_connection(self) -> ConnectionHealth:
        """Check reachability and credentials."""
        ...


class TaskBackend(Backend, Protocol):
    """Task management application."""

    async def list_tasks(self, container: Container, since: str | None) -> TaskPage:
        """List tasks of a container, optionally only changes since a version."""
        ...

    async def get_task(self, remote_id: str) -> RemoteTask:
        """Fetch one task."""
        ...

    async def create_task(self, draft: TaskDraft) -> RemoteTask:
        """Create a task."""
        ...

    async def update_task(
        self, remote_id: str, patch: TaskPatch, expected_version: str
    ) -> RemoteTask:
        """Update a task; raise ``RemoteConflict`` if the version changed."""
        ...

    async def delete_task(self, remote_id: str) -> None:
        """Delete a task."""
        ...

    async def complete_task(self, remote_id: str) -> RemoteTask:
        """Mark a task done."""
        ...

    async def set_planned_time(
        self,
        remote_id: str,
        due_at: datetime | None,
        all_day: bool,
        expected_version: str,
    ) -> RemoteTask:
        """Write (or clear, with ``due_at=None``) the task's planned time.

        The due date is the only planning date of a task. With ``all_day`` the task is planned
        for a date only: ``due_at`` is then 00:00 local time on that date, and the adapter maps
        it to whatever its application uses for a date-only due date.
        """
        ...


class CalendarBackend(Backend, Protocol):
    """Calendar application (one instance per account)."""

    async def list_entries(
        self,
        container: Container,
        start: datetime,
        end: datetime,
        sync_token: str | None,
    ) -> EntryPage:
        """List events in a window."""
        ...

    async def get_entry(self, remote_id: str) -> RemoteEntry:
        """Fetch one event."""
        ...

    async def create_entry(self, draft: EntryDraft) -> RemoteEntry:
        """Create an event."""
        ...

    async def update_entry(
        self, remote_id: str, patch: EntryPatch, expected_version: str
    ) -> RemoteEntry:
        """Update an event; raise ``RemoteConflict`` if the version changed."""
        ...

    async def delete_entry(self, remote_id: str) -> None:
        """Delete an event."""
        ...


class NoteBackend(Backend, Protocol):
    """Note taking application."""

    async def list_notes(self, container: Container, since: str | None) -> list[RemoteNote]:
        """List notes of a container."""
        ...

    async def get_note(self, remote_id: str) -> RemoteNote:
        """Fetch one note."""
        ...

    async def create_note(self, draft: NoteDraft) -> RemoteNote:
        """Create a note."""
        ...

    async def update_note(
        self, remote_id: str, patch: NotePatch, expected_version: str
    ) -> RemoteNote:
        """Update a note; raise ``RemoteConflict`` if the version changed."""
        ...

    async def delete_note(self, remote_id: str) -> None:
        """Delete a note."""
        ...

    async def get_or_create_daily(self, day: date) -> RemoteNote:
        """Return the daily note for a date, creating it when missing."""
        ...

    async def append(self, remote_id: str, text: str) -> RemoteNote:
        """Append text to a note."""
        ...
