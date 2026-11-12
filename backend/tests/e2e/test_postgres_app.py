"""The whole app on PostgreSQL (asyncpg): migrations, sign-in, sync, writes, goals, reviews,
notes, user delete.

Runs only when ``TEFTERI_TEST_POSTGRES_URL`` is set. The CI Postgres job runs it with
``just backend::test-postgres``.
"""

import asyncio
import os
from collections.abc import AsyncIterator, Callable, Iterator
from pathlib import Path

import pytest
from alembic import command
from alembic.config import Config
from httpx import ASGITransport, AsyncClient

from tefteri.config import Settings
from tefteri.domain.entities import Container, TaskDraft
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

    # Review and retrospective (JSON columns, FKs).
    plan = (
        await pg_api.post(
            f"{V1}/plans",
            json={"period_type": "year", "period_start": "2026-01-01", "title": "2026"},
        )
    ).json()
    review = (await pg_api.get(f"{V1}/plans/{plan['id']}/review")).json()
    # A review counts the goals of the period. The task only feeds the progress of its goal.
    assert (review["planned_count"], review["completed_count"]) == (1, 1)
    saved = await pg_api.put(
        f"{V1}/plans/{plan['id']}/review/retrospective", json={"body": "Good year."}
    )
    assert saved.json()["retrospective"]["kind"] == "retrospective"


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


async def test_simultaneous_key_result_adds_respect_the_limit_on_postgres(
    pg_api: AsyncClient,
) -> None:
    year = 2026
    created = await pg_api.post(
        f"{V1}/annual/{year}/goals/bulk",
        json={
            "goals": [
                {
                    "title": "Concurrent annual goal",
                    "key_results": [
                        {
                            "metric": metric,
                            "start_value": 0,
                            "target": 10,
                            "deadline": f"{year}-12-31",
                        }
                        for metric in ("First", "Second")
                    ],
                }
            ]
        },
    )
    assert created.status_code == 201, created.text
    goal_id = created.json()["goals"][0]["id"]

    async def add(metric: str):
        return await pg_api.post(
            f"{V1}/annual/goals/{goal_id}/key-results",
            json={
                "metric": metric,
                "start_value": 0,
                "target": 10,
                "deadline": f"{year}-12-31",
            },
        )

    responses = await asyncio.gather(add("Third A"), add("Third B"))

    assert sorted(response.status_code for response in responses) == [201, 409]
    rejected = next(response for response in responses if response.status_code == 409)
    assert rejected.json()["code"] == "key_result_limit"
    plan = (await pg_api.get(f"{V1}/annual/{year}")).json()
    assert len(plan["goals"][0]["key_results"]) == 3


async def test_weekly_milestones_on_postgres(pg_api: AsyncClient, world: FakeWorld) -> None:
    """Milestone rows, rollover events, the close log (JSON) and the cascades on PostgreSQL."""
    backend = world.tasks["default"]
    backend.containers.extend([Container("p2", "Open source"), Container("p3", "Login flow", "p2")])
    for n in range(3):
        await backend.create_task(TaskDraft("p3", f"Task {n}"))
    await connect_all(pg_api)
    await pg_api.post(f"{V1}/sync")
    tree = (await pg_api.get(f"{V1}/projects/classification")).json()
    by_name = {p["name"]: p["id"] for c in tree["connections"] for p in c["projects"]}
    labelled = await pg_api.put(
        f"{V1}/projects/labels",
        json={"changes": [{"id": by_name["Open source"], "label": "theme"}]},
    )
    assert labelled.status_code == 200, labelled.text
    week, next_week = "2030-03-04", "2030-03-11"
    themes = (await pg_api.get(f"{V1}/weekly/{week}/themes")).json()["themes"]
    parent = next(t["container_id"] for t in themes if t["name"] == "Open source")
    made = await pg_api.post(
        f"{V1}/weekly/{week}/milestones",
        json={"parent_id": parent, "name": "Passkeys", "done_state": "Sign in works"},
    )
    assert made.status_code == 201, made.text
    login = (await pg_api.get(f"{V1}/weekly/{week}/candidates")).json()
    container = next(c["container_id"] for c in login if c["name"] == "Login flow")
    await pg_api.post(f"{V1}/weekly/{week}/projects", json={"container_id": container})
    await pg_api.post(f"{V1}/weekly/{week}/spread")
    committed = await pg_api.post(f"{V1}/weekly/{week}/commit")
    assert committed.status_code == 200, committed.text
    entries = {p["name"]: p for p in committed.json()["plan"]["projects"]}

    # Close one milestone: the log is a JSON column that grows with each moved task.
    closed = await pg_api.post(
        f"{V1}/milestones/{entries['Login flow']['milestone_id']}/close", json={"confirm": True}
    )
    assert closed.status_code == 200, closed.text
    assert closed.json()["moved"] == 3
    reopened = await pg_api.post(f"{V1}/milestones/{entries['Login flow']['milestone_id']}/reopen")
    assert reopened.json()["moved_back"] == 3

    back = (await pg_api.get(f"{V1}/weekly/{next_week}")).json()["look_back"]
    ids = {p["name"]: p["id"] for p in back["projects"]}
    reviewed = await pg_api.post(
        f"{V1}/weekly/reviews/{back['plan_id']}",
        json={
            "projects": [
                {"plan_project_id": ids["Passkeys"], "decision": "recommit", "expected": True},
                {"plan_project_id": ids["Login flow"], "decision": "park"},
            ]
        },
    )
    assert reviewed.status_code == 200, reviewed.text
    plan = (await pg_api.get(f"{V1}/weekly/{next_week}")).json()["plan"]
    assert [(p["name"], p["rollover_count"]) for p in plan["projects"]] == [("Passkeys", 1)]
    found = {c["name"]: c for c in (await pg_api.get(f"{V1}/weekly/{next_week}/candidates")).json()}
    assert found["Login flow"]["state"] == "parked"
    history = (await pg_api.get(f"{V1}/weekly/history")).json()
    assert {p["decision"] for p in history["entries"][0]["projects"]} == {"recommit", "park"}

    # Deleting the user removes the milestone rows through the cascades.
    sam = await pg_api.post(f"{V1}/users", json={"username": "sam", "password": "long enough pw"})
    assert (await pg_api.delete(f"{V1}/users/{sam.json()['id']}")).status_code == 204


async def test_work_categories_and_statistics_on_postgres(
    pg_api: AsyncClient, world: FakeWorld
) -> None:
    """Recording, the grouped counts, both paging orders (ties) and the cascade on PostgreSQL."""
    backend = world.tasks["default"]
    backend.containers.extend([Container("p2", "Zebra"), Container("p3", "apple")])
    for project in ("p1", "p2", "p3"):
        for n in range(3):
            await backend.create_task(TaskDraft(project, f"{project} task {n}"))
    await connect_all(pg_api)
    await pg_api.post(f"{V1}/sync")
    tasks = (await pg_api.get(f"{V1}/tasks", params={"due": "all"})).json()
    for task in tasks:  # every completion has the same time: the order must still be stable
        assert (await pg_api.post(f"{V1}/tasks/{task['id']}/complete")).status_code == 200
    params = {"period": "week", "day": "2030-03-06"}
    for period in ("week", "month", "year"):
        body = (await pg_api.get(f"{V1}/statistics", params=params | {"period": period})).json()
        assert body["counts"] == {"goal_aligned": 0, "maintenance": 0, "off_plan": 9}
        assert body["unsorted"] == 9 and body["total"] == 9
    for order in ("newest", "project"):
        seen: list[str] = []
        cursor = None
        while True:
            page = (
                await pg_api.get(
                    f"{V1}/statistics/tasks",
                    params=params
                    | {"order": order, "limit": 2}
                    | ({"cursor": cursor} if cursor else {}),
                )
            ).json()
            seen += [t["id"] for t in page["items"]]
            cursor = page["next_cursor"]
            if cursor is None:
                break
        assert len(seen) == len(set(seen)) == 9, order
    first = (
        await pg_api.get(f"{V1}/statistics/tasks", params=params | {"order": "project", "limit": 1})
    ).json()["items"][0]
    assert first["project"]["name"] == "apple"  # case-folded: apple before Inbox and Zebra
    sam = await pg_api.post(f"{V1}/users", json={"username": "sam", "password": "long enough pw"})
    assert (await pg_api.delete(f"{V1}/users/{sam.json()['id']}")).status_code == 204
