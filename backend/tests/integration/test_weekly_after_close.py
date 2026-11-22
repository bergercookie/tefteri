"""The numbers of a week come from the plan as it was committed, also after a milestone was closed.

Closing a milestone moves its open tasks to the theme. The plan keeps the ids of the tasks that
were committed at the start of the week, so the look-back, the review and the trends must count
those tasks wherever they are now (the user's plan is the plan of the start of the week).
"""

from datetime import UTC, datetime
from typing import Any

from tefteri.domain.entities import Container
from tests.conftest import V1
from tests.integration.conftest import ProjectsEnv
from tests.integration.stats_helpers import Stats, at
from tests.integration.weekly_helpers import NEXT, WEEK, Weekly


async def _committed_week(env: ProjectsEnv) -> tuple[Weekly, str]:
    weekly = Weekly(env)
    await env.connect(
        Container("p2", "Open source"),
        Container("p3", "Login flow", "p2"),
        tasks={"p3": 5},
    )
    await weekly.label(**{"Open source": "theme", "Login flow": "milestone"})
    plan = await weekly.commit(WEEK, "Login flow")
    milestone = str(plan["plan"]["projects"][0]["milestone_id"])
    return weekly, milestone


async def _trend(env: ProjectsEnv, weekly: Weekly) -> dict[str, Any]:
    env.app.state.clock = lambda: datetime(2030, 3, 20, 12, tzinfo=UTC)  # two weeks later
    r = await weekly.api.get(f"{V1}/weekly/trends", params={"weeks": 4})
    assert r.status_code == 200, r.text
    weeks: list[dict[str, Any]] = r.json()["weeks"]
    return next(w for w in weeks if w["week_start"] == str(WEEK))


async def test_a_closed_milestone_keeps_its_committed_tasks_in_the_look_back(
    env: ProjectsEnv,
) -> None:
    weekly, milestone = await _committed_week(env)
    await weekly.complete("p3 task 0", "p3 task 1")
    closed = await weekly.api.post(f"{V1}/milestones/{milestone}/close", json={"confirm": True})
    assert closed.status_code == 200, closed.text
    assert closed.json()["moved"] == 3  # the open tasks are in the theme now
    summary = (await weekly.look_back(WEEK))["summary"]
    assert (summary["committed_tasks"], summary["done_tasks"]) == (5, 2)
    entry = (await weekly.look_back_entries(WEEK))["Login flow"]
    assert (entry["committed"], entry["done"]) == (5, 2)
    assert len(entry["leftover"]) == 3  # the moved tasks are still listed as not done


async def test_a_review_after_the_close_stores_the_committed_numbers(env: ProjectsEnv) -> None:
    weekly, milestone = await _committed_week(env)
    await weekly.complete("p3 task 0", "p3 task 1")
    await weekly.api.post(f"{V1}/milestones/{milestone}/close", json={"confirm": True})
    reviewed = await weekly.review(WEEK, {"name": "Login flow", "decision": "close"})
    assert reviewed.status_code == 200, reviewed.text
    entry = (await weekly.look_back_entries(WEEK))["Login flow"]
    assert (entry["committed"], entry["done"]) == (5, 2)
    week = await _trend(env, weekly)
    assert (week["committed_tasks"], week["committed_done"]) == (5, 2)
    assert week["completion_percent"] == 40
    assert (week["milestones_committed"], week["milestones_done"]) == (1, 0)


async def test_a_task_done_after_it_moved_still_counts_for_the_week(env: ProjectsEnv) -> None:
    weekly, milestone = await _committed_week(env)
    await weekly.complete("p3 task 0")
    await weekly.api.post(f"{V1}/milestones/{milestone}/close", json={"confirm": True})
    await weekly.complete("p3 task 1")  # done in the theme, after the close
    entry = (await weekly.look_back_entries(WEEK))["Login flow"]
    assert (entry["committed"], entry["done"]) == (5, 2)
    assert NEXT > WEEK


async def test_a_committed_task_done_after_it_moved_to_the_theme_is_goal_aligned(
    env: ProjectsEnv,
) -> None:
    s = Stats(env)
    await s.standard()
    for title in ("Task 1", "Task 2", "Task 3"):
        await s.add("p3", title)
    await s.sync()
    await s.weekly.commit(WEEK, "Login flow")
    s.finish("Task 1", at(5))
    # The milestone is closed: the open tasks return to the theme (project p2).
    s.move("Task 2", "p2")
    s.move("Task 3", "p2")
    await s.sync()
    s.finish("Task 2", at(6))  # done in the theme, but committed at the start of the week
    await s.done("p2", "Extra", at(6))  # done in the theme and never planned
    await s.sync()
    rows = await s.rows()
    assert (rows["Task 1"].category, rows["Task 1"].reason) == (
        "goal_aligned",
        "committed_milestone",
    )
    assert (rows["Task 2"].category, rows["Task 2"].reason) == (
        "goal_aligned",
        "committed_milestone",
    )
    assert (rows["Extra"].category, rows["Extra"].reason) == ("off_plan", "theme")
    summary = await s.stats("week", WEEK)
    assert summary["counts"]["goal_aligned"] == 2 and summary["counts"]["off_plan"] == 1
    # The task that is still open is a committed one too, so it is goal-aligned.
    open_work = (await s.api.get(f"{V1}/statistics/open", params={"day": str(WEEK)})).json()
    assert open_work["counts"]["goal_aligned"] == 1
