"""Task use cases: write through to the task app first, then update the cache."""

import uuid
from datetime import UTC, datetime, timedelta
from typing import cast

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from tefteri.db.models.calendar_entry import CalendarEntry
from tefteri.db.models.connection import Connection, SourceContainer
from tefteri.db.models.task import Task
from tefteri.db.repositories.items import TaskRepository
from tefteri.domain.entities import RemoteTask, TaskDraft, TaskPatch
from tefteri.domain.enums import Capability, ConnectionKind, Context, SyncState
from tefteri.domain.errors import NotSupported
from tefteri.domain.ports import TaskBackend
from tefteri.domain.timeutil import overlaps
from tefteri.services import conflicts
from tefteri.services.connections import ConnectionService
from tefteri.services.errors import BackendProblem, Invalid, NotFound, guard
from tefteri.services.mirror import task_values

DEFAULT_SLOT = timedelta(hours=1)
UNSET = object()


class TaskService:
    """Create, change, complete, delete and schedule tasks."""

    def __init__(self, connections: ConnectionService) -> None:
        """Use ``connections`` to reach each task app."""
        self._connections = connections

    async def _connection_of(self, db: AsyncSession, user_id: uuid.UUID, task: Task) -> Connection:
        connection = await self._connections.get(db, user_id, task.connection_id)
        if connection is None:
            raise NotFound
        return connection

    def _backend(self, connection: Connection) -> TaskBackend:
        return cast(TaskBackend, self._connections.backend_for(connection))

    async def get(self, db: AsyncSession, user_id: uuid.UUID, task_id: uuid.UUID) -> Task:
        """Return one of the user's tasks or raise ``NotFound``."""
        task = await TaskRepository(db, user_id).get(task_id)
        if task is None:
            raise NotFound
        return task

    def _apply(self, task: Task, remote: RemoteTask) -> None:
        for key, value in task_values(remote, task.container_id).items():
            setattr(task, key, value)
        task.remote_version = remote.version
        task.sync_state = SyncState.SYNCED.value

    async def create(
        self,
        db: AsyncSession,
        user_id: uuid.UUID,
        *,
        connection_id: uuid.UUID,
        title: str,
        description: str = "",
        due_at: datetime | None = None,
        container_id: uuid.UUID | None = None,
        goal_id: uuid.UUID | None = None,
    ) -> Task:
        """Create a task in the app, then cache it. Nothing is cached when the app fails."""
        connection = await self._connections.get(db, user_id, connection_id)
        if connection is None or connection.kind != ConnectionKind.TASKS.value:
            raise Invalid("connection must be a task connection")
        container = await self._container(db, user_id, connection, container_id)
        remote = await guard(
            connection,
            self._backend(connection).create_task(
                TaskDraft(container.remote_id, title, description, due_at)
            ),
        )
        task = Task(
            connection_id=connection.id,
            container_id=container.id,
            remote_id=remote.remote_id,
            title=remote.title,
            goal_id=goal_id,
        )
        self._apply(task, remote)
        return await TaskRepository(db, user_id).add(task)

    async def _container(
        self,
        db: AsyncSession,
        user_id: uuid.UUID,
        connection: Connection,
        container_id: uuid.UUID | None,
    ) -> SourceContainer:
        query = select(SourceContainer).where(
            SourceContainer.connection_id == connection.id, SourceContainer.user_id == user_id
        )
        if container_id is not None:
            query = query.where(SourceContainer.id == container_id)
        container = (await db.execute(query.order_by(SourceContainer.name))).scalars().first()
        if container is None:
            raise Invalid("no project found: sync the connection first")
        return container

    async def update(
        self,
        db: AsyncSession,
        user_id: uuid.UUID,
        task: Task,
        *,
        title: str | None = None,
        description: str | None = None,
        due_at: datetime | None = None,
        context: object = UNSET,
        goal_id: object = UNSET,
    ) -> Task:
        """Change a task. Remote fields go to the app first; ``context``, ``goal_id`` stay local."""
        if goal_id is not UNSET:
            task.goal_id = None if goal_id is None else uuid.UUID(str(goal_id))
        if context is not UNSET:
            task.context = None if context is None else Context(str(context)).value
        if title is not None or description is not None or due_at is not None:
            connection = await self._connection_of(db, user_id, task)
            try:
                remote = await guard(
                    connection,
                    self._backend(connection).update_task(
                        task.remote_id,
                        TaskPatch(title=title, description=description, due_at=due_at),
                        task.remote_version,
                    ),
                )
            except BackendProblem as problem:
                if problem.code == "remote_conflict":
                    await self._record_conflict(
                        db,
                        user_id,
                        task,
                        connection,
                        {
                            "title": title if title is not None else task.title,
                            "description": description
                            if description is not None
                            else task.description,
                            "status": task.status,
                            "due_at": _iso(due_at or task.due_at),
                        },
                    )
                    problem.message += " Open the Conflicts screen to choose a version."
                raise
            self._apply(task, remote)
        await db.flush()
        return task

    async def _record_conflict(
        self,
        db: AsyncSession,
        user_id: uuid.UUID,
        task: Task,
        connection: Connection,
        local: dict[str, object],
    ) -> None:
        try:
            current = await self._backend(connection).get_task(task.remote_id)
        except Exception:  # noqa: BLE001 - the conflict itself is still reported
            return
        await conflicts.record(db, user_id, "task", task, local, conflicts.task_snapshot(current))

    async def complete(self, db: AsyncSession, user_id: uuid.UUID, task: Task) -> Task:
        """Mark a task done in the app, then in the cache."""
        connection = await self._connection_of(db, user_id, task)
        remote = await guard(connection, self._backend(connection).complete_task(task.remote_id))
        self._apply(task, remote)
        await db.flush()
        return task

    async def delete(self, db: AsyncSession, user_id: uuid.UUID, task: Task) -> None:
        """Delete a task in the app, then in the cache."""
        connection = await self._connection_of(db, user_id, task)
        await guard(connection, self._backend(connection).delete_task(task.remote_id))
        await TaskRepository(db, user_id).delete(task)

    async def set_schedule(
        self,
        db: AsyncSession,
        user_id: uuid.UUID,
        task: Task,
        start: datetime | None,
        end: datetime | None,
    ) -> tuple[Task, list[CalendarEntry]]:
        """Write (or clear, with ``start=None``) the task's time to the task app.

        Creates no calendar event. Returns the task and the calendar entries it overlaps.
        """
        connection = await self._connection_of(db, user_id, task)
        backend = self._backend(connection)
        if Capability.TASK_TIME not in backend.capabilities():
            await guard(connection, _raise_unsupported())
        if start is not None and end is None:
            end = start + DEFAULT_SLOT
        if start is not None and end is not None and end <= start:
            raise Invalid("end must be after start")
        remote = await guard(
            connection, backend.set_schedule(task.remote_id, start, end, task.remote_version)
        )
        self._apply(task, remote)
        await db.flush()
        found: list[CalendarEntry] = []
        if start is not None and end is not None:
            entries = (
                await db.execute(select(CalendarEntry).where(CalendarEntry.user_id == user_id))
            ).scalars()
            found = [
                e
                for e in entries
                if e.sync_state != SyncState.DELETED_REMOTELY.value
                and overlaps(start, end, _aware(e.start), _aware(e.end))
            ]
        return task, found


def _iso(value: datetime | None) -> str | None:
    return value.isoformat() if value else None


def _aware(value: datetime) -> datetime:
    return value if value.tzinfo else value.replace(tzinfo=UTC)


async def _raise_unsupported() -> None:
    raise NotSupported(Capability.TASK_TIME)
