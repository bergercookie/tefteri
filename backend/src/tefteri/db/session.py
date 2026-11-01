"""Async engine and session factory for SQLite and PostgreSQL."""

from collections.abc import AsyncIterator
from contextlib import asynccontextmanager

from sqlalchemy import event
from sqlalchemy.ext.asyncio import (
    AsyncEngine,
    AsyncSession,
    async_sessionmaker,
    create_async_engine,
)
from sqlalchemy.pool import StaticPool


def create_engine(database_url: str) -> AsyncEngine:
    """Create an async engine; the URL decides SQLite (aiosqlite) or PostgreSQL (asyncpg)."""
    if database_url.startswith("sqlite"):
        kwargs: dict[str, object] = {}
        if ":memory:" in database_url or database_url.endswith("///"):
            kwargs = {"poolclass": StaticPool, "connect_args": {"check_same_thread": False}}
        engine = create_async_engine(database_url, **kwargs)

        @event.listens_for(engine.sync_engine, "connect")
        def _fk_on(dbapi_conn, _record):  # type: ignore[no-untyped-def]  # noqa: ANN001, ANN202
            dbapi_conn.execute("PRAGMA foreign_keys=ON")

        return engine
    return create_async_engine(database_url)


def create_session_factory(engine: AsyncEngine) -> async_sessionmaker[AsyncSession]:
    """Create the session factory bound to ``engine``."""
    return async_sessionmaker(engine, expire_on_commit=False)


@asynccontextmanager
async def session_scope(
    factory: async_sessionmaker[AsyncSession],
) -> AsyncIterator[AsyncSession]:
    """Provide a session that commits on success and rolls back on error."""
    async with factory() as session:
        try:
            yield session
            await session.commit()
        except Exception:
            await session.rollback()
            raise
