"""Unusual projects and moved tasks (spec 005, US5)."""

import uuid

from sqlalchemy import select

from tefteri.db.models.connection import Connection
from tefteri.db.models.project_label import ProjectLabel as ProjectLabelRow
from tefteri.db.models.project_label import ProjectLabelHistory
from tefteri.db.models.task import Task
from tests.integration.conftest import ProjectsEnv
from tests.integration.stats_helpers import WEEK, Stats, at


async def test_a_task_moved_to_another_project_and_completed_after_a_sync_counts_the_new_one(
    env: ProjectsEnv,
) -> None:
    s = Stats(env)
    await s.standard()
    await s.add("p9", "Moves")  # Misc, no label
    await s.sync()
    s.move("Moves", "p5")  # Chores: maintenance
    await s.sync()  # this sync saw the task in Chores
    s.finish("Moves", at(5))
    await s.sync()
    row = (await s.rows())["Moves"]
    assert (row.project_name, row.category) == ("Chores", "maintenance")


async def test_a_task_seen_open_in_one_project_and_done_in_another_counts_the_first(
    env: ProjectsEnv,
) -> None:
    s = Stats(env)
    await s.standard()
    await s.add("p9", "Between syncs")
    await s.sync()
    s.move("Between syncs", "p5")
    s.finish("Between syncs", at(5))
    await s.sync()
    row = (await s.rows())["Between syncs"]
    assert (row.project_name, row.category, row.reason) == ("Misc", "off_plan", "unclassified")


async def test_a_task_first_seen_done_counts_the_current_project(env: ProjectsEnv) -> None:
    s = Stats(env)
    await s.standard()
    await s.done("p5", "Never seen open", at(5))
    await s.sync()
    assert (await s.rows())["Never seen open"].project_name == "Chores"


async def test_unclassified_and_no_project_are_off_plan_and_unsorted(env: ProjectsEnv) -> None:
    s = Stats(env)
    await s.standard()
    await s.done("p9", "Unclassified", at(5))
    await s.sync()
    async with env.db() as db:
        # A done task that no project holds (its project is gone from the cache).
        user_id = await env.user_id()
        connection = (
            (await db.execute(select(Connection).where(Connection.kind == "tasks"))).scalars().one()
        )
        assert connection is not None
        db.add(
            Task(
                user_id=user_id,
                connection_id=connection.id,
                container_id=None,
                remote_id="loose",
                title="No project",
                status="done",
                completed_at=at(5),
                remote_version="v1",
            )
        )
        await db.flush()
        # The sync would mark a task that the app does not list as deleted: run the recorder.
        await env.app.state.category_recorder.record_new(db, user_id, {})
    rows = await s.rows()
    assert (rows["Unclassified"].reason, rows["Unclassified"].unsorted) == ("unclassified", True)
    r = rows["No project"]
    assert (r.category, r.reason, r.unsorted, r.project_id, r.project_name) == (
        "off_plan",
        "no_project",
        True,
        None,
        None,
    )
    stats = await s.stats("week", WEEK)
    assert stats["unsorted"] == 2 and stats["counts"]["off_plan"] == 2


async def test_ignored_and_the_child_of_an_ignored_project_are_hidden(env: ProjectsEnv) -> None:
    s = Stats(env)
    await s.standard()
    await s.done("p7", "In ignored", at(5))
    await s.done("p8", "In child of ignored", at(5))
    await s.sync()
    rows = await s.rows()
    assert (rows["In ignored"].category, rows["In ignored"].reason) == ("hidden", "ignored")
    assert (rows["In child of ignored"].category, rows["In child of ignored"].reason) == (
        "hidden",
        "ignored_ancestor",
    )
    stats = await s.stats("week", WEEK)
    assert stats["hidden"] == 2 and stats["total"] == 0 and stats["empty"] is None


async def test_a_child_of_a_maintenance_project_labelled_theme_is_maintenance(
    env: ProjectsEnv,
) -> None:
    s = Stats(env)
    await s.standard()
    await s.weekly.label(Dishes="theme")
    await s.done("p6", "Inside a routine", at(5))
    await s.sync()
    row = (await s.rows())["Inside a routine"]
    assert (row.category, row.reason, row.project_label) == (
        "maintenance",
        "inside_routine",
        "theme",
    )


async def _history(env: ProjectsEnv, name: str, *entries: tuple[str | None, int]) -> None:
    """Replace the history of a project: ``(label, day of March 2030)`` entries."""
    async with env.db() as db:
        row = (
            await db.execute(select(ProjectLabelRow).where(ProjectLabelRow.name == name))
        ).scalar_one()
        for old in (
            await db.execute(
                select(ProjectLabelHistory).where(ProjectLabelHistory.project_id == row.id)
            )
        ).scalars():
            await db.delete(old)
        for label, day in entries:
            db.add(
                ProjectLabelHistory(
                    id=uuid.uuid4(), project_id=row.id, label=label, from_at=at(day), source="user"
                )
            )
        row.label = entries[-1][0]


async def test_the_label_is_read_from_the_history_for_the_completion_day(
    env: ProjectsEnv,
) -> None:
    s = Stats(env)
    await s.standard()
    await _history(env, "Misc", ("theme", 1), ("maintenance", 5), (None, 9))
    await s.done("p9", "Early", at(3))
    await s.done("p9", "Middle", at(6))
    await s.done("p9", "Late", at(10))
    await s.sync()
    rows = await s.rows()
    assert (rows["Early"].category, rows["Early"].reason) == ("off_plan", "theme")
    assert rows["Middle"].category == "maintenance"
    assert rows["Late"].reason == "unclassified"  # back to unclassified from the 9th


async def test_the_oldest_label_is_used_when_the_history_starts_later(env: ProjectsEnv) -> None:
    s = Stats(env)
    await s.standard()
    await _history(env, "Misc", ("maintenance", 20), ("theme", 25))
    await s.done("p9", "Before any label", at(3))
    await s.sync()
    assert (await s.rows())["Before any label"].category == "maintenance"


async def test_an_orphaned_committed_milestone_keeps_goal_aligned_and_its_name(
    env: ProjectsEnv,
) -> None:
    s = Stats(env)
    await s.standard()
    await s.add("p3", "Seed")
    await s.weekly.commit(WEEK, "Login flow")
    await s.done("p3", "Done then orphaned", at(5))
    await s.sync()
    s.backend.containers = [c for c in s.backend.containers if c.remote_id != "p3"]
    await s.sync()
    row = (await s.rows())["Done then orphaned"]
    assert (row.category, row.project_name) == ("goal_aligned", "Login flow")
    async with env.db() as db:
        label = (
            await db.execute(select(ProjectLabelRow).where(ProjectLabelRow.name == "Login flow"))
        ).scalar_one()
        assert label.orphaned_reason == "missing" and row.project_id == label.id
