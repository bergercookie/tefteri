"""In-memory fake backends implementing the three ports, for service/integration/e2e tests."""

import itertools
from dataclasses import replace
from datetime import date, datetime

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
from tefteri.domain.enums import Capability, ConnectionStatus
from tefteri.domain.errors import AuthExpired, BackendUnavailable, NotSupported, RemoteConflict


class _FakeBase:
    """Shared failure switches and version counter."""

    def __init__(self, containers: list[Container] | None = None) -> None:
        self.containers = containers or [Container("c1", "Default")]
        self.unavailable = False
        self.auth_expired = False
        self.supported: set[Capability] = set(Capability)
        self._ids = itertools.count(1)
        self._versions = itertools.count(1)

    def _guard(self) -> None:
        if self.unavailable:
            raise BackendUnavailable("fake backend is down")
        if self.auth_expired:
            raise AuthExpired("fake credentials expired")

    def _require(self, capability: Capability) -> None:
        if capability not in self.supported:
            raise NotSupported(capability)

    def _new_id(self) -> str:
        return str(next(self._ids))

    def _new_version(self) -> str:
        return str(next(self._versions))

    def _check_version(self, current: str, expected: str) -> None:
        if current != expected:
            raise RemoteConflict(f"expected version {expected}, found {current}")

    def capabilities(self) -> set[Capability]:
        """Return the supported capabilities."""
        return set(self.supported)

    async def list_containers(self) -> list[Container]:
        """List containers."""
        self._guard()
        return list(self.containers)

    async def check_connection(self) -> ConnectionHealth:
        """Report health according to the failure switches."""
        if self.unavailable:
            return ConnectionHealth(ConnectionStatus.ERROR, "unreachable")
        if self.auth_expired:
            return ConnectionHealth(ConnectionStatus.NEEDS_ATTENTION, "auth_expired")
        return ConnectionHealth(ConnectionStatus.OK)


class FakeTaskBackend(_FakeBase):
    """In-memory ``TaskBackend``."""

    def __init__(self, containers: list[Container] | None = None) -> None:
        """Start empty."""
        super().__init__(containers)
        self.tasks: dict[str, RemoteTask] = {}

    async def list_tasks(self, container: Container, since: str | None) -> TaskPage:  # noqa: ARG002
        """List the tasks of a container."""
        self._guard()
        items = [t for t in self.tasks.values() if t.container_id == container.remote_id]
        return TaskPage(items=items, next_version=self._new_version())

    async def get_task(self, remote_id: str) -> RemoteTask:
        """Fetch a task."""
        self._guard()
        return self.tasks[remote_id]

    async def create_task(self, draft: TaskDraft) -> RemoteTask:
        """Create a task."""
        self._guard()
        task = RemoteTask(
            remote_id=self._new_id(),
            container_id=draft.container_id,
            title=draft.title,
            description=draft.description,
            due_at=draft.due_at,
            version=self._new_version(),
        )
        self.tasks[task.remote_id] = task
        return task

    async def update_task(
        self, remote_id: str, patch: TaskPatch, expected_version: str
    ) -> RemoteTask:
        """Update a task, checking the version."""
        self._guard()
        current = self.tasks[remote_id]
        self._check_version(current.version, expected_version)
        updated = replace(
            current,
            title=patch.title if patch.title is not None else current.title,
            description=patch.description if patch.description is not None else current.description,
            due_at=patch.due_at if patch.due_at is not None else current.due_at,
            version=self._new_version(),
        )
        self.tasks[remote_id] = updated
        return updated

    async def delete_task(self, remote_id: str) -> None:
        """Delete a task."""
        self._guard()
        del self.tasks[remote_id]

    async def complete_task(self, remote_id: str) -> RemoteTask:
        """Mark a task done."""
        self._guard()
        updated = replace(self.tasks[remote_id], done=True, version=self._new_version())
        self.tasks[remote_id] = updated
        return updated

    async def set_planned_time(
        self, remote_id: str, due_at: datetime | None, all_day: bool, expected_version: str
    ) -> RemoteTask:
        """Write the planned time (the due date) to the task."""
        self._guard()
        self._require(Capability.TASK_TIME)
        current = self.tasks[remote_id]
        self._check_version(current.version, expected_version)
        updated = replace(
            current,
            due_at=due_at,
            all_day=all_day and due_at is not None,
            version=self._new_version(),
        )
        self.tasks[remote_id] = updated
        return updated

    def edit_remotely(self, remote_id: str, title: str) -> None:
        """Simulate a change made directly in the app."""
        self.tasks[remote_id] = replace(
            self.tasks[remote_id], title=title, version=self._new_version()
        )


class FakeCalendarBackend(_FakeBase):
    """In-memory ``CalendarBackend``."""

    def __init__(self, containers: list[Container] | None = None) -> None:
        """Start empty."""
        super().__init__(containers)
        self.entries: dict[str, RemoteEntry] = {}

    async def list_entries(
        self,
        container: Container,
        start: datetime,
        end: datetime,
        sync_token: str | None,  # noqa: ARG002
    ) -> EntryPage:
        """List events overlapping the window."""
        self._guard()
        items = [
            e
            for e in self.entries.values()
            if e.container_id == container.remote_id and e.start < end and e.end > start
        ]
        return EntryPage(items=items, sync_token=self._new_version())

    async def get_entry(self, remote_id: str) -> RemoteEntry:
        """Fetch an event."""
        self._guard()
        return self.entries[remote_id]

    def edit_remotely(self, remote_id: str, title: str) -> None:
        """Simulate a change made directly in the app."""
        self.entries[remote_id] = replace(
            self.entries[remote_id], title=title, version=self._new_version()
        )

    async def create_entry(self, draft: EntryDraft) -> RemoteEntry:
        """Create an event."""
        self._guard()
        entry = RemoteEntry(
            remote_id=self._new_id(),
            container_id=draft.container_id,
            title=draft.title,
            start=draft.start,
            end=draft.end,
            all_day=draft.all_day,
            location=draft.location,
            version=self._new_version(),
        )
        self.entries[entry.remote_id] = entry
        return entry

    async def update_entry(
        self, remote_id: str, patch: EntryPatch, expected_version: str
    ) -> RemoteEntry:
        """Update an event, checking the version."""
        self._guard()
        current = self.entries[remote_id]
        self._check_version(current.version, expected_version)
        updated = replace(
            current,
            title=patch.title if patch.title is not None else current.title,
            start=patch.start if patch.start is not None else current.start,
            end=patch.end if patch.end is not None else current.end,
            location=patch.location if patch.location is not None else current.location,
            version=self._new_version(),
        )
        self.entries[remote_id] = updated
        return updated

    async def delete_entry(self, remote_id: str) -> None:
        """Delete an event."""
        self._guard()
        del self.entries[remote_id]


class FakeNoteBackend(_FakeBase):
    """In-memory ``NoteBackend``."""

    def __init__(self, containers: list[Container] | None = None) -> None:
        """Start empty."""
        super().__init__(containers)
        self.notes: dict[str, RemoteNote] = {}

    async def list_notes(
        self,
        container: Container,  # noqa: ARG002
        since: str | None,  # noqa: ARG002
    ) -> list[RemoteNote]:
        """List all notes."""
        self._guard()
        return list(self.notes.values())

    async def get_note(self, remote_id: str) -> RemoteNote:
        """Fetch a note."""
        self._guard()
        return self.notes[remote_id]

    async def create_note(self, draft: NoteDraft) -> RemoteNote:
        """Create a note."""
        self._guard()
        note = RemoteNote(
            remote_id=self._new_id(),
            title=draft.title,
            body=draft.body,
            note_date=draft.note_date,
            version=self._new_version(),
        )
        self.notes[note.remote_id] = note
        return note

    async def update_note(
        self, remote_id: str, patch: NotePatch, expected_version: str
    ) -> RemoteNote:
        """Update a note, checking the version."""
        self._guard()
        current = self.notes[remote_id]
        self._check_version(current.version, expected_version)
        updated = replace(
            current,
            title=patch.title if patch.title is not None else current.title,
            body=patch.body if patch.body is not None else current.body,
            version=self._new_version(),
        )
        self.notes[remote_id] = updated
        return updated

    async def delete_note(self, remote_id: str) -> None:
        """Delete a note."""
        self._guard()
        del self.notes[remote_id]

    async def get_or_create_daily(self, day: date) -> RemoteNote:
        """Return the daily note for ``day``."""
        self._guard()
        for note in self.notes.values():
            if note.note_date == day:
                return note
        return await self.create_note(NoteDraft(title=day.isoformat(), note_date=day))

    async def append(self, remote_id: str, text: str) -> RemoteNote:
        """Append text to a note."""
        self._guard()
        self._require(Capability.NOTE_APPEND)
        current = self.notes[remote_id]
        updated = replace(
            current, body=f"{current.body}\n{text}".strip(), version=self._new_version()
        )
        self.notes[remote_id] = updated
        return updated
