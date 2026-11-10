"""On-demand sync of connections into the local cache (failures are isolated per connection)."""

import asyncio
import logging
import uuid
from collections.abc import Callable
from dataclasses import dataclass, field
from datetime import UTC, datetime, timedelta
from typing import Any

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from tefteri.db.models.calendar_entry import CalendarEntry
from tefteri.db.models.connection import Connection, SourceContainer
from tefteri.db.models.note import Note
from tefteri.db.models.sync import SyncRun
from tefteri.db.models.task import Task
from tefteri.db.models.user import User
from tefteri.domain.entities import Container
from tefteri.domain.enums import ConnectionKind, ConnectionStatus, SyncState
from tefteri.domain.errors import AuthExpired, BackendError, BackendUnavailable
from tefteri.domain.ports import CalendarBackend, NoteBackend, TaskBackend
from tefteri.services.connections import ConnectionService
from tefteri.services.mirror import anchor_all_day, entry_values, note_values, task_values

logger = logging.getLogger(__name__)

CALENDAR_PAST = timedelta(days=90)
CALENDAR_FUTURE = timedelta(days=400)


@dataclass
class SyncResult:
    """Outcome of syncing one connection."""

    connection_id: uuid.UUID
    name: str
    outcome: str  # 'ok' | 'needs_attention' | 'error'
    reason: str | None = None  # 'unreachable' | 'auth_expired' | 'error'
    detail: str | None = None  # the underlying error, e.g. which address could not be reached
    counts: dict[str, int] = field(
        default_factory=lambda: {"created": 0, "updated": 0, "deleted": 0}
    )


def _upsert(
    db: AsyncSession,
    existing: dict[str, Any],
    seen: set[str],
    counts: dict[str, int],
    model: type[Any],
    connection: Connection,
    remote_id: str,
    version: str,
    values: dict[str, Any],
) -> None:
    """Insert or update one mirror row, never touching rows in conflict."""
    seen.add(remote_id)
    row = existing.get(remote_id)
    if row is None:
        row = model(
            user_id=connection.user_id,
            connection_id=connection.id,
            remote_id=remote_id,
            remote_version=version,
            **values,
        )
        db.add(row)
        existing[remote_id] = row
        counts["created"] += 1
    elif row.sync_state == SyncState.CONFLICT.value:
        return
    elif row.remote_version != version or row.sync_state == SyncState.DELETED_REMOTELY.value:
        for key, value in values.items():
            setattr(row, key, value)
        row.remote_version = version
        row.sync_state = SyncState.SYNCED.value
        counts["updated"] += 1


def _mark_deleted(existing: dict[str, Any], seen: set[str], counts: dict[str, int]) -> None:
    for remote_id, row in existing.items():
        if remote_id not in seen and row.sync_state == SyncState.SYNCED.value:
            row.sync_state = SyncState.DELETED_REMOTELY.value
            counts["deleted"] += 1


class SyncService:
    """Pull data from each connected app into the cache."""

    def __init__(
        self,
        connections: ConnectionService,
        clock: Callable[[], datetime] = lambda: datetime.now(UTC),
    ) -> None:
        """Use ``connections`` to build backends; ``clock`` is injectable for tests."""
        self._connections = connections
        self._clock = clock
        self._locks: dict[uuid.UUID, asyncio.Lock] = {}

    async def sync_all(self, db: AsyncSession, user_id: uuid.UUID) -> list[SyncResult]:
        """Sync every connection of the user; one failing connection never stops the others."""
        results = []
        for connection in await self._connections.list(db, user_id):
            results.append(await self.sync_connection(db, connection))
        return results

    async def sync_connection(self, db: AsyncSession, connection: Connection) -> SyncResult:
        """Sync one connection and record a ``SyncRun``; failures become a structured result.

        Two syncs of the same connection never run at once (a scheduled one and a manual one, or
        a double click): the second waits for the first, and then syncs on top of its result.
        """
        lock = self._locks.setdefault(connection.id, asyncio.Lock())
        async with lock:
            return await self._sync_locked(db, connection)

    async def _sync_locked(self, db: AsyncSession, connection: Connection) -> SyncResult:
        result = SyncResult(connection.id, connection.display_name, "ok")
        started = self._clock()
        try:
            async with db.begin_nested():
                backend = await self._connections.backend_of_owner(db, connection)
                containers = await self._sync_containers(db, connection, backend)
                kind = ConnectionKind(connection.kind)
                if kind is ConnectionKind.TASKS:
                    await self._sync_tasks(db, connection, backend, containers, result.counts)  # type: ignore[arg-type]
                elif kind is ConnectionKind.CALENDAR:
                    await self._sync_calendar(db, connection, backend, containers, result.counts)  # type: ignore[arg-type]
                else:
                    await self._sync_notes(db, connection, backend, containers, result.counts)  # type: ignore[arg-type]
        except AuthExpired as exc:
            result.outcome, result.reason = ConnectionStatus.NEEDS_ATTENTION.value, "auth_expired"
            result.detail = str(exc)
        except BackendUnavailable as exc:
            result.outcome, result.reason = ConnectionStatus.ERROR.value, "unreachable"
            result.detail = str(exc)
        except Exception as exc:  # noqa: BLE001 - isolate any adapter failure to this connection
            result.outcome, result.reason = ConnectionStatus.ERROR.value, "error"
            result.detail = str(exc) or type(exc).__name__
            logger.exception("Sync of connection %s failed", connection.id)
        if result.reason in ("auth_expired", "unreachable"):
            logger.warning("Sync of connection %s: %s", connection.id, result.detail)
        connection.status = result.outcome
        connection.last_sync_at = self._clock()
        connection.last_sync_outcome = result.outcome if result.reason is None else result.reason
        db.add(
            SyncRun(
                user_id=connection.user_id,
                connection_id=connection.id,
                started_at=started,
                finished_at=self._clock(),
                outcome=result.outcome,
                counts=result.counts,
                error=result.reason,
            )
        )
        await db.flush()
        return result

    async def sync_projects(
        self, db: AsyncSession, connection: Connection, rows: list[SourceContainer]
    ) -> dict[str, int]:
        """Sync the tasks of some projects only (cheap enough to repeat every few seconds).

        Unlike ``sync_connection`` this reads no other project, writes no ``SyncRun`` and leaves
        the connection status alone. A task that left a listed project is marked deleted until
        the next full sync finds it in its new project.
        """
        counts = {"created": 0, "updated": 0, "deleted": 0}
        backend = await self._connections.backend_of_owner(db, connection)
        if connection.kind != ConnectionKind.TASKS.value:
            return counts
        existing = {
            t.remote_id: t
            for t in (
                await db.execute(select(Task).where(Task.connection_id == connection.id))
            ).scalars()
        }
        for row in rows:
            seen: set[str] = set()
            container = Container(row.remote_id, row.name, row.parent_remote_id)
            for item in (await backend.list_tasks(container, None)).items:  # type: ignore[attr-defined]
                _upsert(
                    db,
                    existing,
                    seen,
                    counts,
                    Task,
                    connection,
                    item.remote_id,
                    item.version,
                    task_values(item, row.id),
                )
            _mark_deleted(
                {k: t for k, t in existing.items() if t.container_id == row.id}, seen, counts
            )
        await db.flush()
        return counts

    async def _sync_containers(
        self, db: AsyncSession, connection: Connection, backend: Any
    ) -> dict[str, tuple[Container, uuid.UUID]]:
        remote = await backend.list_containers()
        rows = {
            c.remote_id: c
            for c in (
                await db.execute(
                    select(SourceContainer).where(SourceContainer.connection_id == connection.id)
                )
            ).scalars()
        }
        out: dict[str, tuple[Container, uuid.UUID]] = {}
        for container in remote:
            row = rows.get(container.remote_id)
            if row is None:
                row = SourceContainer(
                    user_id=connection.user_id,
                    connection_id=connection.id,
                    remote_id=container.remote_id,
                    name=container.name,
                    parent_remote_id=container.parent_id,
                    color=container.color,
                    read_only=container.read_only,
                    enabled=container.enabled_by_default,
                )
                db.add(row)
            else:
                row.name = container.name
                row.parent_remote_id = container.parent_id
                row.color = container.color
                row.read_only = container.read_only
            await db.flush()
            # A container that the user switched off stays known (it is in the list to choose
            # from) but is not synced: its items are not seen, so they leave the cache.
            if row.enabled:
                out[container.remote_id] = (container, row.id)
        # A container that the app no longer lists is gone there (deleted, or never one). Its
        # tasks, entries and notes are marked deleted by the sync that follows.
        listed = {c.remote_id for c in remote}
        for remote_id, row in rows.items():
            if remote_id not in listed:
                await db.delete(row)
        await db.flush()
        return out

    async def _sync_tasks(
        self,
        db: AsyncSession,
        connection: Connection,
        backend: TaskBackend,
        containers: dict[str, tuple[Container, uuid.UUID]],
        counts: dict[str, int],
    ) -> None:
        existing = {
            t.remote_id: t
            for t in (
                await db.execute(select(Task).where(Task.connection_id == connection.id))
            ).scalars()
        }
        seen: set[str] = set()
        for container, container_row_id in containers.values():
            for item in (await backend.list_tasks(container, None)).items:
                _upsert(
                    db,
                    existing,
                    seen,
                    counts,
                    Task,
                    connection,
                    item.remote_id,
                    item.version,
                    task_values(item, container_row_id),
                )
        _mark_deleted(existing, seen, counts)

    async def _sync_calendar(
        self,
        db: AsyncSession,
        connection: Connection,
        backend: CalendarBackend,
        containers: dict[str, tuple[Container, uuid.UUID]],
        counts: dict[str, int],
    ) -> None:
        existing = {
            e.remote_id: e
            for e in (
                await db.execute(
                    select(CalendarEntry).where(CalendarEntry.connection_id == connection.id)
                )
            ).scalars()
        }
        seen: set[str] = set()
        now = self._clock()
        owner = await db.get(User, connection.user_id)
        tz_name = owner.timezone if owner is not None else "UTC"
        for container, container_row_id in containers.values():
            try:
                page = await backend.list_entries(
                    container, now - CALENDAR_PAST, now + CALENDAR_FUTURE, None
                )
            except (AuthExpired, BackendUnavailable):
                raise  # the whole account has a problem
            except BackendError:
                # One calendar that the app refuses must not stop the others. Keep what the
                # cache already holds of it: not seeing it now does not mean it is gone.
                logger.warning(
                    "Sync of connection %s: skipped calendar %r", connection.id, container.name
                )
                counts["skipped"] = counts.get("skipped", 0) + 1
                seen.update(
                    remote_id
                    for remote_id, entry in existing.items()
                    if entry.container_id == container_row_id
                )
                continue
            for item in page.items:
                _upsert(
                    db,
                    existing,
                    seen,
                    counts,
                    CalendarEntry,
                    connection,
                    item.remote_id,
                    item.version,
                    entry_values(anchor_all_day(item, tz_name), container_row_id),
                )
        _mark_deleted(existing, seen, counts)

    async def _sync_notes(
        self,
        db: AsyncSession,
        connection: Connection,
        backend: NoteBackend,
        containers: dict[str, tuple[Container, uuid.UUID]],
        counts: dict[str, int],
    ) -> None:
        existing = {
            n.remote_id: n
            for n in (
                await db.execute(select(Note).where(Note.connection_id == connection.id))
            ).scalars()
        }
        seen: set[str] = set()
        for container, _ in containers.values():
            for item in await backend.list_notes(container, None):
                _upsert(
                    db,
                    existing,
                    seen,
                    counts,
                    Note,
                    connection,
                    item.remote_id,
                    item.version,
                    note_values(item),
                )
        _mark_deleted(existing, seen, counts)
