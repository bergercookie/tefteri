"""The color of a Vikunja project shows on its tasks."""

from datetime import UTC, datetime, timedelta

from httpx import AsyncClient

from tefteri.domain.entities import Container, TaskDraft
from tests.conftest import V1
from tests.fakes.world import FakeWorld

NEW = {"settings": {}, "credentials": {"token": "t"}}


async def _setup(api: AsyncClient, world: FakeWorld) -> None:
    backend = world.tasks["default"]
    backend.containers = [
        Container("red", "Website", color="#d50000"),
        Container("none", "Inbox"),
    ]
    due = datetime.now(UTC).replace(microsecond=0) + timedelta(days=1)
    await backend.create_task(TaskDraft("red", "Fix the form", due_at=due))
    await backend.create_task(TaskDraft("none", "Reply to Sam", due_at=due))
    r = await api.post(
        f"{V1}/connections", json={**NEW, "provider": "vikunja", "display_name": "T"}
    )
    assert r.status_code == 201, r.text


async def test_tasks_carry_the_color_of_their_project(api: AsyncClient, world: FakeWorld) -> None:
    await _setup(api, world)
    tasks = {t["title"]: t for t in (await api.get(f"{V1}/tasks", params={"due": "all"})).json()}
    assert tasks["Fix the form"]["project_color"] == "#d50000"
    assert tasks["Reply to Sam"]["project_color"] is None

    items = {i["title"]: i for i in (await api.get(f"{V1}/calendar")).json()}
    assert items["Fix the form"]["color"] == "#d50000"
    assert items["Reply to Sam"]["color"] is None

    one = (await api.get(f"{V1}/tasks/{tasks['Fix the form']['id']}")).json()
    assert one["project"] == "Website" and one["project_color"] == "#d50000"


async def test_the_views_and_the_weekly_plan_carry_the_color(
    api: AsyncClient, world: FakeWorld
) -> None:
    await _setup(api, world)
    day = datetime.now(UTC).date() + timedelta(days=1)
    week = (await api.get(f"{V1}/views/week/{day}")).json()
    assert {t["title"]: t["project_color"] for t in week["tasks"]} == {
        "Fix the form": "#d50000",
        "Reply to Sam": None,
    }
    daily = (await api.get(f"{V1}/views/day/{day}")).json()
    assert {t["title"]: t["project_color"] for t in daily["tasks"]} == {
        "Fix the form": "#d50000",
        "Reply to Sam": None,
    }
    connection = (await api.get(f"{V1}/connections")).json()[0]["id"]
    listed = (await api.get(f"{V1}/connections/{connection}/containers")).json()
    containers = {c["name"]: c["id"] for c in listed}
    plan = (
        await api.post(f"{V1}/weekly/{day}/projects", json={"container_id": containers["Website"]})
    ).json()["plan"]
    assert plan["projects"][0]["color"] == "#d50000"
