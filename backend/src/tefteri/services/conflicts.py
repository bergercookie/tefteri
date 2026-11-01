"""Conflicts: a change made both in tefteri and in the connected app is never merged silently.

A conflict is recorded when a write is refused because the remote item changed (stale
version). The item is marked ``conflict`` and both versions are kept until the user picks one.
"""

import uuid
from datetime import UTC, datetime
from typing import Any, cast

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from tefteri.db.models.calendar_entry import CalendarEntry
from tefteri.db.models.sync import Conflict
from tefteri.db.models.task import Task
from tefteri.domain.entities import EntryPatch, RemoteEntry, RemoteTask, TaskPatch
from tefteri.domain.enums import Resolution, SyncState
from tefteri.domain.ports import CalendarBackend, TaskBackend
from tefteri.services.connections import ConnectionService
from tefteri.services.errors import Invalid, NotFound, guard
from tefteri.services.mirror import entry_values, task_values


def _iso(value: datetime | None) -> str | None:
    return value.isoformat() if value else None


def _dt(value: str | None) -> datetime | None:
    return datetime.fromisoformat(value) if value else None


def task_snapshot(item: Task | RemoteTask) -> dict[str, Any]:
    """Return the user-visible fields of a task or remote task."""
    if isinstance(item, Task):
        return {
            "title": item.title,
            "description": item.description,
            "status": item.status,
            "due_at": _iso(item.due_at),
        }
    return {
        "title": item.title,
        "description": item.description,
        "status": "done" if item.done else "open",
        "due_at": _iso(item.due_at),
    }


def entry_snapshot(item: CalendarEntry | RemoteEntry) -> dict[str, Any]:
    """Return the user-visible fields of an entry or remote entry."""
    return {
        "title": item.title,
        "start": _iso(item.start),
        "end": _iso(item.end),
        "location": item.location,
    }


async def record(
    db: AsyncSession,
    user_id: uuid.UUID,
    entity_type: str,
    row: Task | CalendarEntry,
    local: dict[str, Any],
    remote: dict[str, Any],
) -> Conflict:
    """Store a conflict, mark the item and commit, so the record survives the failed request."""
    existing = (
        await db.execute(
            select(Conflict).where(Conflict.entity_id == row.id, Conflict.resolved_at.is_(None))
        )
    ).scalar_one_or_none()
    conflict = existing or Conflict(
        user_id=user_id,
        entity_type=entity_type,
        entity_id=row.id,
        local_snapshot={},
        remote_snapshot={},
    )
    conflict.local_snapshot = local
    conflict.remote_snapshot = remote
    row.sync_state = SyncState.CONFLICT.value
    db.add(conflict)
    await db.commit()
    return conflict


class ConflictService:
    """List and resolve conflicts. Resolution is always the user's explicit choice."""

    def __init__(self, connections: ConnectionService) -> None:
        """Use ``connections`` to reach the apps."""
        self._connections = connections

    async def list_open(self, db: AsyncSession, user_id: uuid.UUID) -> list[Conflict]:
        """Return the user's unresolved conflicts, oldest first."""
        rows = await db.execute(
            select(Conflict)
            .where(Conflict.user_id == user_id, Conflict.resolved_at.is_(None))
            .order_by(Conflict.created_at)
        )
        return list(rows.scalars())

    async def resolve(
        self, db: AsyncSession, user_id: uuid.UUID, conflict_id: uuid.UUID, resolution: Resolution
    ) -> None:
        """Keep the local or the remote version and mark the conflict resolved."""
        conflict = (
            await db.execute(
                select(Conflict).where(Conflict.id == conflict_id, Conflict.user_id == user_id)
            )
        ).scalar_one_or_none()
        if conflict is None or conflict.resolved_at is not None:
            raise NotFound
        if conflict.entity_type == "task":
            await self._resolve_task(db, user_id, conflict, resolution)
        elif conflict.entity_type == "entry":
            await self._resolve_entry(db, user_id, conflict, resolution)
        else:
            raise Invalid("unsupported conflict type")
        conflict.resolution = resolution.value
        conflict.resolved_at = datetime.now(UTC)
        await db.flush()

    async def _resolve_task(
        self, db: AsyncSession, user_id: uuid.UUID, conflict: Conflict, resolution: Resolution
    ) -> None:
        task = (
            await db.execute(
                select(Task).where(Task.id == conflict.entity_id, Task.user_id == user_id)
            )
        ).scalar_one_or_none()
        if task is None:
            raise NotFound
        connection = await self._connections.get(db, user_id, task.connection_id)
        if connection is None:
            raise NotFound
        backend = cast(TaskBackend, self._connections.backend_for(connection))
        current = await guard(connection, backend.get_task(task.remote_id))
        if resolution is Resolution.KEEP_LOCAL:
            local = conflict.local_snapshot
            current = await guard(
                connection,
                backend.update_task(
                    task.remote_id,
                    TaskPatch(
                        title=local.get("title"),
                        description=local.get("description"),
                        due_at=_dt(local.get("due_at")),
                    ),
                    current.version,
                ),
            )
        for key, value in task_values(current, task.container_id).items():
            setattr(task, key, value)
        task.remote_version = current.version
        task.sync_state = SyncState.SYNCED.value

    async def _resolve_entry(
        self, db: AsyncSession, user_id: uuid.UUID, conflict: Conflict, resolution: Resolution
    ) -> None:
        entry = (
            await db.execute(
                select(CalendarEntry).where(
                    CalendarEntry.id == conflict.entity_id, CalendarEntry.user_id == user_id
                )
            )
        ).scalar_one_or_none()
        if entry is None:
            raise NotFound
        connection = await self._connections.get(db, user_id, entry.connection_id)
        if connection is None:
            raise NotFound
        backend = cast(CalendarBackend, self._connections.backend_for(connection))
        current = await guard(connection, backend.get_entry(entry.remote_id))
        if resolution is Resolution.KEEP_LOCAL:
            local = conflict.local_snapshot
            current = await guard(
                connection,
                backend.update_entry(
                    entry.remote_id,
                    EntryPatch(
                        title=local.get("title"),
                        start=_dt(local.get("start")),
                        end=_dt(local.get("end")),
                        location=local.get("location"),
                    ),
                    current.version,
                ),
            )
        for key, value in entry_values(current, entry.container_id).items():
            setattr(entry, key, value)
        entry.remote_version = current.version
        entry.sync_state = SyncState.SYNCED.value
