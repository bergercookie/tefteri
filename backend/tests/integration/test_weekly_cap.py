"""The cap of three milestones is a warning on read, never a refusal (FR-005, FR-006)."""

from tefteri.domain.entities import Container
from tests.conftest import V1
from tests.integration.conftest import ProjectsEnv
from tests.integration.weekly_helpers import WEEK, Weekly


async def _setup(env: ProjectsEnv) -> Weekly:
    weekly = Weekly(env)
    await env.connect(
        Container("p2", "Open source"),
        Container("p3", "M1", "p2"),
        Container("p4", "M2", "p2"),
        Container("p5", "M3", "p2"),
        Container("p6", "M4", "p2"),
        Container("p7", "Chores"),
        Container("p8", "Mow", "p7"),
        tasks={"p3": 1, "p8": 2},
    )
    await weekly.label(**{"Open source": "theme", "Chores": "maintenance"})
    return weekly


async def test_a_fourth_milestone_is_accepted_and_warns(env: ProjectsEnv) -> None:
    weekly = await _setup(env)
    for name in ("M1", "M2", "M3"):
        state = await weekly.add(WEEK, name)
    assert (state["plan"]["milestone_count"], state["plan"]["over_cap"]) == (3, False)
    fourth = await weekly.add(WEEK, "M4")
    assert fourth["plan"]["milestone_count"] == 4
    assert fourth["plan"]["over_cap"] is True and fourth["plan"]["milestone_cap"] == 3
    committed = await env.api.post(f"{V1}/weekly/{WEEK}/commit")
    assert committed.status_code == 200  # the warning never blocks the commit
    assert committed.json()["plan"]["over_cap"] is True


async def test_a_remove_clears_the_warning(env: ProjectsEnv) -> None:
    weekly = await _setup(env)
    for name in ("M1", "M2", "M3", "M4"):
        state = await weekly.add(WEEK, name)
    assert state["plan"]["over_cap"] is True
    removed = await env.api.delete(
        f"{V1}/weekly/{WEEK}/projects/{state['plan']['projects'][0]['id']}"
    )
    plan = removed.json()["plan"]
    assert (plan["milestone_count"], plan["over_cap"]) == (3, False)


async def test_tasks_and_routine_projects_do_not_count(env: ProjectsEnv) -> None:
    weekly = await _setup(env)
    for name in ("M1", "M2", "M3"):
        await weekly.add(WEEK, name)
    refused = await weekly.try_add(WEEK, "Mow")  # inside a routine: never planned
    assert refused.status_code == 422
    plan = (await weekly.state(WEEK))["plan"]
    assert (plan["milestone_count"], plan["over_cap"]) == (3, False)
    # M1 has a task and Mow two, but only milestones are counted.
    assert sum(p["open_tasks"] for p in plan["projects"]) == 1


async def test_the_cap_does_not_block_creating_a_milestone(env: ProjectsEnv) -> None:
    weekly = await _setup(env)
    for name in ("M1", "M2", "M3", "M4"):
        await weekly.add(WEEK, name)
    created = await env.api.post(
        f"{V1}/weekly/{WEEK}/milestones",
        json={
            "parent_id": await weekly.cid("Open source"),
            "name": "M5",
            "done_state": "M5 is shipped",
        },
    )
    assert created.status_code == 201, created.text
    assert created.json()["plan"]["milestone_count"] == 5
