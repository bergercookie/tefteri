"""The whole app on PostgreSQL (asyncpg): migrations, sign-in, sync, writes, goals, reviews,
notes, user delete.

Runs only when ``TEFTERI_TEST_POSTGRES_URL`` is set. The CI Postgres job runs it with
``just backend::test-postgres``.
"""

import os
from collections.abc import AsyncIterator, Callable, Iterator
from pathlib import Path

import pytest
from alembic import command
from alembic.config import Config
from httpx import ASGITransport, AsyncClient

from tefteri.config import Settings
from tefteri.main import create_app
from tests.conftest import ADMIN_PASSWORD, V1, connect_all
from tests.fakes.world import FakeWorld

URL = os.environ.get("TEFTERI_TEST_POSTGRES_URL")

pytestmark = [
    pytest.mark.postgres,
    pytest.mark.skipif(URL is None, reason="TEFTERI_TEST_POSTGRES_URL is not set"),
]


def _alembic() -> Config:
    root = Path(__file__).parents[2]
    config = Config(str(root / "alembic.ini"))
    config.set_main_option("script_location", str(root / "migrations"))
    return config


@pytest.fixture
def migrated(monkeypatch: pytest.MonkeyPatch) -> Iterator[None]:
    """Build the schema with the real migrations and remove it afterwards."""
    assert URL is not None
    monkeypatch.setenv("TEFTERI_DATABASE_URL", URL)
    command.downgrade(_alembic(), "base")
    command.upgrade(_alembic(), "head")
    yield
    command.downgrade(_alembic(), "base")


@pytest.fixture
async def pg_api(
    migrated: None, make_settings: Callable[..., Settings], world: FakeWorld
) -> AsyncIterator[AsyncClient]:
    assert URL is not None
    app = create_app(
        make_settings(database_url=URL, create_schema=False), registry=world.registry()
    )
    async with (
        app.router.lifespan_context(app),
        AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as c,
    ):
        r = await c.post(f"{V1}/auth/login", json={"username": "admin", "password": ADMIN_PASSWORD})
        c.headers["Authorization"] = f"Bearer {r.json()['token']}"
        yield c


async def test_main_flow_on_postgres(pg_api: AsyncClient, world: FakeWorld) -> None:
    await world.seed()
    ids = await connect_all(pg_api)
    results = (await pg_api.post(f"{V1}/sync")).json()
    assert all(r["outcome"] == "ok" for r in results)

    task = (
        await pg_api.post(
            f"{V1}/tasks", json={"connection_id": ids["vikunja"], "title": "On Postgres"}
        )
    ).json()
    await pg_api.put(
        f"{V1}/tasks/{task['id']}/schedule", json={"start": "2026-11-02T09:00:00+00:00"}
    )
    await pg_api.post(f"{V1}/tasks/{task['id']}/complete")
    day = (await pg_api.get(f"{V1}/views/day/2026-11-02")).json()
    assert {e["title"] for e in day["entries"]} == {"Standup"}
    assert [t["status"] for t in day["tasks"]] == ["done"]

    goal = (
        await pg_api.post(
            f"{V1}/goals", json={"period_type": "year", "period_start": "2026-01-01", "title": "G"}
        )
    ).json()
    await pg_api.patch(f"{V1}/tasks/{task['id']}", json={"goal_id": goal["id"]})
    goals = (await pg_api.get(f"{V1}/goals")).json()
    assert goals[0]["progress"] == 1.0

    # Review, retrospective and a process note linked to the task (JSON columns, FKs).
    plan = (
        await pg_api.post(
            f"{V1}/plans",
            json={"period_type": "year", "period_start": "2026-01-01", "title": "2026"},
        )
    ).json()
    review = (await pg_api.get(f"{V1}/plans/{plan['id']}/review")).json()
    assert (review["planned_count"], review["completed_count"]) == (2, 2)
    saved = await pg_api.put(
        f"{V1}/plans/{plan['id']}/review/retrospective", json={"body": "Good year."}
    )
    assert saved.json()["retrospective"]["kind"] == "retrospective"
    note = (
        await pg_api.post(
            f"{V1}/notes", json={"title": "Steps", "kind": "process", "task_ids": [task["id"]]}
        )
    ).json()
    assert note["task_ids"] == [task["id"]]
    assert (await pg_api.delete(f"{V1}/notes/{note['id']}")).status_code == 204


async def test_conflict_and_cascades_on_postgres(pg_api: AsyncClient, world: FakeWorld) -> None:
    ids = await connect_all(pg_api)
    await pg_api.post(f"{V1}/sync")
    task = (
        await pg_api.post(f"{V1}/tasks", json={"connection_id": ids["vikunja"], "title": "A"})
    ).json()
    world.tasks["default"].edit_remotely(next(iter(world.tasks["default"].tasks)), "B")
    assert (await pg_api.patch(f"{V1}/tasks/{task['id']}", json={"title": "C"})).status_code == 409
    conflict = (await pg_api.get(f"{V1}/conflicts")).json()[0]
    await pg_api.post(
        f"{V1}/conflicts/{conflict['id']}/resolve", json={"resolution": "keep_remote"}
    )
    assert (await pg_api.get(f"{V1}/tasks/{task['id']}")).json()["title"] == "B"

    # deleting a user removes their rows through the database cascades
    sam = await pg_api.post(f"{V1}/users", json={"username": "sam", "password": "long enough pw"})
    assert (await pg_api.delete(f"{V1}/users/{sam.json()['id']}")).status_code == 204
    assert [u["username"] for u in (await pg_api.get(f"{V1}/users")).json()] == ["admin"]
