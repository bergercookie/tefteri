"""Note use cases: the daily note and links between notes and tasks."""

import uuid
from datetime import date
from typing import cast

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from tefteri.db.models.connection import Connection
from tefteri.db.models.links import TaskNoteLink
from tefteri.db.models.note import Note
from tefteri.db.models.task import Task
from tefteri.db.repositories.items import NoteRepository, TaskNoteLinkRepository
from tefteri.domain.entities import NoteDraft, NotePatch, RemoteNote
from tefteri.domain.enums import ConnectionKind, SyncState
from tefteri.domain.ports import NoteBackend
from tefteri.services.connections import ConnectionService
from tefteri.services.errors import Invalid, NotFound, guard
from tefteri.services.mirror import note_values


class NoteService:
    """Read and write notes through the connected note app.

    The note app is not copied. Tefteri keeps a row only for a note that it created or opened
    (the daily note), so that a task can point at it.
    """

    def __init__(self, connections: ConnectionService) -> None:
        """Use ``connections`` to reach the note app."""
        self._connections = connections

    def _backend(self, connection: Connection) -> NoteBackend:
        return cast(NoteBackend, self._connections.backend_for(connection))

    async def notes_connection(
        self, db: AsyncSession, user_id: uuid.UUID, connection_id: uuid.UUID | None = None
    ) -> Connection:
        """Return the given notes connection, or the user's first one."""
        for connection in await self._connections.list(db, user_id):
            if connection.kind == ConnectionKind.NOTES.value and connection_id in (
                None,
                connection.id,
            ):
                return connection
        raise Invalid("connect a note app first")

    def _apply(self, note: Note, remote: RemoteNote) -> None:
        for key, value in note_values(remote).items():
            setattr(note, key, value)
        note.remote_version = remote.version
        note.sync_state = SyncState.SYNCED.value

    async def _mirror(
        self,
        db: AsyncSession,
        user_id: uuid.UUID,
        connection: Connection,
        remote: RemoteNote,
        kind: str,
    ) -> Note:
        note = (
            await db.execute(
                select(Note).where(
                    Note.connection_id == connection.id, Note.remote_id == remote.remote_id
                )
            )
        ).scalar_one_or_none()
        if note is None:
            note = Note(
                connection_id=connection.id,
                remote_id=remote.remote_id,
                title=remote.title,
                kind=kind,
            )
            self._apply(note, remote)
            return await NoteRepository(db, user_id).add(note)
        self._apply(note, remote)
        await db.flush()
        return note

    async def get(self, db: AsyncSession, user_id: uuid.UUID, note_id: uuid.UUID) -> Note:
        """Return one of the user's notes or raise ``NotFound``."""
        note = await NoteRepository(db, user_id).get(note_id)
        if note is None:
            raise NotFound
        return note

    async def daily(self, db: AsyncSession, user_id: uuid.UUID, day: date) -> Note:
        """Return the daily note for ``day``; the note app creates it when missing."""
        connection = await self.notes_connection(db, user_id)
        remote = await guard(connection, self._backend(connection).get_or_create_daily(day))
        return await self._mirror(db, user_id, connection, remote, "daily")

    async def append_daily(
        self, db: AsyncSession, user_id: uuid.UUID, day: date, text: str, task_id: uuid.UUID | None
    ) -> Note:
        """Append ``text`` to the daily note and optionally link the note to a task."""
        note = await self.daily(db, user_id, day)
        connection = await self.notes_connection(db, user_id, note.connection_id)
        remote = await guard(connection, self._backend(connection).append(note.remote_id, text))
        self._apply(note, remote)
        if task_id is not None:
            task = (
                await db.execute(select(Task).where(Task.id == task_id, Task.user_id == user_id))
            ).scalar_one_or_none()
            if task is None:
                raise NotFound
            await self.link(db, user_id, task, note)
        await db.flush()
        return note

    async def link(
        self, db: AsyncSession, user_id: uuid.UUID, task: Task, note: Note
    ) -> TaskNoteLink:
        """Link a note to a task (idempotent)."""
        existing = (
            await db.execute(
                select(TaskNoteLink).where(
                    TaskNoteLink.task_id == task.id, TaskNoteLink.note_id == note.id
                )
            )
        ).scalar_one_or_none()
        if existing is not None:
            return existing
        return await TaskNoteLinkRepository(db, user_id).add(
            TaskNoteLink(task_id=task.id, note_id=note.id)
        )

    async def create(
        self,
        db: AsyncSession,
        user_id: uuid.UUID,
        *,
        title: str,
        body: str = "",
        kind: str,
    ) -> Note:
        """Create a note of ``kind`` in the note app and cache it."""
        connection = await self.notes_connection(db, user_id)
        remote = await guard(
            connection, self._backend(connection).create_note(NoteDraft(title, body))
        )
        note = await self._mirror(db, user_id, connection, remote, kind)
        await db.flush()
        return note

    async def update(
        self,
        db: AsyncSession,
        user_id: uuid.UUID,
        note: Note,
        *,
        title: str | None = None,
        body: str | None = None,
    ) -> Note:
        """Change a note. Title and body go to the note app first."""
        if title is not None or body is not None:
            connection = await self.notes_connection(db, user_id, note.connection_id)
            remote = await guard(
                connection,
                self._backend(connection).update_note(
                    note.remote_id, NotePatch(title=title, body=body), note.remote_version
                ),
            )
            self._apply(note, remote)
        await db.flush()
        return note
