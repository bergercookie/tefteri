"""The ``progress`` block of the week statistics has the numbers of the old client class."""

from datetime import UTC, datetime

import pytest

from tests.integration.conftest import ProjectsEnv
from tests.integration.stats_helpers import NEXT, WEEK, Stats, at


async def _committed(env: ProjectsEnv, tasks: int = 10) -> Stats:
    s = Stats(env)
    await s.standard()
    for i in range(tasks):
        await s.add("p3", f"Task {i + 1}")
    await s.sync()
    await s.weekly.commit(WEEK, "Login flow")
    return s


def _today(env: ProjectsEnv, day: int, hour: int = 15) -> None:
    env.app.state.clock = lambda: datetime(2030, 3, day, hour, tzinfo=UTC)


async def test_progress_has_the_numbers_of_the_old_week_progress_class(env: ProjectsEnv) -> None:
    s = await _committed(env)
    for title, day in (("Task 1", 4), ("Task 2", 4), ("Task 3", 5), ("Task 4", 6)):
        s.finish(title, at(day))
    await s.sync()
    _today(env, 6)  # Wednesday
    p = (await s.stats("week", WEEK))["progress"]
    assert p["committed"] == 10 and p["done"] == 4 and p["scope"] == 10
    assert p["done_by_day"] == [2, 1, 1, 0, 0, 0, 0]
    assert (p["done_before"], p["done_undated"], p["done_after"]) == (0, 0, 0)
    assert (p["days_elapsed"], p["days_left"]) == (3, 5)
    assert p["cadence"] == pytest.approx(4 / 3)
    assert p["needed_per_day"] == pytest.approx(6 / 5)
    assert p["on_track"] is True
    assert p["remaining_by_day"] == [8, 7, 6, None, None, None, None]
    assert p["ideal_by_day"][0] == pytest.approx(10 * 6 / 7, abs=0.01)
    assert p["ideal_by_day"][-1] == 0


async def test_progress_is_behind_late_in_the_week(env: ProjectsEnv) -> None:
    s = await _committed(env)
    for title, day in (("Task 1", 4), ("Task 2", 4), ("Task 3", 5), ("Task 4", 6)):
        s.finish(title, at(day))
    await s.sync()
    _today(env, 10)  # Sunday
    p = (await s.stats("week", WEEK))["progress"]
    assert p["days_left"] == 1 and p["needed_per_day"] == 6
    assert p["cadence"] == pytest.approx(4 / 7) and p["on_track"] is False


async def test_progress_is_null_with_no_committed_plan_a_draft_a_month_and_a_year(
    env: ProjectsEnv,
) -> None:
    s = Stats(env)
    await s.standard()
    assert (await s.stats("week", WEEK))["progress"] is None  # no plan
    await s.weekly.add(NEXT, "Login flow")  # a draft
    assert (await s.stats("week", NEXT))["progress"] is None
    await s.add("p3", "Task")
    await s.weekly.commit(WEEK, "Login flow")
    assert (await s.stats("week", WEEK))["progress"] is not None
    assert (await s.stats("month", WEEK))["progress"] is None
    assert (await s.stats("year", WEEK))["progress"] is None


async def test_a_task_done_before_the_week_with_no_day_or_after_it_is_counted_as_before(
    env: ProjectsEnv,
) -> None:
    s = await _committed(env, 5)
    s.finish("Task 1", datetime(2030, 3, 1, 9, tzinfo=UTC))  # before the week
    s.finish("Task 2", None)  # done, the app says no day
    s.finish("Task 3", at(5))
    s.finish("Task 4", at(14))  # after the week
    await s.sync()
    _today(env, 20)
    p = (await s.stats("week", WEEK))["progress"]
    assert p["committed"] == 5 and p["done"] == 4
    assert (p["done_before"], p["done_undated"], p["done_after"]) == (1, 1, 1)
    assert p["done_by_day"] == [0, 1, 0, 0, 0, 0, 0]
    assert p["scope"] == 3 and p["days_left"] == 0 and p["needed_per_day"] is None
    assert p["remaining_by_day"][-1] == 2


async def test_a_committed_plan_with_no_task_has_progress_with_zero_committed(
    env: ProjectsEnv,
) -> None:
    s = Stats(env)
    await s.standard()
    await env.api.post(f"/api/v1/weekly/{WEEK}/start")
    assert (await env.api.post(f"/api/v1/weekly/{WEEK}/commit")).status_code == 200
    _today(env, 6)
    p = (await s.stats("week", WEEK))["progress"]
    assert p["committed"] == 0 and p["on_track"] is True and p["needed_per_day"] is None


async def test_done_tasks_stay_in_the_plan_when_a_sync_does_not_list_them(env: ProjectsEnv) -> None:
    """A sync that flags a done task as deleted must not shrink the committed plan."""
    s = await _committed(env)
    for title, day in (("Task 1", 4), ("Task 2", 4), ("Task 3", 5), ("Task 4", 6)):
        s.finish(title, at(day))
    await s.sync()
    _today(env, 6)
    # The task app does not list the four done tasks in the next sync.
    done = {i: t for i, t in s.backend.tasks.items() if t.done}
    for i in done:
        del s.backend.tasks[i]
    await s.sync()
    p = (await s.stats("week", WEEK))["progress"]
    assert p["committed"] == 10 and p["done"] == 4 and p["scope"] == 10
    s.backend.tasks.update(done)
    await s.sync()
    assert (await s.stats("week", WEEK))["progress"]["committed"] == 10


async def test_an_open_task_that_is_gone_leaves_the_plan(env: ProjectsEnv) -> None:
    s = await _committed(env)
    _today(env, 5)
    gone = next(i for i, t in s.backend.tasks.items() if t.title == "Task 1")
    del s.backend.tasks[gone]
    await s.sync()
    p = (await s.stats("week", WEEK))["progress"]
    assert p["committed"] == 9 and p["done"] == 0 and p["scope"] == 9


async def test_the_look_back_keeps_done_tasks_when_a_sync_does_not_list_them(
    env: ProjectsEnv,
) -> None:
    """Planning the next week shows the reviewed week with its done tasks still counted."""
    s = await _committed(env)
    for title, day in (("Task 1", 4), ("Task 2", 4)):
        s.finish(title, at(day))
    await s.sync()
    done = {i: t for i, t in s.backend.tasks.items() if t.done}
    for i in done:
        del s.backend.tasks[i]
    await s.sync()
    (project,) = (await s.weekly.look_back(WEEK))["projects"]
    assert (project["committed"], project["done"]) == (10, 2)
    s.backend.tasks.update(done)
    await s.sync()
