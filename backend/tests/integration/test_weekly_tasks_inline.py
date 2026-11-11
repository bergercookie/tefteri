"""Tasks are added under a milestone of the plan, and unpicked tasks stay as they are (FR-012)."""

from datetime import timedelta

from tefteri.domain.entities import Container
from tefteri.domain.enums import Capability
from tests.conftest import V1
from tests.integration.conftest import ProjectsEnv
from tests.integration.weekly_helpers import WEEK, Weekly


async def _setup(env: ProjectsEnv) -> Weekly:
    weekly = Weekly(env)
    await env.connect(
        Container("p2", "Open source"), Container("p3", "Login flow", "p2"), tasks={"p3": 2}
    )
    await weekly.label(**{"Open source": "theme", "Login flow": "milestone"})
    return weekly


async def _add_task(weekly: Weekly, entry_id: str, title: str = "Draw the screens"):  # type: ignore[no-untyped-def]
    return await weekly.api.post(
        f"{V1}/weekly/{WEEK}/projects/{entry_id}/tasks", json={"title": title}
    )


async def test_a_task_added_under_a_milestone_is_in_the_task_app_and_the_plan(
    env: ProjectsEnv,
) -> None:
    weekly = await _setup(env)
    state = await weekly.add(WEEK, "Login flow")
    entry = state["plan"]["projects"][0]
    r = await _add_task(weekly, entry["id"])
    assert r.status_code == 201, r.text
    shown = r.json()["plan"]["projects"][0]
    assert sorted(t["title"] for t in shown["tasks"]) == [
        "Draw the screens",
        "p3 task 0",
        "p3 task 1",
    ]
    created = [
        t for t in env.world.tasks["default"].tasks.values() if t.title == "Draw the screens"
    ]
    assert [t.container_id for t in created] == ["p3"]  # under the milestone, in the task app


async def test_a_new_task_is_not_committed_until_it_has_a_day(env: ProjectsEnv) -> None:
    weekly = await _setup(env)
    entry = (await weekly.add(WEEK, "Login flow"))["plan"]["projects"][0]
    await _add_task(weekly, entry["id"])
    for title in ("p3 task 0", "p3 task 1"):
        task = await weekly.task(title)
        day = str(WEEK + timedelta(days=1))
        await weekly.api.put(f"{V1}/tasks/{task['id']}/schedule", json={"date": day})
    committed = (await weekly.api.post(f"{V1}/weekly/{WEEK}/commit")).json()["plan"]["projects"][0]
    titles = {t["title"] for t in committed["committed_tasks"]}
    assert "p3 task 0" in titles and "p3 task 1" in titles
    assert "Draw the screens" not in titles  # it has no day, so it is not committed
    again = await _add_task(weekly, entry["id"], "Too late")
    assert again.status_code == 422  # a committed plan refuses it


async def test_unpicked_tasks_stay_unchanged_in_the_task_app(env: ProjectsEnv) -> None:
    weekly = await _setup(env)
    entry = (await weekly.add(WEEK, "Login flow"))["plan"]["projects"][0]
    aside = entry["tasks"][0]
    r = await weekly.api.put(
        f"{V1}/weekly/{WEEK}/tasks/{aside['id']}/parked", json={"parked": True}
    )
    assert r.status_code == 200, r.text
    before = {t.remote_id: t for t in env.world.tasks["default"].tasks.values()}
    await weekly.api.post(f"{V1}/weekly/{WEEK}/spread")
    committed = (await weekly.api.post(f"{V1}/weekly/{WEEK}/commit")).json()["plan"]["projects"][0]
    assert aside["id"] not in {t["id"] for t in committed["committed_tasks"]}
    assert committed["parked_tasks"] == 1
    remote = env.world.tasks["default"].tasks
    unpicked = next(t for t in before.values() if t.title == aside["title"])
    assert remote[unpicked.remote_id] == unpicked  # not touched: not even a day


async def test_blank_titles_unknown_entries_and_missing_support_are_refused(
    env: ProjectsEnv,
) -> None:
    weekly = await _setup(env)
    entry = (await weekly.add(WEEK, "Login flow"))["plan"]["projects"][0]
    assert (await _add_task(weekly, entry["id"], "   ")).status_code == 422
    unknown = await _add_task(weekly, "00000000-0000-0000-0000-000000000000")
    assert unknown.status_code == 404
    env.world.tasks["default"].supported.discard(Capability.CREATE_TASKS)
    unsupported = await _add_task(weekly, entry["id"])
    assert unsupported.status_code == 409 and unsupported.json()["code"] == "not_supported"
    env.world.tasks["default"].supported.add(Capability.CREATE_TASKS)
    env.world.tasks["default"].unavailable = True
    assert (await _add_task(weekly, entry["id"])).status_code == 502
    env.world.tasks["default"].unavailable = False
    assert not [
        t for t in env.world.tasks["default"].tasks.values() if t.title == "Draw the screens"
    ]
