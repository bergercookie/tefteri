"""Month and week goals become read-only history (spec 006, US8, FR-022 to FR-027, SC-005)."""

import json
import uuid
from datetime import date

import pytest
from httpx import AsyncClient
from sqlalchemy import select, update

from tefteri.db.models.task import Task
from tests.conftest import V1
from tests.integration.annual_helpers import NOW, YEAR, create_goal, freeze, kr, plan
from tests.integration.conftest import ProjectsEnv, legacy_goal

WEEK = date(2030, 6, 3)  # a Monday
MONTH = date(2030, 6, 1)


async def _tasks(env: ProjectsEnv, count: int = 3) -> list[Task]:
    freeze(env.api)
    await env.connect(tasks={"p1": count})
    async with env.db() as db:
        rows = list((await db.execute(select(Task).order_by(Task.title))).scalars())
        for row in rows:
            row.due_at = NOW
        return rows


async def _link(env: ProjectsEnv, task_id: uuid.UUID, goal_id: uuid.UUID | None) -> None:
    async with env.db() as db:
        await db.execute(update(Task).where(Task.id == task_id).values(goal_id=goal_id))


async def test_history_lists_month_week_and_closed_year_goals_read_only(api: AsyncClient) -> None:
    year_goal = await legacy_goal(api, period_type="year", period_start=date(2025, 1, 1))
    month = await legacy_goal(
        api, period_type="month", period_start=MONTH, title="Run 100 km", parent_id=year_goal
    )
    week = await legacy_goal(api, period_type="week", period_start=WEEK, parent_id=month)
    retired = await legacy_goal(
        api, period_type="year", period_start=date(2025, 1, 1), title="Old", status="retired"
    )
    done = await legacy_goal(
        api, period_type="year", period_start=date(2024, 1, 1), title="Done", status="done"
    )

    rows = (await api.get(f"{V1}/goals/history")).json()

    assert {r["id"] for r in rows} == {str(month), str(week), str(retired), str(done)}
    by_id = {r["id"]: r for r in rows}
    assert by_id[str(month)]["parent_id"] == str(year_goal)
    assert by_id[str(week)]["parent_id"] == str(month)
    assert set(by_id[str(month)]) == {
        "id",
        "parent_id",
        "period_type",
        "period_start",
        "title",
        "description",
        "criteria",
        "status",
        "linked_tasks",
    }
    only_month = (await api.get(f"{V1}/goals/history", params={"period_type": "month"})).json()
    assert [r["id"] for r in only_month] == [str(month)]
    by_start = (await api.get(f"{V1}/goals/history", params={"period_start": str(WEEK)})).json()
    assert [r["id"] for r in by_start] == [str(week)]


async def test_history_counts_the_linked_tasks(env: ProjectsEnv) -> None:
    tasks = await _tasks(env)
    month = await legacy_goal(env.api, period_type="month", period_start=MONTH)
    for task in tasks[:2]:
        await _link(env, task.id, month)

    rows = (await env.api.get(f"{V1}/goals/history")).json()

    assert rows[0]["linked_tasks"] == 2


@pytest.mark.parametrize(
    ("method", "path"),
    [
        ("get", "/goals"),
        ("post", "/goals"),
        ("post", "/goals/bulk"),
        ("patch", "/goals/{id}"),
        ("delete", "/goals/{id}"),
        ("post", "/goals/{id}/breakdown"),
    ],
)
async def test_the_old_goal_routes_are_gone(api: AsyncClient, method: str, path: str) -> None:
    goal = await legacy_goal(api, period_type="month", period_start=MONTH)

    response = await api.request(
        method.upper(),
        V1 + path.format(id=goal),
        json={"title": "x", "period_type": "month", "period_start": str(MONTH)},
    )

    assert response.status_code in (404, 405)
    assert len((await api.get(f"{V1}/goals/history")).json()) == 1


async def test_old_criteria_is_a_metric_suggestion_until_a_key_result_exists(
    env: ProjectsEnv,
) -> None:
    freeze(env.api)
    await env.connect()
    goal_id = await legacy_goal(
        env.api,
        period_type="year",
        period_start=date(YEAR, 1, 1),
        title="Get fit",
        criteria="Run 1000 km",
    )

    goal = (await plan(env.api))["goals"][0]
    assert (goal["id"], goal["criteria_suggestion"], goal["key_results"]) == (
        str(goal_id),
        "Run 1000 km",
        [],
    )
    assert goal["flags"][0]["code"] == "no_key_result"

    added = await env.api.post(f"{V1}/annual/goals/{goal_id}/key-results", json=kr("Kilometres"))
    assert added.status_code == 201, added.text
    goal = (await plan(env.api))["goals"][0]
    assert goal["criteria_suggestion"] is None
    assert [k["metric"] for k in goal["key_results"]] == ["Kilometres"]


async def test_a_done_year_goal_shows_as_legacy_done_in_the_plan(api: AsyncClient) -> None:
    freeze(api)
    await legacy_goal(api, period_type="year", period_start=date(YEAR, 1, 1), status="done")

    goal = (await plan(api))["goals"][0]

    assert goal["legacy_done"] is True


async def test_tasks_keep_their_links_and_views_show_goal_titles(env: ProjectsEnv) -> None:
    tasks = await _tasks(env)
    year_goal = await create_goal(env.api, "Annual goal", kr())
    month = await legacy_goal(env.api, period_type="month", period_start=MONTH, title="Run")
    await _link(env, tasks[0].id, uuid.UUID(year_goal["id"]))
    await _link(env, tasks[1].id, month)

    first = (await env.api.get(f"{V1}/tasks/{tasks[0].id}")).json()
    second = (await env.api.get(f"{V1}/tasks/{tasks[1].id}")).json()
    assert (first["goal_id"], second["goal_id"]) == (year_goal["id"], str(month))

    for kind in ("week", "month"):
        view = (await env.api.get(f"{V1}/views/{kind}/{NOW.date()}")).json()
        assert "goals" not in view
        assert view["goal_titles"] == {
            year_goal["id"]: {"title": "Annual goal", "annual": True},
            str(month): {"title": "Run", "annual": False},
        }
    year_view = (await env.api.get(f"{V1}/views/year/{YEAR}")).json()
    assert "goals" not in year_view

    cleared = await env.api.patch(f"{V1}/tasks/{tasks[1].id}", json={"goal_id": None})
    assert cleared.status_code == 200 and cleared.json()["goal_id"] is None


async def test_only_active_annual_goals_of_this_year_can_be_linked(env: ProjectsEnv) -> None:
    tasks = await _tasks(env)
    current = await create_goal(env.api, "This year", kr())
    later = await create_goal(env.api, "Next year", kr(year=YEAR + 1), year=YEAR + 1)
    retired = await create_goal(env.api, "Retired", kr())
    await env.api.post(f"{V1}/annual/goals/{retired['id']}/retire", json={})
    month = await legacy_goal(env.api, period_type="month", period_start=MONTH)
    await _link(env, tasks[1].id, month)

    for goal_id in (str(month), later["id"], retired["id"], str(uuid.uuid4())):
        response = await env.api.patch(f"{V1}/tasks/{tasks[0].id}", json={"goal_id": goal_id})
        assert response.status_code == 422, goal_id
        assert response.json()["code"] == "goal_not_linkable"
        assert response.json()["detail"] == "Only goals of this year's annual plan can be linked."

    linked = await env.api.patch(f"{V1}/tasks/{tasks[0].id}", json={"goal_id": current["id"]})
    assert linked.status_code == 200 and linked.json()["goal_id"] == current["id"]
    unchanged = await env.api.patch(
        f"{V1}/tasks/{tasks[1].id}", json={"goal_id": str(month), "title": tasks[1].title}
    )
    assert unchanged.status_code == 200 and unchanged.json()["goal_id"] == str(month)

    created = await env.api.post(
        f"{V1}/tasks",
        json={"connection_id": env.connection_id, "title": "New", "goal_id": str(month)},
    )
    assert created.status_code == 422 and created.json()["code"] == "goal_not_linkable"


async def test_the_weekly_flow_and_the_look_back_offer_no_goal(env: ProjectsEnv) -> None:
    await _tasks(env)
    await legacy_goal(env.api, period_type="week", period_start=WEEK, title="Old week goal")
    await legacy_goal(env.api, period_type="month", period_start=MONTH, title="Old month goal")
    await create_goal(env.api, "Annual goal", kr())

    for path in (f"/weekly/{WEEK}", f"/weekly/{WEEK}/candidates", "/weekly/history"):
        response = await env.api.get(V1 + path)
        assert response.status_code == 200, (path, response.text)
        text = json.dumps(response.json())
        assert "Old week goal" not in text and "Old month goal" not in text, path
        assert '"goals"' not in text, path
