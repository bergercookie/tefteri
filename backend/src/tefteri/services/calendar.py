"""Calendar entry use cases: write through to the calendar app, then update the cache."""

import uuid
from datetime import UTC, datetime, time, timedelta
from typing import cast
from zoneinfo import ZoneInfo

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from tefteri.db.models.calendar_entry import CalendarEntry
from tefteri.db.models.connection import Connection, SourceContainer
from tefteri.db.models.user import User
from tefteri.db.repositories.items import EntryRepository
from tefteri.domain.entities import EntryDraft, EntryPatch, RemoteEntry
from tefteri.domain.enums import ConnectionKind, SyncState
from tefteri.domain.ports import CalendarBackend
from tefteri.services import conflicts
from tefteri.services.connections import ConnectionService
from tefteri.services.errors import BackendProblem, Invalid, NotFound, guard
from tefteri.services.mirror import anchor_all_day, entry_values, to_utc


class CalendarService:
    """Create, change and delete calendar entries."""

    def __init__(self, connections: ConnectionService) -> None:
        """Use ``connections`` to reach each calendar app."""
        self._connections = connections

    def _backend(self, connection: Connection) -> CalendarBackend:
        return cast(CalendarBackend, self._connections.backend_for(connection))

    async def get(self, db: AsyncSession, user_id: uuid.UUID, entry_id: uuid.UUID) -> CalendarEntry:
        """Return one of the user's entries or raise ``NotFound``."""
        entry = await EntryRepository(db, user_id).get(entry_id)
        if entry is None:
            raise NotFound
        return entry

    async def _connection_of(
        self, db: AsyncSession, user_id: uuid.UUID, entry: CalendarEntry
    ) -> Connection:
        connection = await self._connections.get(db, user_id, entry.connection_id)
        if connection is None:
            raise NotFound
        return connection

    async def _ensure_writable(self, db: AsyncSession, entry: CalendarEntry) -> None:
        """Refuse a change in a calendar that the user cannot change in the app."""
        if entry.container_id is None:
            return
        container = await db.get(SourceContainer, entry.container_id)
        if container is not None and container.read_only:
            raise Invalid(f'The calendar "{container.name}" is read-only. Nothing was changed.')

    @staticmethod
    async def _tz(db: AsyncSession, user_id: uuid.UUID) -> str:
        owner = await db.get(User, user_id)
        return owner.timezone if owner is not None else "UTC"

    def _apply(self, entry: CalendarEntry, remote: RemoteEntry, tz_name: str = "UTC") -> None:
        # An all-day event comes back as dates: put it on the local days of the user.
        remote = anchor_all_day(remote, tz_name)
        for key, value in entry_values(remote, entry.container_id).items():
            setattr(entry, key, value)
        entry.remote_version = remote.version
        entry.sync_state = SyncState.SYNCED.value

    async def create(
        self,
        db: AsyncSession,
        user_id: uuid.UUID,
        *,
        connection_id: uuid.UUID,
        title: str,
        start: datetime,
        end: datetime,
        all_day: bool = False,
        location: str = "",
        container_id: uuid.UUID | None = None,
    ) -> CalendarEntry:
        """Create an event in the calendar app, then cache it."""
        connection = await self._connections.get(db, user_id, connection_id)
        if connection is None or connection.kind != ConnectionKind.CALENDAR.value:
            raise Invalid("connection must be a calendar connection")
        if end <= start:
            raise Invalid("end must be after start")
        tz_name = await self._tz(db, user_id)
        if all_day:
            # An all-day event is dates. Take the days of the user, not of UTC: local midnight
            # of 20 November in Athens is 19 November in UTC.
            zone = ZoneInfo(tz_name)
            first = to_utc(start).astimezone(zone).date()
            last = max(to_utc(end).astimezone(zone).date(), first + timedelta(days=1))
            start = datetime.combine(first, time(0), tzinfo=UTC)
            end = datetime.combine(last, time(0), tzinfo=UTC)
        query = select(SourceContainer).where(
            SourceContainer.connection_id == connection.id, SourceContainer.user_id == user_id
        )
        if container_id is not None:
            query = query.where(SourceContainer.id == container_id)
        # Only a calendar that the user chose, and may change, takes a new event.
        query = query.where(SourceContainer.enabled.is_(True), SourceContainer.read_only.is_(False))
        container = (await db.execute(query.order_by(SourceContainer.name))).scalars().first()
        if container is None:
            raise Invalid(
                "no calendar that you can change was found: choose a calendar and sync the "
                "connection first"
            )
        remote = await guard(
            connection,
            self._backend(connection).create_entry(
                EntryDraft(container.remote_id, title, start, end, all_day, location)
            ),
        )
        entry = CalendarEntry(
            connection_id=connection.id,
            container_id=container.id,
            remote_id=remote.remote_id,
            title=remote.title,
            start=remote.start,
            end=remote.end,
        )
        self._apply(entry, remote, tz_name)
        return await EntryRepository(db, user_id).add(entry)

    async def update(
        self,
        db: AsyncSession,
        user_id: uuid.UUID,
        entry: CalendarEntry,
        *,
        title: str | None = None,
        start: datetime | None = None,
        end: datetime | None = None,
        location: str | None = None,
    ) -> CalendarEntry:
        """Change an entry. Remote fields go to the app first."""
        await self._ensure_writable(db, entry)
        if any(v is not None for v in (title, start, end, location)):
            connection = await self._connection_of(db, user_id, entry)
            try:
                remote = await guard(
                    connection,
                    self._backend(connection).update_entry(
                        entry.remote_id,
                        EntryPatch(title=title, start=start, end=end, location=location),
                        entry.remote_version,
                    ),
                )
            except BackendProblem as problem:
                if problem.code == "remote_conflict":
                    try:
                        current = await self._backend(connection).get_entry(entry.remote_id)
                    except Exception:  # noqa: BLE001 - the conflict itself is still reported
                        raise problem from None
                    local = {
                        "title": title if title is not None else entry.title,
                        "start": to_utc(start or entry.start).isoformat(),
                        "end": to_utc(end or entry.end).isoformat(),
                        "location": location if location is not None else entry.location,
                    }
                    await conflicts.record(
                        db, user_id, "entry", entry, local, conflicts.entry_snapshot(current)
                    )
                    problem.message += " Open the Conflicts screen to choose a version."
                raise
            self._apply(entry, remote, await self._tz(db, user_id))
        await db.flush()
        return entry

    async def delete(self, db: AsyncSession, user_id: uuid.UUID, entry: CalendarEntry) -> None:
        """Delete an event in the app, then in the cache."""
        await self._ensure_writable(db, entry)
        connection = await self._connection_of(db, user_id, entry)
        await guard(connection, self._backend(connection).delete_entry(entry.remote_id))
        await EntryRepository(db, user_id).delete(entry)
