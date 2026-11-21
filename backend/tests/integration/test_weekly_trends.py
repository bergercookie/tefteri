"""The numbers of the weeks, to compare a week with the earlier ones. Counts only."""

from datetime import UTC, date, datetime, timedelta
from typing import Any

from httpx import AsyncClient

from tests.conftest import V1
from tests.integration.conftest import ProjectsEnv
from tests.integration.stats_helpers import WEEK, Stats, at


def _today(env: ProjectsEnv, day: int, month: int = 3) -> None:
    env.app.state.clock = lambda: datetime(2030, month, day, 15, tzinfo=UTC)


async def _trends(s: Stats, weeks: int = 12) -> list[dict[str, Any]]:
    r = await s.api.get(f"{V1}/weekly/trends", params={"weeks": weeks})
    assert r.status_code == 200, r.text
    body: dict[str, Any] = r.json()
    return list(body["weeks"])


async def _committed(env: ProjectsEnv, tasks: int = 10) -> Stats:
    s = Stats(env)
    await s.standard()
    for i in range(tasks):
        await s.add("p3", f"Task {i + 1}")
    await s.sync()
    await s.weekly.commit(WEEK, "Login flow")
    return s


async def test_the_running_week_has_the_plan_and_the_work_done(env: ProjectsEnv) -> None:
    s = await _committed(env)
    for title, day in (("Task 1", 4), ("Task 2", 5), ("Task 3", 6), ("Task 4", 6)):
        s.finish(title, at(day))
    await s.done("p9", "Odd job", at(6))  # a project without a label: off-plan
    await s.done("p6", "Wash up", at(7))  # inside a routine: maintenance
    await s.sync()
    _today(env, 7)  # Thursday of the week of WEEK
    weeks = await _trends(s, 4)
    assert [w["week_start"] for w in weeks][-1] == str(WEEK)
    now = weeks[-1]
    assert now["finished"] is False and now["has_plan"] is True
    assert (now["committed_tasks"], now["committed_done"]) == (10, 4)
    assert now["completion_percent"] == 40
    assert (now["milestones_committed"], now["milestones_done"]) == (1, 0)
    # Every completed task, in the three categories; the share of goal-aligned work.
    assert (now["goal_aligned"], now["maintenance"], now["off_plan"]) == (4, 1, 1)
    assert now["tasks_done"] == 6 and now["goal_aligned_percent"] == 67
    assert now["has_data"] is True


async def test_weeks_with_nothing_have_no_data_and_come_oldest_first(env: ProjectsEnv) -> None:
    s = await _committed(env)
    _today(env, 7)
    weeks = await _trends(s, 4)
    starts = [date.fromisoformat(w["week_start"]) for w in weeks]
    assert starts == [
        WEEK - timedelta(days=21),
        WEEK - timedelta(days=14),
        WEEK - timedelta(days=7),
        WEEK,
    ]
    before = weeks[0]
    assert before["has_data"] is False and before["has_plan"] is False
    assert before["completion_percent"] is None and before["goal_aligned_percent"] is None
    assert before["finished"] is True
    # A week with a plan but no finished task has a completion of 0, not "no data".
    assert weeks[-1]["completion_percent"] == 0 and weeks[-1]["has_data"] is True


async def test_a_week_that_ended_is_kept_and_does_not_change(env: ProjectsEnv) -> None:
    s = await _committed(env)
    s.finish("Task 1", at(5))
    s.finish("Task 2", at(6))
    await s.sync()
    _today(env, 12)  # the week after: WEEK has ended
    weeks = await _trends(s, 2)
    last = next(w for w in weeks if w["week_start"] == str(WEEK))
    assert last["finished"] is True and last["tasks_done"] == 2
    # A task of that week is deleted in the task app afterwards. The week stays as it was.
    remote_id, _ = next((i, t) for i, t in s.backend.tasks.items() if t.title == "Task 1")
    del s.backend.tasks[remote_id]
    await s.sync()
    again = next(w for w in await _trends(s, 2) if w["week_start"] == str(WEEK))
    assert again["tasks_done"] == 2 and again["goal_aligned"] == 2


async def test_milestones_that_became_done_and_the_themes_with_work(env: ProjectsEnv) -> None:
    s = Stats(env)
    await s.standard()
    await s.add("p3", "Only task")
    await s.add("p4", "Docs task")
    await s.add("p9", "Odd job")
    await s.sync()
    await s.weekly.commit(WEEK, "Login flow")
    for title, day in (("Only task", 5), ("Docs task", 6), ("Odd job", 6)):
        s.finish(title, at(day))
    await s.sync()
    _today(env, 8)
    now = (await _trends(s, 1))[-1]
    # Login flow is done: its only task is closed. It was committed, and it became done in the
    # week. Docs has a closed task too, but it has no record as a milestone (it was never
    # committed or created in tefteri), so it is not counted as a finished milestone.
    assert now["milestones_committed"] == 1 and now["milestones_done"] == 1
    assert now["milestones_finished"] == 1
    # Login flow and Docs are under the theme Open source; Misc has no theme.
    assert now["themes_active"] == 1
    assert now["tasks_done"] == 3


async def test_the_number_of_weeks_is_kept_in_bounds(env: ProjectsEnv) -> None:
    s = Stats(env)
    await s.standard()
    _today(env, 7)
    assert len(await _trends(s, 0)) == 1
    assert len(await _trends(s, 3)) == 3
    assert len(await _trends(s, 500)) == 52


async def test_the_trends_need_a_signed_in_user(client: AsyncClient) -> None:
    assert (await client.get(f"{V1}/weekly/trends")).status_code == 401
