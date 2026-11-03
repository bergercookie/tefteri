"""Sync service: per-connection results, failure isolation, deletion marking."""

from collections.abc import AsyncIterator

import pytest
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from tefteri.db.base import Base
from tefteri.db.models.connection import Connection
from tefteri.db.models.note import Note
from tefteri.db.models.sync import SyncRun
from tefteri.db.models.task import Task
from tefteri.db.models.user import User
from tefteri.db.session import create_engine, create_session_factory
from tefteri.domain.entities import TaskDraft
from tefteri.domain.enums import DefaultContext, SyncState
from tefteri.security.crypto import TokenCipher
from tefteri.services.connections import ConnectionService
from tefteri.services.sync import SyncService
from tests.fakes.world import FakeWorld


@pytest.fixture
async def db() -> AsyncIterator[AsyncSession]:
    engine = create_engine("sqlite+aiosqlite:///:memory:")
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
    async with create_session_factory(engine)() as session:
        yield session
    await engine.dispose()


async def _setup(db: AsyncSession, world: FakeWorld) -> tuple[ConnectionService, SyncService, User]:
    user = User(username="u")
    db.add(user)
    await db.flush()
    connections = ConnectionService(world.registry(), TokenCipher("secret-key-0123456789"))
    for provider, name in (("vikunja", "Tasks"), ("google_calendar", "Cal"), ("trilium", "Notes")):
        await connections.create(
            db,
            user.id,
            provider=provider,
            display_name=name,
            default_context=DefaultContext.LIFE,
            settings={},
            credentials={"token": "t"},
        )
    return connections, SyncService(connections), user


async def test_sync_all_reports_each_connection_and_stores_items(db: AsyncSession) -> None:
    world = FakeWorld()
    await world.seed()
    _, sync, user = await _setup(db, world)
    results = await sync.sync_all(db, user.id)
    assert {r.name: r.outcome for r in results} == {"Tasks": "ok", "Cal": "ok", "Notes": "ok"}
    assert [r.counts["created"] for r in results] == [1, 1, 1]
    assert (await db.execute(select(Task))).scalars().one().title == "Write report"
    assert (await db.execute(select(Note))).scalars().one().body == "steps"
    assert len((await db.execute(select(SyncRun))).scalars().all()) == 3


async def test_one_failing_connection_does_not_block_others(db: AsyncSession) -> None:
    world = FakeWorld()
    await world.seed()
    world.tasks["default"].unavailable = True
    _, sync, user = await _setup(db, world)
    results = {r.name: r for r in await sync.sync_all(db, user.id)}
    assert results["Tasks"].outcome == "error" and results["Tasks"].reason == "unreachable"
    assert results["Cal"].outcome == "ok" and results["Notes"].outcome == "ok"
    conns = {c.display_name: c for c in (await db.execute(select(Connection))).scalars()}
    assert conns["Tasks"].status == "error" and conns["Cal"].status == "ok"


async def test_expired_credentials_need_attention_then_recover(db: AsyncSession) -> None:
    world = FakeWorld()
    world.notes["default"].auth_expired = True
    connections, sync, user = await _setup(db, world)
    notes_conn = next(c for c in await connections.list(db, user.id) if c.display_name == "Notes")
    result = await sync.sync_connection(db, notes_conn)
    assert (result.outcome, result.reason) == ("needs_attention", "auth_expired")
    assert notes_conn.status == "needs_attention" and notes_conn.last_sync_outcome == "auth_expired"
    world.notes["default"].auth_expired = False
    assert (await sync.sync_connection(db, notes_conn)).outcome == "ok"
    assert notes_conn.status == "ok"


async def test_unexpected_adapter_error_is_isolated(db: AsyncSession) -> None:
    world = FakeWorld()

    async def boom(*_a: object, **_k: object) -> None:
        raise RuntimeError("bug in adapter")

    world.calendars["default"].list_containers = boom  # type: ignore[method-assign,assignment]
    _, sync, user = await _setup(db, world)
    results = {r.name: r for r in await sync.sync_all(db, user.id)}
    assert (results["Cal"].outcome, results["Cal"].reason) == ("error", "error")
    assert results["Tasks"].outcome == "ok"


async def test_remote_deletion_is_marked_not_removed_and_resync_is_idempotent(
    db: AsyncSession,
) -> None:
    world = FakeWorld()
    await world.seed()
    _, sync, user = await _setup(db, world)
    await sync.sync_all(db, user.id)
    second = await sync.sync_all(db, user.id)
    assert all(sum(r.counts.values()) == 0 for r in second)

    remote_id = next(iter(world.tasks["default"].tasks))
    await world.tasks["default"].delete_task(remote_id)
    results = {r.name: r for r in await sync.sync_all(db, user.id)}
    assert results["Tasks"].counts["deleted"] == 1
    task = (await db.execute(select(Task))).scalars().one()
    assert task.sync_state == SyncState.DELETED_REMOTELY.value


async def test_remote_change_updates_cache_but_not_rows_in_conflict(db: AsyncSession) -> None:
    world = FakeWorld()
    await world.seed()
    _, sync, user = await _setup(db, world)
    await sync.sync_all(db, user.id)
    remote_id = next(iter(world.tasks["default"].tasks))
    world.tasks["default"].edit_remotely(remote_id, "Renamed remotely")
    await sync.sync_all(db, user.id)
    task = (await db.execute(select(Task))).scalars().one()
    assert task.title == "Renamed remotely"

    task.sync_state = SyncState.CONFLICT.value
    world.tasks["default"].edit_remotely(remote_id, "Changed again")
    await world.tasks["default"].create_task(TaskDraft("p1", "New one"))
    await sync.sync_all(db, user.id)
    tasks = {t.title: t for t in (await db.execute(select(Task))).scalars()}
    assert "Renamed remotely" in tasks and "New one" in tasks  # conflict row untouched
