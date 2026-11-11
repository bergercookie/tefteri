"""In-memory fake backends implementing the three ports, for service/integration/e2e tests."""

import itertools
from dataclasses import replace
from datetime import UTC, date, datetime

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
from tefteri.domain.errors import (
    AuthExpired,
    BackendError,
    BackendUnavailable,
    NotSupported,
    RemoteConflict,
)


def _utc(value: datetime) -> datetime:
    """An all-day event is a plain date (no zone); compare it as UTC."""
    return value if value.tzinfo else value.replace(tzinfo=UTC)


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
        self.archived: list[Container] = []
        self.known_labels: set[str] = set()
        self.reminders: dict[str, int] = {}

    async def create_container(self, name: str, parent: Container | None) -> Container:
        """Create a project (a subproject of ``parent`` when given)."""
        self._guard()
        self._require(Capability.SUBPROJECTS)
        created = Container(self._new_id(), name, parent.remote_id if parent else None)
        self.containers.append(created)
        return created

    async def list_labels(self) -> list[str]:
        """List the labels that exist, also those only used on tasks."""
        self._guard()
        used = {name for t in self.tasks.values() for name in t.labels}
        return sorted(self.known_labels | used, key=str.casefold)

    async def archive_container(self, container: Container) -> None:
        """Archive a project: the app stops listing it (and its subprojects)."""
        self._guard()
        self._require(Capability.ARCHIVE_PROJECTS)
        gone = {container.remote_id}
        grew = True
        while grew:
            grew = False
            for c in self.containers:
                if c.parent_id in gone and c.remote_id not in gone:
                    gone.add(c.remote_id)
                    grew = True
        self.archived.extend(c for c in self.containers if c.remote_id in gone)
        self.containers = [c for c in self.containers if c.remote_id not in gone]

    async def rename_container(self, container: Container, name: str) -> Container:
        """Give a project a new title; its id and parent stay."""
        self._guard()
        self._require(Capability.RENAME_PROJECTS)
        for index, c in enumerate(self.containers):
            if c.remote_id == container.remote_id:
                self.containers[index] = replace(c, name=name)
                return self.containers[index]
        raise BackendError(f"no project {container.remote_id}")

    async def restore_container(self, container: Container) -> None:
        """Bring an archived project back into the list."""
        self._guard()
        self._require(Capability.RESTORE_PROJECTS)
        for c in self.archived:
            if c.remote_id == container.remote_id:
                self.archived.remove(c)
                self.containers.append(c)
                return
        raise BackendError(f"project {container.remote_id} is not archived")

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
            labels=draft.labels,
            version=self._new_version(),
        )
        self.known_labels.update(draft.labels)
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

    async def get_reminder(self, remote_id: str) -> int | None:
        """Return the minutes before the due time of the reminder."""
        self._guard()
        self._require(Capability.TASK_REMINDERS)
        return self.reminders.get(remote_id)

    async def set_reminder(self, remote_id: str, minutes_before: int | None) -> RemoteTask:
        """Set or remove the reminder."""
        self._guard()
        self._require(Capability.TASK_REMINDERS)
        if minutes_before is None:
            self.reminders.pop(remote_id, None)
        else:
            self.reminders[remote_id] = minutes_before
        updated = replace(self.tasks[remote_id], version=self._new_version())
        self.tasks[remote_id] = updated
        return updated

    async def delete_task(self, remote_id: str) -> None:
        """Delete a task."""
        self._guard()
        del self.tasks[remote_id]

    async def complete_task(self, remote_id: str) -> RemoteTask:
        """Mark a task done."""
        self._guard()
        updated = replace(
            self.tasks[remote_id],
            done=True,
            done_at=datetime(2030, 3, 6, 22, 30, tzinfo=UTC),
            version=self._new_version(),
        )
        self.tasks[remote_id] = updated
        return updated

    async def reopen_task(self, remote_id: str) -> RemoteTask:
        """Mark a task open again."""
        self._guard()
        updated = replace(
            self.tasks[remote_id], done=False, done_at=None, version=self._new_version()
        )
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
        self.refused: set[str] = set()
        """Remote ids of calendars that the app answers with an error (like a 404)."""

    async def list_entries(
        self,
        container: Container,
        start: datetime,
        end: datetime,
        sync_token: str | None,  # noqa: ARG002
    ) -> EntryPage:
        """List events overlapping the window."""
        self._guard()
        if container.remote_id in self.refused:
            raise BackendError(f"GET calendars/{container.remote_id}/events answered 404")
        items = [
            e
            for e in self.entries.values()
            if e.container_id == container.remote_id and _utc(e.start) < end and _utc(e.end) > start
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
