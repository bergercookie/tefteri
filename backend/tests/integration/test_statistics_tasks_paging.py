"""The list of completed tasks has no cap and pages without losing or repeating a task (M3)."""

from datetime import timedelta

import pytest
from sqlalchemy import select

from tefteri.db.models.connection import Connection
from tefteri.domain.entities import Container
from tests.conftest import V1
from tests.integration.conftest import ProjectsEnv
from tests.integration.stats_helpers import NEXT, WEEK, Stats, at


@pytest.mark.parametrize("limit", [50, 200])
async def test_250_off_plan_tasks_are_all_reachable_in_pages(env: ProjectsEnv, limit: int) -> None:
    s = Stats(env)
    await s.standard()
    s.bulk("p9", 250, "Off", at(5), step=timedelta(minutes=1))
    await s.sync()
    first = await s.page(period="week", day=str(WEEK), category="off_plan", limit=limit)
    assert first["total"] == 250 and len(first["items"]) == limit
    items = await s.all_tasks(limit, period="week", day=str(WEEK), category="off_plan")
    titles = [t["title"] for t in items]
    assert len(titles) == 250 and len(set(titles)) == 250  # no repeat, no gap
    assert titles[0] == "Off 0249"  # the newest first
    stats = await s.stats("week", WEEK)
    assert stats["counts"]["off_plan"] == 250  # no cap of 200 any more


async def test_a_thousand_tasks_are_all_reachable(env: ProjectsEnv) -> None:
    s = Stats(env)
    await s.standard()
    s.bulk("p9", 1000, "Many", at(5), step=timedelta(seconds=30))
    await s.sync()
    items = await s.all_tasks(200, period="week", day=str(WEEK))
    assert len({t["id"] for t in items}) == 1000
    assert (await s.page(period="week", day=str(WEEK), limit=200))["total"] == 1000


async def test_month_and_year_counts_have_no_cap(env: ProjectsEnv) -> None:
    s = Stats(env)
    await s.standard()
    s.bulk("p9", 260, "Month", at(5), step=timedelta(minutes=1))
    await s.sync()
    assert (await s.stats("month", WEEK))["counts"]["off_plan"] == 260
    assert (await s.stats("year", WEEK))["counts"]["off_plan"] == 260
    assert len(await s.all_tasks(200, period="month", day=str(WEEK))) == 260


@pytest.mark.parametrize("order", ["newest", "project"])
async def test_both_orders_are_stable_when_many_tasks_share_one_completion_time(
    env: ProjectsEnv, order: str
) -> None:
    s = Stats(env)
    await s.standard()
    s.bulk("p9", 120, "Same", at(5))  # one completion time for all of them
    s.bulk("p5", 80, "Same2", at(5))
    await s.sync()
    items = await s.all_tasks(30, period="week", day=str(WEEK), order=order)
    ids = [t["id"] for t in items]
    assert len(ids) == 200 and len(set(ids)) == 200
    again = await s.all_tasks(7, period="week", day=str(WEEK), order=order)
    assert [t["id"] for t in again] == ids  # the same order at any page size


async def test_a_task_completed_while_the_client_pages_does_not_shift_the_next_page(
    env: ProjectsEnv,
) -> None:
    s = Stats(env)
    await s.standard()
    s.bulk("p9", 120, "Page", at(5), step=timedelta(minutes=1))
    await s.sync()
    full = [t["id"] for t in await s.all_tasks(50, period="week", day=str(WEEK))]
    first = await s.page(period="week", day=str(WEEK), limit=50)
    # A new task, newer than every task, is completed between the two requests.
    s.bulk("p9", 1, "Later", at(8))
    await s.sync()
    rest: list[str] = []
    cursor = first["next_cursor"]
    while cursor:
        page = await s.page(period="week", day=str(WEEK), limit=50, cursor=cursor)
        rest.extend(t["id"] for t in page["items"])
        cursor = page["next_cursor"]
    assert [t["id"] for t in first["items"]] + rest == full  # no shift, no repeat, no gap


async def test_a_bad_cursor_and_a_cursor_of_another_filter_are_invalid(env: ProjectsEnv) -> None:
    s = Stats(env)
    await s.standard()
    s.bulk("p9", 10, "C", at(5), step=timedelta(minutes=1))
    await s.sync()
    first = await s.page(period="week", day=str(WEEK), limit=3)
    cursor = first["next_cursor"]
    assert cursor
    for params in (
        {"cursor": "not a cursor"},
        {"cursor": ""[:0] or "e30"},  # valid base64 of {} : no filter
        {"cursor": cursor, "order": "project"},
        {"cursor": cursor, "category": "maintenance"},
        {"cursor": cursor, "day": str(NEXT)},
        {"cursor": cursor, "period": "month"},
    ):
        r = await env.api.get(
            f"{V1}/statistics/tasks", params={"period": "week", "day": str(WEEK)} | params
        )
        assert r.status_code == 422, params
        assert r.json()["code"] == "invalid_cursor", params


async def test_the_list_of_a_category_is_exactly_the_tasks_behind_its_count(
    env: ProjectsEnv,
) -> None:
    s = Stats(env)
    await s.standard()
    await s.add("p3", "Seed")
    await s.weekly.commit(WEEK, "Login flow")
    await s.done("p3", "Goal 1", at(4))
    await s.done("p3", "Goal 2", at(5))
    await s.done("p5", "Maint", at(5))
    await s.done("p6", "Maint inside", at(6))
    await s.done("p9", "Off 1", at(7))
    await s.done("p2", "Off theme", at(7))
    await s.done("p7", "Hidden 1", at(7))
    await s.done("p8", "Hidden 2", at(7))
    await s.sync()
    stats = await s.stats("week", WEEK)
    for category in ("goal_aligned", "maintenance", "off_plan", "hidden"):
        listed = await s.all_tasks(period="week", day=str(WEEK), category=category)
        count = stats["hidden"] if category == "hidden" else stats["counts"][category]
        assert len(listed) == count, category
        assert {t["category"] for t in listed} == {category}
    assert sorted(await s.titles("hidden")) == ["Hidden 1", "Hidden 2"]
    # No category: the three work categories, never the hidden tasks.
    assert len(await s.titles()) == stats["total"] == 6


async def test_order_by_project_groups_by_stored_name_case_folded_no_project_last(
    env: ProjectsEnv,
) -> None:
    s = Stats(env)
    await env.connect(
        Container("pa", "banana"), Container("pb", "Apple"), Container("pc", "cherry")
    )
    await s.done("pa", "b1", at(4))
    await s.done("pb", "a1", at(4))
    await s.done("pc", "c1", at(4))
    await s.done("pb", "a2", at(6))
    await s.done("pa", "b2", at(6))
    await s.sync()
    # A done task with no project: the project row is gone from the cache.
    from tefteri.db.models.task import Task

    async with env.db() as db:
        connection = (
            (await db.execute(select(Connection).where(Connection.kind == "tasks"))).scalars().one()
        )
        assert connection is not None
        db.add(
            Task(
                user_id=await env.user_id(),
                connection_id=connection.id,
                container_id=None,
                remote_id="loose",
                title="loose",
                status="done",
                completed_at=at(5),
                remote_version="v1",
            )
        )
        await db.flush()
        await env.app.state.category_recorder.record_new(db, await env.user_id(), {})
    got = [
        (t["project"]["name"], t["title"])
        for t in await s.all_tasks(2, period="week", day=str(WEEK), order="project")
    ]
    assert got == [
        ("Apple", "a2"),
        ("Apple", "a1"),
        ("banana", "b2"),
        ("banana", "b1"),
        ("cherry", "c1"),
        (None, "loose"),
    ]


async def test_an_orphaned_or_renamed_project_shows_the_stored_name_and_orphaned(
    env: ProjectsEnv,
) -> None:
    s = Stats(env)
    await s.standard()
    await s.done("p9", "In misc", at(5))
    await s.done("p5", "In chores", at(5))
    await s.sync()
    s.backend.containers = [
        Container("p5", "Housework") if c.remote_id == "p5" else c
        for c in s.backend.containers
        if c.remote_id != "p9"
    ]
    await s.sync()
    by = {t["title"]: t["project"] for t in await s.all_tasks(period="week", day=str(WEEK))}
    # The task of an orphaned project left the cache with it: nothing is counted or listed.
    assert "In misc" not in by
    assert by["In chores"]["name"] == "Chores" and by["In chores"]["orphaned"] is False
    assert by["In chores"]["id"] is not None


async def test_a_deleted_or_reopened_task_is_not_listed(env: ProjectsEnv) -> None:
    s = Stats(env)
    await s.standard()
    for name in ("Stays", "Deleted", "Reopened"):
        await s.done("p9", name, at(5))
    await s.sync()
    s.reopen("Reopened")
    del s.backend.tasks[next(i for i, t in s.backend.tasks.items() if t.title == "Deleted")]
    await s.sync()
    assert await s.titles() == ["Stays"]


async def test_the_link_and_the_color_of_the_project_are_in_each_item(env: ProjectsEnv) -> None:
    s = Stats(env)
    await s.standard()
    s.backend.containers = [
        Container(c.remote_id, c.name, c.parent_id, "#aabbcc" if c.remote_id == "p9" else None)
        for c in s.backend.containers
    ]
    await s.done("p9", "Colourful", at(5))
    await s.sync()
    async with env.db() as db:
        connection = (
            (await db.execute(select(Connection).where(Connection.kind == "tasks"))).scalars().one()
        )
        connection.settings = {"base_url": "https://tasks.example"}
    (item,) = await s.all_tasks(period="week", day=str(WEEK))
    assert item["project"]["color"] == "#aabbcc"
    assert item["url"].startswith("https://tasks.example/tasks/")
    assert set(item) == {
        "id",
        "title",
        "completed_at",
        "completed_day",
        "category",
        "reason",
        "unsorted",
        "project",
        "url",
    }
    assert item["completed_at"].endswith("Z") and item["unsorted"] is True
