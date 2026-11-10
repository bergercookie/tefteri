"""The regular sync of all connections."""

import asyncio
import uuid
from collections.abc import AsyncIterator, Callable
from datetime import UTC, datetime, timedelta

import httpx
import pytest
from httpx import AsyncClient
from sqlalchemy import select

from tefteri.config import Settings
from tefteri.db.models.connection import Connection
from tefteri.db.models.sync import SyncRun
from tefteri.db.session import session_scope
from tefteri.domain.entities import TaskDraft
from tefteri.domain.enums import ConnectionStatus
from tefteri.main import create_app
from tefteri.services.background_sync import SYNC_RUN_KEEP, BackgroundSync
from tests.conftest import V1
from tests.fakes.world import FakeWorld

NEW = {"settings": {}, "credentials": {"token": "t"}}


@pytest.fixture
async def app(make_settings: Callable[..., Settings], world: FakeWorld) -> AsyncIterator[object]:
    application = create_app(make_settings(), registry=world.registry())
    async with application.router.lifespan_context(application):
        yield application


def _runner(app: object, **kwargs: object) -> BackgroundSync:
    state = app.state  # type: ignore[attr-defined]
    return BackgroundSync(
        state.session_factory,
        state.sync_service,
        timedelta(hours=1),
        **kwargs,  # type: ignore[arg-type]
    )


async def _client(app: object) -> AsyncClient:
    client = AsyncClient(transport=httpx.ASGITransport(app=app), base_url="http://test")  # type: ignore[arg-type]
    login = await client.post(
        f"{V1}/auth/login", json={"username": "admin", "password": "correct horse battery"}
    )
    client.headers["Authorization"] = f"Bearer {login.json()['token']}"
    return client


async def _runs(app: object) -> list[SyncRun]:
    async with session_scope(app.state.session_factory) as db:  # type: ignore[attr-defined]
        return list((await db.execute(select(SyncRun))).scalars())


async def test_a_pass_syncs_the_connections_of_every_user(app: object, world: FakeWorld) -> None:
    await world.seed()
    client = await _client(app)
    await client.post(f"{V1}/connections", json={**NEW, "provider": "vikunja", "display_name": "T"})
    await client.post(f"{V1}/connections", json={**NEW, "provider": "trilium", "display_name": "N"})
    before = len(await _runs(app))  # one run for each, from the sync at creation

    assert await _runner(app).run_once() == 2

    assert len(await _runs(app)) == before + 2
    # The data of the apps is in the cache without anyone pressing Sync.
    assert [t["title"] for t in (await client.get(f"{V1}/tasks")).json()] == ["Write report"]
    await client.aclose()


async def test_a_pass_brings_in_what_changed_in_the_app(app: object, world: FakeWorld) -> None:
    await world.seed()
    client = await _client(app)
    await client.post(f"{V1}/connections", json={**NEW, "provider": "vikunja", "display_name": "T"})
    assert len((await client.get(f"{V1}/tasks")).json()) == 1
    # A task is added in the task app, not in tefteri.
    await world.tasks["default"].create_task(TaskDraft("p1", "Added in Vikunja"))
    await _runner(app).run_once()
    titles = {t["title"] for t in (await client.get(f"{V1}/tasks")).json()}
    assert titles == {"Write report", "Added in Vikunja"}
    await client.aclose()


async def test_a_connection_that_needs_attention_is_left_out(app: object, world: FakeWorld) -> None:
    await world.seed()
    client = await _client(app)
    broken = (
        await client.post(
            f"{V1}/connections", json={**NEW, "provider": "vikunja", "display_name": "Broken"}
        )
    ).json()["id"]
    await client.post(f"{V1}/connections", json={**NEW, "provider": "trilium", "display_name": "N"})
    async with session_scope(app.state.session_factory) as db:  # type: ignore[attr-defined]
        row = await db.get(Connection, uuid.UUID(broken))
        assert row is not None
        row.status = ConnectionStatus.NEEDS_ATTENTION.value
    # Only the healthy one is tried. A manual sync would still try the other.
    assert await _runner(app).run_once() == 1
    await client.aclose()


async def test_one_failing_connection_does_not_stop_the_others(
    app: object, world: FakeWorld
) -> None:
    await world.seed()
    client = await _client(app)
    await client.post(f"{V1}/connections", json={**NEW, "provider": "vikunja", "display_name": "T"})
    await client.post(f"{V1}/connections", json={**NEW, "provider": "trilium", "display_name": "N"})
    world.tasks["default"].unavailable = True  # the task app is down at the next pass
    assert await _runner(app).run_once() == 2
    status = {s["name"]: s["status"] for s in (await client.get(f"{V1}/sync/status")).json()}
    assert status == {"T": "error", "N": "ok"}
    await client.aclose()


async def test_the_loop_waits_then_syncs_at_each_interval(app: object) -> None:
    waits: list[float] = []
    passes = 0

    async def fake_sleep(seconds: float) -> None:
        waits.append(seconds)
        if len(waits) == 4:
            raise asyncio.CancelledError  # stop the loop after three passes

    runner = _runner(app, first_run_after=timedelta(seconds=30), sleep=fake_sleep)

    async def count_pass() -> int:
        nonlocal passes
        passes += 1
        if passes == 2:
            raise RuntimeError("a bad pass")  # the loop goes on after it
        return 0

    runner.run_once = count_pass  # type: ignore[method-assign]
    with pytest.raises(asyncio.CancelledError):
        await runner.run_forever()
    assert waits == [30, 3600, 3600, 3600]
    assert passes == 3


async def test_old_records_of_syncs_are_forgotten(app: object, world: FakeWorld) -> None:
    await world.seed()
    client = await _client(app)
    await client.post(f"{V1}/connections", json={**NEW, "provider": "vikunja", "display_name": "T"})
    async with session_scope(app.state.session_factory) as db:  # type: ignore[attr-defined]
        old = (await db.execute(select(SyncRun))).scalars().first()
        assert old is not None
        old.started_at = datetime.now(UTC) - SYNC_RUN_KEEP - timedelta(days=1)
    await _runner(app).run_once()
    started = [r.started_at for r in await _runs(app)]
    assert started and all(
        s.replace(tzinfo=UTC) > datetime.now(UTC) - SYNC_RUN_KEEP for s in started
    )
    await client.aclose()


async def test_two_syncs_of_one_connection_never_overlap(app: object, world: FakeWorld) -> None:
    await world.seed()
    client = await _client(app)
    created = (
        await client.post(
            f"{V1}/connections", json={**NEW, "provider": "vikunja", "display_name": "T"}
        )
    ).json()
    backend = world.tasks["default"]
    running = 0
    most = 0
    original = backend.list_containers

    async def slow() -> list:  # type: ignore[type-arg]
        nonlocal running, most
        running += 1
        most = max(most, running)
        await asyncio.sleep(0.05)
        try:
            return await original()
        finally:
            running -= 1

    backend.list_containers = slow  # type: ignore[method-assign]
    await asyncio.gather(
        client.post(f"{V1}/connections/{created['id']}/sync"),
        client.post(f"{V1}/connections/{created['id']}/sync"),
        _runner(app).run_once(),
    )
    assert most == 1
    await client.aclose()


async def test_the_server_starts_and_stops_the_loop(
    make_settings: Callable[..., Settings], world: FakeWorld
) -> None:
    app = create_app(make_settings(sync_interval_minutes=1), registry=world.registry())
    async with app.router.lifespan_context(app):
        pass  # the loop is waiting for its first pass; leaving the app cancels it
    assert not [t for t in asyncio.all_tasks() if t.get_name() == "background-sync"]


def test_the_interval_can_be_turned_off_but_not_made_negative(
    make_settings: Callable[..., Settings],
) -> None:
    assert make_settings(sync_interval_minutes=0).sync_interval_minutes == 0
    assert Settings.model_fields["sync_interval_minutes"].default == 60
    with pytest.raises(ValueError):  # noqa: PT011
        make_settings(sync_interval_minutes=-5)
