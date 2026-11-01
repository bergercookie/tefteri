"""Alembic environment (async; works on SQLite and PostgreSQL)."""

import asyncio
import os

from alembic import context
from sqlalchemy import pool
from sqlalchemy.engine import Connection, Engine
from sqlalchemy.ext.asyncio import create_async_engine

import tefteri.db.models  # noqa: F401
from tefteri.db.base import Base

target_metadata = Base.metadata


def _url() -> str:
    return os.environ.get("TEFTERI_DATABASE_URL") or context.config.get_main_option(
        "sqlalchemy.url", "sqlite+aiosqlite:///./tefteri.db"
    )


def _run(connection: Connection) -> None:
    context.configure(connection=connection, target_metadata=target_metadata, render_as_batch=True)
    with context.begin_transaction():
        context.run_migrations()


async def _run_async() -> None:
    engine = create_async_engine(_url(), poolclass=pool.NullPool)
    async with engine.connect() as connection:
        await connection.run_sync(_run)
    await engine.dispose()


if context.is_offline_mode():
    context.configure(url=_url(), target_metadata=target_metadata, literal_binds=True)
    with context.begin_transaction():
        context.run_migrations()
elif (connection := context.config.attributes.get("connection")) is not None:
    # A caller (for example pytest-alembic) supplied a synchronous engine or connection.
    if isinstance(connection, Engine):
        with connection.begin() as conn:
            _run(conn)
    else:
        _run(connection)
else:
    asyncio.run(_run_async())
