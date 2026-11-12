"""A stored category never changes, and a reopened or deleted task counts correctly (M2)."""

from dataclasses import replace
from datetime import UTC, date, datetime, timedelta

from sqlalchemy import select

from tefteri.db.models.task import Task
from tefteri.db.models.task_category import TaskCategory
from tefteri.domain.entities import Container, TaskDraft
from tests.conftest import V1
from tests.integration.conftest import ProjectsEnv
from tests.integration.stats_helpers import NEXT, WEEK, Stats, at


async def _recorded(s: Stats) -> dict[str, dict]:  # type: ignore[type-arg]
    await s.add("p3", "Fix login")
    await s.weekly.commit(WEEK, "Login flow")
    s.finish("Fix login", at(6))
    await s.sync()
    return await s.snapshot()


async def test_a_stored_category_survives_every_later_change(env: ProjectsEnv) -> None:
    s = Stats(env)
    await s.standard()
    before = await _recorded(s)
    assert before["Fix login"]["category"] == "goal_aligned"
    week_before = await s.stats("week", WEEK)

    # Relabel the project: the task is now work in a routine project.
    await s.weekly.label(**{"Login flow": "maintenance"})
    await s.sync()
    assert await s.snapshot() == before

    # Edit the past commitment: remove the project, add another one.
    assert (await env.api.post(f"{V1}/weekly/{WEEK}/reopen")).status_code == 200
    plan = (await s.weekly.state(WEEK))["plan"]
    entry = plan["projects"][0]["id"]
    assert (await env.api.delete(f"{V1}/weekly/{WEEK}/projects/{entry}")).status_code == 200
    await s.weekly.label(**{"Login flow": "milestone"})
    await s.weekly.add(WEEK, "Docs")
    await env.api.post(f"{V1}/weekly/{WEEK}/commit")
    await s.sync()
    assert await s.snapshot() == before

    # Rename the project, move the task, orphan the project: nothing changes.
    backend = s.backend
    backend.containers = [
        Container("p3", "Sign-in", "p2") if c.remote_id == "p3" else c for c in backend.containers
    ]
    s.move("Fix login", "p9")
    await s.sync()
    assert await s.snapshot() == before
    backend.containers = [c for c in backend.containers if c.remote_id not in ("p3", "p9")]
    await s.sync()
    snapshot = await s.snapshot()
    assert snapshot["Fix login"] == before["Fix login"]
    assert snapshot["Fix login"]["project_name"] == "Login flow"  # the stored name
    # The task is gone from the cache with its project, so it does not count; the row stays.
    assert (await s.stats("week", WEEK))["counts"]["goal_aligned"] == 0
    assert week_before["counts"]["goal_aligned"] == 1


async def test_a_past_week_keeps_its_numbers_when_the_labels_change(env: ProjectsEnv) -> None:
    s = Stats(env)
    await s.standard()
    await _recorded(s)
    await s.done("p5", "Wash up", at(5))
    await s.done("p9", "Misc job", at(7))
    await s.sync()
    before = await s.stats("week", WEEK)
    assert before["counts"] == {"goal_aligned": 1, "maintenance": 1, "off_plan": 1}
    await s.weekly.label(**{"Chores": "ignored", "Login flow": "theme", "Misc": "maintenance"})
    await s.sync()
    assert await s.stats("week", WEEK) == before | {"sync": (await s.stats("week", WEEK))["sync"]}


async def test_a_reopened_task_completed_again_gets_its_row_replaced_and_counts_once(
    env: ProjectsEnv,
) -> None:
    s = Stats(env)
    await s.standard()
    await s.done("p9", "Twice", at(5))
    await s.sync()
    first = (await s.rows())["Twice"]
    assert first.completed_on == date(2030, 3, 5)
    # While it is open, the row stays and does not count.
    s.reopen("Twice")
    await s.sync()
    assert (await s.stats("week", WEEK))["counts"]["off_plan"] == 0
    assert (await s.rows())["Twice"].id == first.id
    # Completed again, on another day: the row is replaced in place.
    s.finish("Twice", at(7))
    await s.sync()
    again = (await s.rows())["Twice"]
    assert again.id == first.id and again.completed_on == date(2030, 3, 7)
    stats = await s.stats("week", WEEK)
    assert stats["counts"]["off_plan"] == 1 and stats["total"] == 1
    day_parts = {p["start"]: p["counts"]["off_plan"] for p in stats["parts"]}
    assert day_parts["2030-03-07"] == 1 and day_parts["2030-03-05"] == 0


async def test_a_done_task_with_no_completion_time_gets_no_row(env: ProjectsEnv) -> None:
    s = Stats(env)
    await s.standard()
    await s.done("p9", "No time", None)
    await s.sync()
    assert await s.rows() == {}
    stats = await s.stats("week", WEEK)
    assert stats["total"] == 0 and stats["hidden"] == 0


async def test_a_task_deleted_in_the_task_app_keeps_its_row_but_is_not_counted(
    env: ProjectsEnv,
) -> None:
    s = Stats(env)
    await s.standard()
    await s.done("p9", "Stays", at(5))
    await s.done("p9", "Goes", at(5))
    await s.sync()
    assert (await s.stats("week", WEEK))["counts"]["off_plan"] == 2
    gone = next(i for i, t in s.backend.tasks.items() if t.title == "Goes")
    del s.backend.tasks[gone]
    await s.sync()
    assert (await s.stats("week", WEEK))["counts"]["off_plan"] == 1  # drops after the next sync
    assert set(await s.rows()) == {"Stays", "Goes"}  # the row stays
    assert await s.titles("off_plan") == ["Stays"]


async def test_two_completions_of_a_recurring_task_count_as_two_tasks(env: ProjectsEnv) -> None:
    s = Stats(env)
    await s.standard()
    # The task app makes a new task for each repeat: two tasks with the same title.
    for day in (4, 6):
        task = await s.backend.create_task(TaskDraft("p9", "Water plants"))
        s.backend.tasks[task.remote_id] = replace(task, done=True, done_at=at(day))
    await s.sync()
    stats = await s.stats("week", WEEK)
    assert stats["counts"]["off_plan"] == 2
    async with env.db() as db:
        assert len((await db.execute(select(TaskCategory))).scalars().all()) == 2


async def test_rows_are_made_for_tasks_only(env: ProjectsEnv) -> None:
    s = Stats(env)
    await s.standard()
    await s.done("p9", "A task", at(4))
    await s.sync()
    # A checklist item (planning checklists of the user) is not a task and gets no row.
    me = (await env.api.get(f"{V1}/auth/me")).json()
    await env.api.patch(f"{V1}/users/{me['id']}", json={})
    async with env.db() as db:
        tasks = (await db.execute(select(Task))).scalars().all()
        rows = (await db.execute(select(TaskCategory))).scalars().all()
    assert len(rows) == len(tasks) == 1


async def test_the_completion_day_follows_the_time_zone_of_the_user_at_the_first_sight(
    env: ProjectsEnv,
) -> None:
    s = Stats(env)
    await s.standard()
    me = (await env.api.get(f"{V1}/auth/me")).json()
    await env.api.patch(f"{V1}/users/{me['id']}", json={"timezone": "Europe/Athens"})
    sunday = datetime(2030, 3, 10, 22, 30, tzinfo=UTC)  # Monday 00:30 in Athens
    await s.done("p9", "Late Sunday", sunday)
    await s.sync()
    row = (await s.rows())["Late Sunday"]
    assert row.completed_on == date(2030, 3, 11)  # Monday, the next week
    assert (await s.stats("week", NEXT))["counts"]["off_plan"] == 1
    assert (await s.stats("week", WEEK))["counts"]["off_plan"] == 0
    # A later change of the time zone does not move the stored day.
    await env.api.patch(f"{V1}/users/{me['id']}", json={"timezone": "America/New_York"})
    await s.sync()
    assert (await s.rows())["Late Sunday"].completed_on == date(2030, 3, 11)
    assert (await s.stats("week", NEXT))["counts"]["off_plan"] == 1
    assert (await s.stats("week", NEXT - timedelta(days=14)))["total"] == 0


async def test_a_reopen_and_a_new_completion_in_the_same_second_is_a_new_completion(
    env: ProjectsEnv,
) -> None:
    """The cache keeps completion times in whole seconds, so two completions can look equal.

    The sync saw the task open in between, so the second completion is a new one: the row is
    replaced and decided with the project the task has now.
    """
    s = Stats(env)
    await s.standard()
    await s.done("p5", "Quick", at(5))  # Chores: maintenance
    await s.sync()
    first = (await s.rows())["Quick"]
    assert first.category == "maintenance"
    s.reopen("Quick")
    s.move("Quick", "p2")  # Open source: a theme
    await s.sync()  # seen open, in its new project
    s.finish("Quick", at(5))  # the very same completion time
    await s.sync()
    again = (await s.rows())["Quick"]
    assert again.id == first.id
    assert (again.category, again.reason, again.project_name) == (
        "off_plan",
        "theme",
        "Open source",
    )
    stats = await s.stats("week", WEEK)
    assert stats["counts"] == {"goal_aligned": 0, "maintenance": 0, "off_plan": 1}
    # A later sync that sees it done again changes nothing.
    before = await s.snapshot()
    await s.sync()
    assert await s.snapshot() == before
