"""Task use cases: write through to the task app first, then update the cache."""

import uuid
from datetime import UTC, date, datetime
from random import Random
from typing import cast

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from tefteri.db.models.calendar_entry import CalendarEntry
from tefteri.db.models.connection import Connection, SourceContainer
from tefteri.db.models.task import Task
from tefteri.db.models.user import User
from tefteri.db.repositories.items import TaskRepository
from tefteri.domain.entities import Container, RemoteTask, TaskDraft, TaskPatch
from tefteri.domain.enums import Capability, ConnectionKind, SyncState
from tefteri.domain.errors import NotSupported
from tefteri.domain.planning_time import (
    all_day_due,
    block_for,
    due_for_block_start,
    pick_random_start,
)
from tefteri.domain.ports import TaskBackend
from tefteri.domain.timeutil import overlaps
from tefteri.services import conflicts
from tefteri.services.connections import ConnectionService
from tefteri.services.errors import BackendProblem, Invalid, NotFound, guard
from tefteri.services.mirror import task_values, to_utc

UNSET = object()


class TaskService:
    """Create, change, complete, delete and schedule tasks."""

    def __init__(self, connections: ConnectionService, rng: Random | None = None) -> None:
        """Use ``connections`` to reach each task app; ``rng`` picks random times (tests inject)."""
        self._connections = connections
        self._rng = rng or Random()  # noqa: S311 - not a security use

    async def _connection_of(self, db: AsyncSession, user_id: uuid.UUID, task: Task) -> Connection:
        connection = await self._connections.get(db, user_id, task.connection_id)
        if connection is None:
            raise NotFound
        return connection

    async def _backend(self, db: AsyncSession, connection: Connection) -> TaskBackend:
        return cast(TaskBackend, await self._connections.backend_of_owner(db, connection))

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
        labels: tuple[str, ...] = (),
    ) -> Task:
        """Create a task in the app, then cache it. Nothing is cached when the app fails."""
        connection = await self._connections.get(db, user_id, connection_id)
        if connection is None or connection.kind != ConnectionKind.TASKS.value:
            raise Invalid("connection must be a task connection")
        container = await self._container(db, user_id, connection, container_id)
        remote = await guard(
            connection,
            (await self._backend(db, connection)).create_task(
                TaskDraft(container.remote_id, title, description, due_at, labels)
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
        goal_id: object = UNSET,
    ) -> Task:
        """Change a task. Remote fields go to the app first; ``goal_id`` stays local."""
        if goal_id is not UNSET:
            task.goal_id = None if goal_id is None else uuid.UUID(str(goal_id))
        if title is not None or description is not None or due_at is not None:
            connection = await self._connection_of(db, user_id, task)
            try:
                remote = await guard(
                    connection,
                    (await self._backend(db, connection)).update_task(
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
            current = await (await self._backend(db, connection)).get_task(task.remote_id)
        except Exception:  # noqa: BLE001 - the conflict itself is still reported
            return
        await conflicts.record(db, user_id, "task", task, local, conflicts.task_snapshot(current))

    async def complete(self, db: AsyncSession, user_id: uuid.UUID, task: Task) -> Task:
        """Mark a task done in the app, then in the cache."""
        connection = await self._connection_of(db, user_id, task)
        backend = await self._backend(db, connection)
        remote = await guard(connection, backend.complete_task(task.remote_id))
        self._apply(task, remote)
        await db.flush()
        return task

    async def reopen(self, db: AsyncSession, user_id: uuid.UUID, task: Task) -> Task:
        """Mark a done task open again in the app, then in the cache."""
        connection = await self._connection_of(db, user_id, task)
        backend = await self._backend(db, connection)
        remote = await guard(connection, backend.reopen_task(task.remote_id))
        self._apply(task, remote)
        await db.flush()
        return task

    async def reminder(
        self, db: AsyncSession, user_id: uuid.UUID, task: Task
    ) -> tuple[bool, int | None]:
        """Return whether the task app has reminders, and the minutes before the due time.

        The reminder is read from the app: it can be changed there too.
        """
        connection = await self._connection_of(db, user_id, task)
        backend = await self._backend(db, connection)
        if Capability.TASK_REMINDERS not in backend.capabilities():
            return False, None
        return True, await guard(connection, backend.get_reminder(task.remote_id))

    async def set_reminder(
        self,
        db: AsyncSession,
        user_id: uuid.UUID,
        task: Task,
        minutes_before: int | None,
        *,
        use_default: bool = False,
    ) -> int | None:
        """Remind before the due time of the task in the app, or remove the reminder.

        ``use_default`` takes the offset from the user's setting. A reminder is relative to the
        due time, so a task with no time of day cannot have one.
        """
        connection = await self._connection_of(db, user_id, task)
        backend = await self._backend(db, connection)
        if Capability.TASK_REMINDERS not in backend.capabilities():
            raise BackendProblem(
                "not_supported",
                connection.display_name,
                f"{connection.display_name} does not support reminders.",
            )
        if use_default:
            minutes_before = (await _owner(db, user_id)).default_reminder_minutes
        if minutes_before is not None and (task.due_at is None or task.all_day):
            raise Invalid("Give the task a day and a time before you add a reminder.")
        remote = await guard(connection, backend.set_reminder(task.remote_id, minutes_before))
        self._apply(task, remote)
        await db.flush()
        return minutes_before

    async def delete(self, db: AsyncSession, user_id: uuid.UUID, task: Task) -> None:
        """Delete a task in the app, then in the cache."""
        connection = await self._connection_of(db, user_id, task)
        await guard(connection, (await self._backend(db, connection)).delete_task(task.remote_id))
        await TaskRepository(db, user_id).delete(task)

    async def move_to_container(
        self, db: AsyncSession, user_id: uuid.UUID, task: Task, container: SourceContainer
    ) -> Task:
        """Move a task to another project in the task app, then in the cache (spec 004).

        The cache changes only after the app answered, so a refused move leaves both as they
        were. The app needs the capability ``MOVE_TASKS``.
        """
        connection = await self._connection_of(db, user_id, task)
        backend = await self._backend(db, connection)
        if Capability.MOVE_TASKS not in backend.capabilities():
            await guard(connection, _raise_unsupported(Capability.MOVE_TASKS))
        remote = await guard(
            connection,
            backend.move_task(
                task.remote_id,
                Container(container.remote_id, container.name, container.parent_remote_id),
                task.remote_version,
            ),
        )
        task.container_id = container.id
        self._apply(task, remote)
        await db.flush()
        return task

    async def schedule_at(
        self, db: AsyncSession, user_id: uuid.UUID, task: Task, start: datetime
    ) -> tuple[Task, list[CalendarEntry]]:
        """Plan the task's block to start at ``start`` (snapped to 15 minutes).

        Only the due date is written to the task app: one hour after the block start. Creates
        no calendar event. Returns the task and the calendar entries its block overlaps.
        """
        due = due_for_block_start(_aware(start))
        task = await self._write_planned_time(db, user_id, task, due, all_day=False)
        return task, await self._overlaps(db, user_id, due)

    async def schedule_date(
        self, db: AsyncSession, user_id: uuid.UUID, task: Task, day: date
    ) -> tuple[Task, list[CalendarEntry]]:
        """Plan the task for a date only, with no time.

        The task becomes all-day. If the user turned on ``random_time_on_date_drop``, it gets a
        random block start between 08:00 and 19:45 local time on that date instead.
        """
        owner = await _owner(db, user_id)
        if owner.random_time_on_date_drop:
            start = pick_random_start(day, owner.timezone, self._rng)
            return await self.schedule_at(db, user_id, task, start)
        due = all_day_due(day, owner.timezone)
        task = await self._write_planned_time(db, user_id, task, due, all_day=True)
        return task, []

    async def unschedule(self, db: AsyncSession, user_id: uuid.UUID, task: Task) -> Task:
        """Remove the task's due date and time in the task app."""
        return await self._write_planned_time(db, user_id, task, None, all_day=False)

    async def _write_planned_time(
        self,
        db: AsyncSession,
        user_id: uuid.UUID,
        task: Task,
        due_at: datetime | None,
        *,
        all_day: bool,
    ) -> Task:
        connection = await self._connection_of(db, user_id, task)
        backend = await self._backend(db, connection)
        if Capability.TASK_TIME not in backend.capabilities():
            await guard(connection, _raise_unsupported(Capability.TASK_TIME))
        try:
            remote = await guard(
                connection,
                backend.set_planned_time(task.remote_id, due_at, all_day, task.remote_version),
            )
        except BackendProblem as problem:
            if problem.code == "remote_conflict" and due_at is not None:
                # Same handling as an edit: keep both versions and let the user choose.
                await self._record_conflict(
                    db,
                    user_id,
                    task,
                    connection,
                    {
                        "title": task.title,
                        "description": task.description,
                        "status": task.status,
                        "due_at": _iso(due_at),
                    },
                )
                problem.message += " Open the Conflicts screen to choose a version."
            raise
        self._apply(task, remote)
        await db.flush()
        return task

    async def _overlaps(
        self, db: AsyncSession, user_id: uuid.UUID, due: datetime
    ) -> list[CalendarEntry]:
        owner = await _owner(db, user_id)
        block = block_for(due, owner.timezone)
        entries = (
            await db.execute(select(CalendarEntry).where(CalendarEntry.user_id == user_id))
        ).scalars()
        return [
            e
            for e in entries
            if e.sync_state != SyncState.DELETED_REMOTELY.value
            and overlaps(block.start, block.end, _aware(e.start), _aware(e.end))
        ]


async def _owner(db: AsyncSession, user_id: uuid.UUID) -> User:
    owner = await db.get(User, user_id)
    if owner is None:
        raise NotFound
    return owner


def _iso(value: datetime | None) -> str | None:
    """A time as text, always in UTC with its zone: the cache drops the zone, an app keeps it."""
    return to_utc(value).isoformat() if value else None


def _aware(value: datetime) -> datetime:
    return value if value.tzinfo else value.replace(tzinfo=UTC)


async def _raise_unsupported(capability: Capability) -> None:
    raise NotSupported(capability)
