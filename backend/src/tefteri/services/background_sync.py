"""Sync every connection of every user at a regular interval."""

import asyncio
import logging
import uuid
from collections.abc import Awaitable, Callable
from datetime import UTC, datetime, timedelta

from sqlalchemy import delete, select
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker

from tefteri.db.models.connection import Connection
from tefteri.db.models.sync import SyncRun
from tefteri.db.session import session_scope
from tefteri.domain.enums import ConnectionStatus
from tefteri.services.sync import SyncService

logger = logging.getLogger(__name__)

SYNC_RUN_KEEP = timedelta(days=30)
"""How long the record of a sync is kept. One record per connection and per run adds up."""


class BackgroundSync:
    """Runs ``SyncService`` for all users, now and then.

    A connection that needs attention (the app rejects its token) is left out: the user has to
    fix it first, and trying again each hour would only repeat the same error. A manual sync
    still tries it. One failing connection or user never stops the others.
    """

    def __init__(
        self,
        factory: async_sessionmaker[AsyncSession],
        sync: SyncService,
        interval: timedelta,
        *,
        first_run_after: timedelta = timedelta(seconds=30),
        sleep: Callable[[float], Awaitable[None]] = asyncio.sleep,
        clock: Callable[[], datetime] = lambda: datetime.now(UTC),
    ) -> None:
        """Sync every ``interval``; the first run is ``first_run_after`` after the start."""
        self._factory = factory
        self._sync = sync
        self._interval = interval
        self._first = first_run_after
        self._sleep = sleep
        self._clock = clock

    async def run_forever(self) -> None:
        """Wait, sync, wait, sync... until the task is cancelled."""
        delay = self._first
        while True:
            await self._sleep(delay.total_seconds())
            try:
                await self.run_once()
            except Exception:
                # The loop must outlive one bad run (a database that is busy, for example).
                logger.exception("Background sync failed")
            delay = self._interval

    async def run_once(self) -> int:
        """Sync the connections of all users once. Returns how many connections were synced."""
        async with session_scope(self._factory) as db:
            user_ids = list(
                (
                    await db.execute(
                        select(Connection.user_id).distinct().order_by(Connection.user_id)
                    )
                ).scalars()
            )
        synced = 0
        for user_id in user_ids:
            try:
                synced += await self._sync_user(user_id)
            except Exception:
                logger.exception("Background sync of user %s failed", user_id)
        await self._prune()
        logger.info("Background sync: %d connection(s) of %d user(s)", synced, len(user_ids))
        return synced

    async def _sync_user(self, user_id: uuid.UUID) -> int:
        """Sync the connections of one user, each in its own session and transaction."""
        async with session_scope(self._factory) as db:
            ids = [
                c.id
                for c in (
                    await db.execute(select(Connection).where(Connection.user_id == user_id))
                ).scalars()
                if c.status != ConnectionStatus.NEEDS_ATTENTION.value
            ]
        count = 0
        for connection_id in ids:
            async with session_scope(self._factory) as db:
                connection = await db.get(Connection, connection_id)
                if connection is None:  # removed while we were busy
                    continue
                await self._sync.sync_connection(db, connection)
                count += 1
        return count

    async def _prune(self) -> None:
        """Forget the record of syncs that are older than ``SYNC_RUN_KEEP``."""
        async with session_scope(self._factory) as db:
            await db.execute(
                delete(SyncRun).where(SyncRun.started_at < self._clock() - SYNC_RUN_KEEP)
            )
