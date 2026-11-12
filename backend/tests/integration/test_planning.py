"""Plans and the weekly, monthly and annual views after spec 006 (goals are annual only)."""

from collections.abc import Awaitable, Callable

from httpx import AsyncClient

from tests.conftest import V1, connect_all
from tests.integration.annual_helpers import create_goal, freeze, kr

GOAL_YEAR = 2030


async def test_a_task_scheduled_in_a_week_shows_in_the_week_view(api: AsyncClient) -> None:
    ids = await connect_all(api)
    await api.post(f"{V1}/sync")
    created = await api.post(
        f"{V1}/tasks", json={"connection_id": ids["vikunja"], "title": "Buy shoes"}
    )
    assert created.status_code == 201, created.text
    task = created.json()

    sched = await api.put(
        f"{V1}/tasks/{task['id']}/schedule", json={"start": "2026-11-03T09:00:00+00:00"}
    )
    assert sched.status_code == 200

    week = (await api.get(f"{V1}/views/week/2026-11-03")).json()
    assert week["start"] == "2026-11-02" and week["end"] == "2026-11-09"
    assert [t["title"] for t in week["tasks"]] == ["Buy shoes"]
    assert "goals" not in week and week["goal_titles"] == {}


async def test_a_task_linked_to_an_annual_goal_is_listed_and_titled(api: AsyncClient) -> None:
    freeze(api)
    ids = await connect_all(api)
    await api.post(f"{V1}/sync")
    goal = await create_goal(api, "Get fit", kr("Kilometres", year=GOAL_YEAR), year=GOAL_YEAR)
    created = await api.post(
        f"{V1}/tasks",
        json={"connection_id": ids["vikunja"], "title": "Run", "goal_id": goal["id"]},
    )
    assert created.status_code == 201, created.text
    task = created.json()
    assert task["goal_id"] == goal["id"]
    await api.put(f"{V1}/tasks/{task['id']}/schedule", json={"start": "2030-07-01T09:00:00Z"})

    linked = (await api.get(f"{V1}/tasks", params={"goal_id": goal["id"]})).json()
    assert [t["title"] for t in linked] == ["Run"]
    month = (await api.get(f"{V1}/views/month/2030-07-01")).json()
    assert month["goal_titles"] == {goal["id"]: {"title": "Get fit", "annual": True}}


async def test_plans_and_month_and_year_views(api: AsyncClient) -> None:
    plan = await api.post(
        f"{V1}/plans",
        json={"period_type": "year", "period_start": "2026-01-01", "title": "2026 resolutions"},
    )
    assert plan.status_code == 201, plan.text
    assert "goals" not in plan.json()
    plans = (await api.get(f"{V1}/plans")).json()
    assert [p["title"] for p in plans] == ["2026 resolutions"]
    assert (await api.get(f"{V1}/plans/{plan.json()['id']}")).status_code == 200
    bad = await api.post(
        f"{V1}/plans", json={"period_type": "week", "period_start": "2026-11-03", "title": "x"}
    )
    assert bad.status_code == 422

    month = (await api.get(f"{V1}/views/month/2026-11-15")).json()
    assert month["start"] == "2026-11-01" and month["end"] == "2026-12-01"
    assert "goals" not in month
    year = (await api.get(f"{V1}/views/year/2026")).json()
    assert year["entries"] == [] and "goals" not in year


async def test_plans_views_and_tasks_belong_to_their_user(
    api: AsyncClient, make_user: Callable[[str], Awaitable[AsyncClient]]
) -> None:
    unknown = "00000000-0000-0000-0000-000000000000"
    bad_link = await api.patch(f"{V1}/tasks/{unknown}", json={"goal_id": unknown})
    assert bad_link.status_code == 404
    plan = (
        await api.post(
            f"{V1}/plans",
            json={"period_type": "month", "period_start": "2026-11-01", "title": "Mine"},
        )
    ).json()

    other = await make_user("bob")

    assert (await other.get(f"{V1}/plans/{plan['id']}")).status_code == 404
    assert (await other.get(f"{V1}/plans")).json() == []
