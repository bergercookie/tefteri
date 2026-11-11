"""The weekly picker lists only weekly-eligible projects (spec 003, FR-007, FR-008, FR-025)."""

from datetime import date

from httpx import AsyncClient

from tefteri.domain.entities import Container
from tefteri.domain.enums import ProjectLabel
from tefteri.services.classification import Change
from tests.conftest import V1
from tests.integration.conftest import ProjectsEnv

WEEK = date(2030, 3, 4)


async def _label(env: ProjectsEnv, **labels: ProjectLabel | None) -> None:
    rows = await env.rows()
    async with env.db() as db:
        await env.classification.save(
            db, await env.user_id(), [Change(rows[n].id, label) for n, label in labels.items()]
        )


async def _candidates(api: AsyncClient) -> dict[str, dict[str, object]]:
    r = await api.get(f"{V1}/weekly/{WEEK}/candidates")
    assert r.status_code == 200, r.text
    return {c["name"]: c for c in r.json()}


async def test_ignored_projects_their_descendants_and_maintenance_are_not_listed(
    env: ProjectsEnv,
) -> None:
    await env.connect(
        Container("p2", "Archive stuff"),
        Container("p3", "Old plans", "p2"),
        Container("p4", "Chores"),
        Container("p5", "Release", "p4"),
        Container("p6", "Website"),
        tasks={"p3": 1, "p5": 1, "p6": 1},
    )
    await _label(
        env,
        **{
            "Archive stuff": ProjectLabel.IGNORED,
            "Chores": ProjectLabel.MAINTENANCE,
            "Website": ProjectLabel.THEME,
        },
    )
    found = await _candidates(env.api)
    # Ignored, what is inside an ignored project, and maintenance are out. A project inside a
    # maintenance project is judged on its own label.
    assert set(found) == {"Inbox", "Release", "Website"}


async def test_unclassified_projects_are_listed_and_marked_unsorted(env: ProjectsEnv) -> None:
    await env.connect(Container("p2", "Website"))
    await _label(env, Website=ProjectLabel.THEME)
    found = await _candidates(env.api)
    assert found["Website"]["unsorted"] is False
    assert found["Inbox"]["unsorted"] is True  # still listed: unsorted never blocks planning


async def test_a_project_can_be_picked_again_after_the_label_changes(env: ProjectsEnv) -> None:
    await env.connect(Container("p2", "Website"))
    await _label(env, Website=ProjectLabel.IGNORED)
    assert "Website" not in await _candidates(env.api)
    await _label(env, Website=ProjectLabel.MILESTONE)
    assert "Website" in await _candidates(env.api)


async def test_maintenance_tasks_stay_in_the_planner_and_the_daily_lists(
    env: ProjectsEnv,
) -> None:
    await env.connect(Container("p2", "Chores"), tasks={"p2": 1})
    await _label(env, Chores=ProjectLabel.MAINTENANCE)
    assert "Chores" not in await _candidates(env.api)
    tasks = (await env.api.get(f"{V1}/tasks", params={"due": "all"})).json()
    (task,) = [t for t in tasks if t["title"] == "p2 task 0"]
    planned = await env.api.put(f"{V1}/tasks/{task['id']}/schedule", json={"date": str(WEEK)})
    assert planned.status_code == 200, planned.text
    day = (await env.api.get(f"{V1}/views/day/{WEEK}")).json()
    assert "p2 task 0" in {t["title"] for t in day["tasks"]}
    week = (await env.api.get(f"{V1}/views/week/{WEEK}")).json()
    assert "p2 task 0" in {t["title"] for t in week["tasks"]}


async def test_an_empty_picker_is_possible_and_the_unsorted_count_is_in_the_tree(
    env: ProjectsEnv,
) -> None:
    await env.connect()
    await _label(env, Inbox=ProjectLabel.IGNORED)
    assert await _candidates(env.api) == {}
    async with env.db() as db:
        tree = await env.classification.tree(db, await env.user_id())
    assert tree.unsorted_count == 0
