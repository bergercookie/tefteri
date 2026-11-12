"""A completed task gets its category when tefteri first sees it (spec 005, M2)."""

import uuid
from datetime import date

from sqlalchemy import select

from tefteri.db.models.milestone import Milestone
from tefteri.db.models.project_label import ProjectLabel as ProjectLabelRow
from tefteri.db.models.task_category import TaskCategory
from tests.integration.conftest import ProjectsEnv
from tests.integration.stats_helpers import NEXT, WEEK, Stats, at


async def test_a_task_done_in_a_committed_milestone_is_goal_aligned(env: ProjectsEnv) -> None:
    s = Stats(env)
    await s.standard()
    await s.add("p3", "Fix login")
    await s.weekly.commit(WEEK, "Login flow")
    s.finish("Fix login", at(6, 22, 30))
    await s.sync()
    row = (await s.rows())["Fix login"]
    assert (row.category, row.reason, row.unsorted) == (
        "goal_aligned",
        "committed_milestone",
        False,
    )
    assert (row.project_name, row.project_label, row.decided_via) == (
        "Login flow",
        "milestone",
        "sync",
    )
    assert row.completed_on == date(2030, 3, 6)
    async with env.db() as db:
        plan = (await s.weekly.state(WEEK))["plan"]["id"]
        assert row.plan_id == uuid.UUID(plan)
        project = (
            await db.execute(select(ProjectLabelRow).where(ProjectLabelRow.name == "Login flow"))
        ).scalar_one()
    assert row.project_id == project.id


async def test_a_task_in_a_committed_project_that_was_not_committed_is_goal_aligned(
    env: ProjectsEnv,
) -> None:
    s = Stats(env)
    await s.standard()
    await s.add("p3", "Committed")
    await s.weekly.commit(WEEK, "Login flow")
    await s.done("p3", "Added after the commit", at(5))
    s.finish("Committed", at(4))
    await s.sync()
    rows = await s.rows()
    assert {t: r.category for t, r in rows.items()} == {
        "Committed": "goal_aligned",
        "Added after the commit": "goal_aligned",
    }


async def test_a_milestone_committed_only_the_week_before_is_off_plan(env: ProjectsEnv) -> None:
    s = Stats(env)
    await s.standard()
    await s.add("p3", "Seed")
    await s.weekly.commit(WEEK, "Login flow")
    await s.done("p3", "Next week", at(12))  # the week after the commitment
    await s.sync()
    row = (await s.rows())["Next week"]
    assert (row.category, row.reason) == ("off_plan", "milestone_not_committed")
    assert row.plan_id is None


async def test_a_parked_closed_or_done_milestone_is_still_goal_aligned_that_week(
    env: ProjectsEnv,
) -> None:
    s = Stats(env)
    await s.standard()
    await s.add("p3", "Seed")
    await s.weekly.commit(WEEK, "Login flow")
    for n, state in enumerate(("parked", "closed", "done")):
        async with env.db() as db:
            (milestone,) = (await db.execute(select(Milestone))).scalars().all()
            milestone.state = state
        await s.done("p3", f"After {state}", at(4 + n))
        await s.sync()
    rows = await s.rows()
    for state in ("parked", "closed", "done"):
        assert rows[f"After {state}"].category == "goal_aligned", state


async def test_a_draft_plan_commits_nothing(env: ProjectsEnv) -> None:
    s = Stats(env)
    await s.standard()
    await s.weekly.add(WEEK, "Login flow")  # a draft: not committed
    await s.done("p3", "In a draft", at(5))
    await s.sync()
    row = (await s.rows())["In a draft"]
    assert (row.category, row.reason) == ("off_plan", "milestone_not_committed")


async def test_the_weekly_commitment_is_read_through_the_provider_seam(env: ProjectsEnv) -> None:
    s = Stats(env)
    await s.standard()
    asked: list[date] = []
    project = (await env.rows())["Login flow"].id

    class Provider:
        async def committed_projects(self, db: object, user_id: uuid.UUID, week_start: date):  # type: ignore[no-untyped-def]
            asked.append(week_start)
            return {project}

    env.app.state.category_recorder._commitments = Provider()  # noqa: SLF001
    await s.done("p3", "Through the seam", at(6))  # Wednesday 6 March 2030
    await s.sync()
    assert asked == [WEEK]  # the Monday of the completion week
    assert (await s.rows())["Through the seam"].category == "goal_aligned"


async def test_maintenance_is_maintenance_with_no_plan_a_draft_and_a_committed_plan(
    env: ProjectsEnv,
) -> None:
    s = Stats(env)
    await s.standard()
    # Week of WEEK: no plan. NEXT: a draft. The week after: a committed plan.
    third = date(2030, 3, 18)
    await s.weekly.add(NEXT, "Login flow")
    await s.add("p3", "Seed")
    await s.weekly.commit(third, "Login flow")  # Login flow shares the theme Open source
    for n, day in enumerate((4, 12, 20)):
        await s.done("p5", f"Chore {n}", at(day))
    await s.done("p6", "Dishes 1", at(21))
    await s.done("p6", "Dishes 2", at(22))
    await s.sync()
    rows = await s.rows()
    assert len(rows) == 5
    assert {r.category for r in rows.values()} == {"maintenance"}
    assert rows["Chore 0"].reason == "maintenance_label"
    assert rows["Dishes 1"].reason == "inside_routine"
    assert all(r.plan_id is None and not r.unsorted for r in rows.values())


async def test_goal_type_tasks_in_a_week_with_no_commitment_are_off_plan(env: ProjectsEnv) -> None:
    s = Stats(env)
    await s.standard()
    await s.done("p3", "A milestone task", at(5))
    await s.done("p2", "A theme task", at(5))
    await s.sync()
    rows = await s.rows()
    assert (rows["A milestone task"].category, rows["A milestone task"].reason) == (
        "off_plan",
        "milestone_not_committed",
    )
    assert (rows["A theme task"].category, rows["A theme task"].reason) == ("off_plan", "theme")


async def test_a_provider_that_cannot_read_the_commitment_makes_the_recorder_write_nothing(
    env: ProjectsEnv,
) -> None:
    s = Stats(env)
    await s.standard()

    class Unavailable:
        async def committed_projects(self, db: object, user_id: uuid.UUID, week_start: date):  # type: ignore[no-untyped-def]
            return None

    real = env.app.state.category_recorder._commitments  # noqa: SLF001
    env.app.state.category_recorder._commitments = Unavailable()  # noqa: SLF001
    await s.done("p5", "Maintenance", at(5))
    await s.done("p3", "Milestone", at(5))
    await s.sync()
    assert await s.rows() == {}
    async with env.db() as db:
        assert (await db.execute(select(TaskCategory))).scalars().all() == []
    # Once the commitment can be read again, the next sync records the tasks of that time.
    env.app.state.category_recorder._commitments = real  # noqa: SLF001
    await s.sync()
    assert set(await s.rows()) == {"Maintenance", "Milestone"}
