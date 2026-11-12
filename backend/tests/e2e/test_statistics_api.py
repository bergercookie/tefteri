"""The statistics routes over HTTP (spec 005, M4)."""

from collections.abc import Awaitable, Callable
from datetime import UTC, datetime, timedelta
from typing import Any

import pytest
from httpx import AsyncClient

from tefteri.domain.enums import CategoryReason, WorkCategory
from tests.conftest import V1
from tests.fakes.world import FakeWorld
from tests.integration.conftest import ProjectsEnv
from tests.integration.stats_helpers import NEXT, WEEK, Stats, at

MakeUser = Callable[..., Awaitable[AsyncClient]]
COUNT_KEYS = {"goal_aligned", "maintenance", "off_plan"}


@pytest.fixture
def env(api: AsyncClient, world: FakeWorld) -> ProjectsEnv:
    return ProjectsEnv(api, world)


async def _every_category(s: Stats) -> None:
    """One completed task for every reason code, and so for every category."""
    await s.standard()
    await s.weekly.label(Dishes="theme")  # a theme inside a routine: inside_routine
    await s.add("p3", "Seed")
    await s.weekly.commit(WEEK, "Login flow")
    await s.done("p3", "committed_milestone", at(4))
    await s.done("p5", "maintenance_label", at(4))
    await s.done("p6", "inside_routine", at(4))
    await s.done("p4", "milestone_not_committed", at(4))  # Docs: a milestone, not committed
    await s.done("p2", "theme", at(4))
    await s.done("p9", "unclassified", at(4))
    await s.done("p7", "ignored", at(4))
    await s.done("p8", "ignored_ancestor", at(4))
    # The task with no project: record it directly, the sync would mark it deleted.
    from sqlalchemy import select

    from tefteri.db.models.connection import Connection
    from tefteri.db.models.task import Task

    await s.sync()
    async with s.env.db() as db:
        connection = (
            await db.execute(select(Connection).where(Connection.kind == "tasks"))
        ).scalar_one()
        db.add(
            Task(
                user_id=await s.env.user_id(),
                connection_id=connection.id,
                container_id=None,
                remote_id="loose",
                title="no_project",
                status="done",
                completed_at=at(4),
                remote_version="v1",
            )
        )
        await db.flush()
        await s.env.app.state.category_recorder.record_new(db, await s.env.user_id(), {})


@pytest.mark.parametrize("period", ["week", "month", "year"])
async def test_the_summary_has_the_shape_of_the_contract(env: ProjectsEnv, period: str) -> None:
    s = Stats(env)
    await _every_category(s)
    body = await s.stats(period, WEEK)
    assert set(body) == {
        "period",
        "start",
        "end",
        "available",
        "unavailable_reason",
        "counts",
        "total",
        "percentages",
        "hidden",
        "unsorted",
        "part_kind",
        "parts",
        "empty",
        "sync",
        "progress",
    }
    assert body["period"] == period and body["available"] is True
    assert set(body["counts"]) == COUNT_KEYS == set(body["percentages"])
    assert body["total"] == sum(body["counts"].values()) == 7
    assert body["hidden"] == 2 and body["unsorted"] == 2
    assert sum(body["percentages"].values()) == 100
    parts = body["parts"]
    assert len(parts) == {"week": 7, "month": 31, "year": 12}[period]
    assert body["part_kind"] == ("month" if period == "year" else "day")
    for key in COUNT_KEYS:
        assert sum(p["counts"][key] for p in parts) == body["counts"][key]
    assert sum(p["hidden"] for p in parts) == body["hidden"]
    assert set(parts[0]) == {"start", "end", "counts", "hidden"}
    assert body["progress"] is not None if period == "week" else body["progress"] is None


async def test_the_day_defaults_to_today_in_the_time_zone_of_the_user(env: ProjectsEnv) -> None:
    s = Stats(env)
    await s.standard()
    me = (await env.api.get(f"{V1}/auth/me")).json()
    await env.api.patch(f"{V1}/users/{me['id']}", json={"timezone": "Pacific/Auckland"})
    # 23:30 UTC on Sunday 10 March is already Monday 11 March (12:30) in Auckland.
    env.app.state.clock = lambda: datetime(2030, 3, 10, 23, 30, tzinfo=UTC)
    body = (await env.api.get(f"{V1}/statistics", params={"period": "week"})).json()
    assert body["start"] == str(NEXT)
    again = (await env.api.get(f"{V1}/statistics")).json()  # period defaults to the week
    assert again["period"] == "week"
    assert (await env.api.get(f"{V1}/statistics", params={"period": "month"})).json()[
        "start"
    ] == "2030-03-01"


@pytest.mark.parametrize(
    "params",
    [
        {"period": "decade"},
        {"period": ""},
        {"day": "not a date"},
    ],
)
async def test_a_bad_request_is_422_invalid(api: AsyncClient, params: dict[str, str]) -> None:
    r = await api.get(f"{V1}/statistics", params=params)
    assert r.status_code == 422 and r.json()["code"] == "invalid"
    r = await api.get(f"{V1}/statistics/tasks", params=params)
    assert r.status_code == 422 and r.json()["code"] == "invalid"


@pytest.mark.parametrize(
    "params",
    [{"limit": 0}, {"limit": 201}, {"limit": "x"}, {"category": "other"}, {"order": "oldest"}],
)
async def test_a_bad_list_request_is_422_invalid(api: AsyncClient, params: dict[str, Any]) -> None:
    r = await api.get(f"{V1}/statistics/tasks", params=params)
    assert r.status_code == 422 and r.json()["code"] == "invalid", params


async def test_250_tasks_are_reached_over_http_page_by_page(env: ProjectsEnv) -> None:
    s = Stats(env)
    await s.standard()
    s.bulk("p9", 250, "Http", at(5), step=timedelta(minutes=1))
    await s.sync()
    seen: list[str] = []
    cursor = None
    pages = 0
    while True:
        params: dict[str, Any] = {"period": "week", "day": str(WEEK), "limit": 100}
        if cursor:
            params["cursor"] = cursor
        body = (await env.api.get(f"{V1}/statistics/tasks", params=params)).json()
        seen += [t["id"] for t in body["items"]]
        pages += 1
        assert body["total"] == 250
        cursor = body["next_cursor"]
        if cursor is None:
            break
    assert pages == 3 and len(set(seen)) == 250
    assert (body["category"], body["order"]) == (None, "newest")


async def test_the_hidden_category_lists_the_ignored_tasks(env: ProjectsEnv) -> None:
    s = Stats(env)
    await s.standard()
    await s.done("p7", "Ignored one", at(5))
    await s.done("p9", "Counted one", at(5))
    await s.sync()
    body = (
        await env.api.get(
            f"{V1}/statistics/tasks",
            params={"period": "week", "day": str(WEEK), "category": "hidden"},
        )
    ).json()
    assert [t["title"] for t in body["items"]] == ["Ignored one"] and body["category"] == "hidden"


async def test_the_weekly_state_has_no_done_outside_plan(env: ProjectsEnv) -> None:
    s = Stats(env)
    await s.standard()
    await s.done("p9", "Outside", at(5))
    await s.sync()
    assert "done_outside_plan" not in await s.weekly.state(WEEK)
    assert "ExtraDoneOut" not in (await env.api.get("/openapi.json")).text


async def test_a_task_of_every_category_and_reason_is_served_without_an_error(
    env: ProjectsEnv,
) -> None:
    s = Stats(env)
    await _every_category(s)
    reasons: set[str] = set()
    for category in WorkCategory:
        items = await s.all_tasks(period="week", day=str(WEEK), category=category.value)
        assert items, category
        reasons |= {t["reason"] for t in items}
        assert {t["category"] for t in items} == {category.value}
    assert reasons == {r.value for r in CategoryReason}  # every code went through the real route
    for period in ("week", "month", "year"):
        for order in ("newest", "project"):
            for category in (None, *WorkCategory):
                params: dict[str, Any] = {"period": period, "day": str(WEEK), "order": order}
                if category:
                    params["category"] = category.value
                r = await env.api.get(f"{V1}/statistics/tasks", params=params)
                assert r.status_code == 200, (period, order, category, r.text)
    body = await s.stats("week", WEEK)
    assert set(body["counts"]) == COUNT_KEYS


async def test_another_user_sees_no_task_and_no_count(
    env: ProjectsEnv, make_user: MakeUser
) -> None:
    s = Stats(env)
    await s.standard()
    await s.done("p9", "Mine", at(5))
    await s.done("p7", "Mine hidden", at(5))
    await s.sync()
    other = await make_user("someone")
    body = (await other.get(f"{V1}/statistics", params={"period": "week", "day": str(WEEK)})).json()
    assert (
        body["total"] == 0
        and body["hidden"] == 0
        and body["counts"]
        == {
            "goal_aligned": 0,
            "maintenance": 0,
            "off_plan": 0,
        }
    )
    assert body["empty"]["reason"] == "no_labels" and body["sync"]["outcome"] is None
    listed = (
        await other.get(f"{V1}/statistics/tasks", params={"period": "week", "day": str(WEEK)})
    ).json()
    assert listed["total"] == 0 and listed["items"] == []
    mine = await s.stats("week", WEEK)
    assert mine["total"] == 1 and mine["hidden"] == 1
