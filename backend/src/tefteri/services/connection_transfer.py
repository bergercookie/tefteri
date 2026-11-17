"""Move a user's connections and the calendar for new events between installations."""

import uuid
from dataclasses import dataclass, field
from typing import Any

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from tefteri.db.models.connection import Connection, SourceContainer
from tefteri.services.connections import ConnectionService, MissingCapability, UnknownProvider
from tefteri.services.errors import Invalid
from tefteri.services.settings import SettingsService
from tefteri.services.sync import SyncService


@dataclass(frozen=True)
class ExportedConnection:
    """A connection with its credentials in the clear. The file that holds it is a secret."""

    provider: str
    display_name: str
    settings: dict[str, Any]
    credentials: dict[str, Any]


@dataclass(frozen=True)
class CalendarRef:
    """A calendar named by the connection that has it and its id in the calendar app."""

    connection: str
    remote_id: str


@dataclass
class ConnectionImport:
    """What an import did with the connections."""

    added: int = 0
    skipped: list[str] = field(default_factory=list)
    """Names of connections that the user already has (same provider and name)."""
    failed: dict[str, str] = field(default_factory=dict)
    """Name and reason of each connection that could not be added."""
    default_calendar_restored: bool = False


class ConnectionTransfer:
    """Export and import connections, with their credentials."""

    def __init__(
        self, connections: ConnectionService, sync: SyncService, settings: SettingsService
    ) -> None:
        """Use the services that create, sync and read the settings."""
        self._connections = connections
        self._sync = sync
        self._settings = settings

    async def export(
        self, db: AsyncSession, user_id: uuid.UUID
    ) -> tuple[list[ExportedConnection], CalendarRef | None]:
        """Return the user's connections and the calendar that new events start in."""
        rows = await self._connections.list(db, user_id)
        out = [
            ExportedConnection(
                c.provider,
                c.display_name,
                dict(c.settings),
                self._connections.credentials_of(c),
            )
            for c in rows
        ]
        chosen = (await self._settings.get(db, user_id)).default_event_container_id
        if chosen is None:
            return out, None
        container = await db.get(SourceContainer, chosen)
        owner = next((c for c in rows if container and c.id == container.connection_id), None)
        if container is None or owner is None:
            return out, None
        return out, CalendarRef(owner.display_name, container.remote_id)

    async def import_(
        self,
        db: AsyncSession,
        user_id: uuid.UUID,
        connections: list[ExportedConnection],
        calendar: CalendarRef | None,
    ) -> ConnectionImport:
        """Add the connections that the user does not have, sync them, then choose the calendar.

        A connection that cannot be added is reported and the others go on. The calendar is
        chosen only when it exists after the sync and can take events.
        """
        result = ConnectionImport()
        have: dict[str, Connection] = {
            c.display_name: c for c in await self._connections.list(db, user_id)
        }
        existing = {(c.provider, c.display_name) for c in have.values()}
        for item in connections:
            if (item.provider, item.display_name) in existing:
                result.skipped.append(item.display_name)
                continue
            if item.display_name in have:
                result.failed[item.display_name] = "A different connection has this name."
                continue
            try:
                created = await self._connections.create(
                    db,
                    user_id,
                    provider=item.provider,
                    display_name=item.display_name,
                    settings=item.settings,
                    credentials=item.credentials,
                )
            except UnknownProvider:
                result.failed[item.display_name] = f"Unknown provider: {item.provider}"
                continue
            except MissingCapability as exc:
                result.failed[item.display_name] = exc.message
                continue
            await self._sync.sync_connection(db, created)
            have[item.display_name] = created
            result.added += 1
        if calendar is not None and calendar.connection in have:
            result.default_calendar_restored = await self._choose(
                db, user_id, have[calendar.connection], calendar.remote_id
            )
        return result

    async def _choose(
        self, db: AsyncSession, user_id: uuid.UUID, connection: Connection, remote_id: str
    ) -> bool:
        container = (
            await db.execute(
                select(SourceContainer).where(
                    SourceContainer.connection_id == connection.id,
                    SourceContainer.remote_id == remote_id,
                )
            )
        ).scalar_one_or_none()
        if container is None:
            return False
        try:
            await self._settings.update(db, user_id, default_event_container_id=container.id)
        except Invalid:
            return False
        return True
