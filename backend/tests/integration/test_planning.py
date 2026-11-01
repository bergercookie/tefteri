"""Goals, plans, breakdown, deletion and the weekly, monthly and annual views."""

from httpx import AsyncClient

from tests.conftest import V1, connect_all
from tests.fakes.world import FakeWorld


async def _goal(api: AsyncClient, **over: str | None) -> dict[str, str]:
    body: dict[str, str | None] = {
        "period_type": "year",
        "period_start": "2026-01-01",
        "title": "Get fit",
    }
    body.update(over)
    r = await api.post(f"{V1}/goals", json=body)
    assert r.status_code == 201, r.text
    result: dict[str, str] = r.json()
    return result


async def test_hierarchy_rules(api: AsyncClient) -> None:
    year = await _goal(api)
    month = await _goal(
        api,
        parent_id=year["id"],
        period_type="month",
        period_start="2026-11-01",
        title="Run 100 km",
    )
    await _goal(
        api, parent_id=month["id"], period_type="week", period_start="2026-11-02", title="Run 25 km"
    )
    misaligned = await api.post(
        f"{V1}/goals", json={"period_type": "week", "period_start": "2026-11-03", "title": "x"}
    )
    assert misaligned.status_code == 422
    outside = await api.post(
        f"{V1}/goals",
        json={
            "parent_id": year["id"],
            "period_type": "month",
            "period_start": "2027-01-01",
            "title": "x",
        },
    )
    assert outside.status_code == 422 and outside.json()["code"] == "invalid"
    same_level = await api.post(
        f"{V1}/goals",
        json={
            "parent_id": month["id"],
            "period_type": "month",
            "period_start": "2026-11-01",
            "title": "x",
        },
    )
    assert same_level.status_code == 422


async def test_breakdown_progress_roll_up_and_scheduling(
    api: AsyncClient, world: FakeWorld
) -> None:
    ids = await connect_all(api)
    await api.post(f"{V1}/sync")
    year = await _goal(api)
    result = await api.post(
        f"{V1}/goals/{year['id']}/breakdown",
        json={
            "goals": [
                {"title": "Nov", "period_type": "month", "period_start": "2026-11-01"},
                {"title": "Dec", "period_type": "month", "period_start": "2026-12-01"},
            ],
            "tasks": [{"connection_id": ids["vikunja"], "title": "Buy shoes"}],
        },
    )
    assert result.status_code == 201, result.text
    body = result.json()
    assert [g["title"] for g in body["goals"]] == ["Nov", "Dec"]
    task = body["tasks"][0]
    assert task["goal_id"] == year["id"]
    assert [t.title for t in world.tasks["default"].tasks.values()] == ["Buy shoes"]

    def progress() -> float:
        return float(year_goal["progress"])

    year_goal = (await api.get(f"{V1}/goals", params={"period_type": "year"})).json()[0]
    assert progress() == 0.0
    await api.post(f"{V1}/tasks/{task['id']}/complete")
    year_goal = (await api.get(f"{V1}/goals", params={"period_type": "year"})).json()[0]
    assert abs(progress() - 1 / 3) < 0.01  # two empty month goals and one done task

    # schedule the goal-derived task from a planning view
    sched = await api.put(
        f"{V1}/tasks/{task['id']}/schedule", json={"start": "2026-11-03T09:00:00+00:00"}
    )
    assert sched.status_code == 200
    week = (await api.get(f"{V1}/views/week/2026-11-03")).json()
    assert week["start"] == "2026-11-02" and week["end"] == "2026-11-09"
    assert [t["title"] for t in week["tasks"]] == ["Buy shoes"]
    linked = (await api.get(f"{V1}/tasks", params={"goal_id": year["id"]})).json()
    assert [t["title"] for t in linked] == ["Buy shoes"]


async def test_delete_keeps_or_deletes_linked_tasks_and_children(
    api: AsyncClient, world: FakeWorld
) -> None:
    ids = await connect_all(api)
    await api.post(f"{V1}/sync")

    async def make() -> tuple[dict[str, str], dict[str, str]]:
        year = await _goal(api)
        out = await api.post(
            f"{V1}/goals/{year['id']}/breakdown",
            json={
                "goals": [{"title": "Nov", "period_type": "month", "period_start": "2026-11-01"}],
                "tasks": [{"connection_id": ids["vikunja"], "title": f"T{year['id']}"[:8]}],
            },
        )
        return year, dict(out.json()["tasks"][0])

    year, task = await make()
    assert (
        await api.delete(f"{V1}/goals/{year['id']}", params={"linked_tasks": "keep"})
    ).status_code == 204
    kept = (await api.get(f"{V1}/tasks/{task['id']}")).json()
    assert kept["goal_id"] is None  # task survives, unlinked
    assert (
        await api.get(f"{V1}/goals") and (await api.get(f"{V1}/goals")).json() == []
    )  # children gone
    assert len(world.tasks["default"].tasks) == 1

    year2, task2 = await make()
    await api.delete(f"{V1}/goals/{year2['id']}", params={"linked_tasks": "delete"})
    assert (await api.get(f"{V1}/tasks/{task2['id']}")).status_code == 404
    assert len(world.tasks["default"].tasks) == 1  # deleted in the app too
    missing_option = await api.delete(f"{V1}/goals/{year2['id']}")
    assert missing_option.status_code == 422


async def test_delete_with_unreachable_task_app_changes_nothing(
    api: AsyncClient, world: FakeWorld
) -> None:
    ids = await connect_all(api)
    await api.post(f"{V1}/sync")
    year = await _goal(api)
    await api.post(
        f"{V1}/goals/{year['id']}/breakdown",
        json={"tasks": [{"connection_id": ids["vikunja"], "title": "T"}]},
    )
    world.tasks["default"].unavailable = True
    r = await api.delete(f"{V1}/goals/{year['id']}", params={"linked_tasks": "delete"})
    assert r.status_code == 502
    world.tasks["default"].unavailable = False
    assert len((await api.get(f"{V1}/goals")).json()) == 1


async def test_context_filter_applies_to_goals_and_views(api: AsyncClient) -> None:
    await _goal(api, title="Life goal", context="life")
    await _goal(api, title="Work goal", context="work")
    for kind, path in (("year", "views/year/2026"), ("month", None), ("week", None)):
        if path is None:
            continue
        work = (await api.get(f"{V1}/{path}", params={"context": "work"})).json()
        life = (await api.get(f"{V1}/{path}", params={"context": "life"})).json()
        assert [g["title"] for g in work["goals"]] == ["Work goal"], kind
        assert [g["title"] for g in life["goals"]] == ["Life goal"]
    listed = (await api.get(f"{V1}/goals", params={"context": "work"})).json()
    assert [g["title"] for g in listed] == ["Work goal"]


async def test_update_status_plans_and_month_year_views(api: AsyncClient) -> None:
    goal = await _goal(api)
    done = await api.patch(f"{V1}/goals/{goal['id']}", json={"status": "done"})
    assert done.json()["status"] == "done" and done.json()["progress"] == 1.0

    plan = await api.post(
        f"{V1}/plans",
        json={"period_type": "year", "period_start": "2026-01-01", "title": "2026 resolutions"},
    )
    assert plan.status_code == 201 and [g["title"] for g in plan.json()["goals"]] == ["Get fit"]
    plans = (await api.get(f"{V1}/plans")).json()
    assert [p["title"] for p in plans] == ["2026 resolutions"]
    assert (await api.get(f"{V1}/plans/{plan.json()['id']}")).status_code == 200
    bad = await api.post(
        f"{V1}/plans", json={"period_type": "week", "period_start": "2026-11-03", "title": "x"}
    )
    assert bad.status_code == 422

    month = (await api.get(f"{V1}/views/month/2026-11-15")).json()
    assert month["start"] == "2026-11-01" and month["end"] == "2026-12-01"
    year = (await api.get(f"{V1}/views/year/2026")).json()
    assert year["entries"] == [] and [g["title"] for g in year["goals"]] == ["Get fit"]


async def test_goals_belong_to_their_user(api: AsyncClient) -> None:
    unknown = "00000000-0000-0000-0000-000000000000"
    assert (await api.patch(f"{V1}/goals/{unknown}", json={"title": "x"})).status_code == 404
    bad_link = await api.patch(f"{V1}/tasks/{unknown}", json={"goal_id": unknown})
    assert bad_link.status_code == 404
