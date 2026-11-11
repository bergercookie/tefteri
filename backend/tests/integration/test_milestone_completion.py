"""A milestone is done when its tasks are closed or dropped, with a done day and a theme."""

from datetime import UTC, datetime

from tefteri.domain.entities import Container
from tests.conftest import V1
from tests.integration.conftest import ProjectsEnv
from tests.integration.weekly_helpers import WEEK, Weekly


async def _setup(env: ProjectsEnv, tasks: dict[str, int]) -> Weekly:
    weekly = Weekly(env)
    await env.connect(
        Container("p2", "Open source"),
        Container("p3", "Login flow", "p2"),
        Container("p4", "Docs", "p2"),
        Container("p5", "Garden"),
        tasks=tasks,
    )
    await weekly.label(
        **{
            "Open source": "theme",
            "Login flow": "milestone",
            "Docs": "milestone",
            "Garden": "theme",
        }
    )
    return weekly


async def _milestone(weekly: Weekly, week, name: str) -> dict:  # type: ignore[no-untyped-def,type-arg]
    entry = (await weekly.entries(week))[name]
    r = await weekly.api.get(f"{V1}/milestones/{entry['milestone_id']}")
    assert r.status_code == 200, r.text
    body: dict = r.json()  # type: ignore[type-arg]
    return body


async def test_all_tasks_closed_makes_it_done_on_the_local_day_with_its_theme(
    env: ProjectsEnv,
) -> None:
    weekly = await _setup(env, {"p3": 2})
    admin = (await env.api.get(f"{V1}/auth/me")).json()
    await env.api.patch(f"{V1}/users/{admin['id']}", json={"timezone": "Europe/Athens"})
    await weekly.add(WEEK, "Login flow")
    await weekly.complete("p3 task 0")
    assert (await _milestone(weekly, WEEK, "Login flow"))["state"] == "active"  # one is open
    await weekly.complete("p3 task 1")
    done = await _milestone(weekly, WEEK, "Login flow")
    # 22:30 UTC is already the next day in Athens in March.
    assert (done["state"], done["done_on"], done["done_by"]) == ("done", "2030-03-07", "auto")
    assert done["done_theme_name"] == "Open source"
    entry = (await weekly.entries(WEEK))["Login flow"]
    assert entry["milestone_state"] == "done"


async def test_a_later_theme_change_never_changes_the_theme_at_done(env: ProjectsEnv) -> None:
    weekly = await _setup(env, {"p3": 1})
    await weekly.add(WEEK, "Login flow")
    await weekly.complete("p3 task 0")
    before = await _milestone(weekly, WEEK, "Login flow")
    assert before["state"] == "done" and before["done_theme_name"] == "Open source"
    backend = env.world.tasks["default"]
    backend.containers = [
        Container("p3", "Login flow", "p5") if c.remote_id == "p3" else c
        for c in backend.containers
    ]  # moved under Garden
    backend.containers = [
        Container("p2", "Open source renamed") if c.remote_id == "p2" else c
        for c in backend.containers
    ]
    await env.sync()
    after = await _milestone(weekly, WEEK, "Login flow")
    assert after["theme"]["name"] == "Garden"  # the live theme changed
    assert after["done_theme_name"] == "Open source"  # the one at done did not
    assert after["done_on"] == before["done_on"]


async def test_closed_and_dropped_is_done_and_only_dropped_or_no_task_is_not(
    env: ProjectsEnv,
) -> None:
    weekly = await _setup(env, {"p3": 2, "p4": 1})
    await weekly.add(WEEK, "Login flow")
    await weekly.add(WEEK, "Docs")
    await weekly.complete("p3 task 0")
    backend = env.world.tasks["default"]
    dropped = next(i for i, t in backend.tasks.items() if t.title == "p3 task 1")
    del backend.tasks[dropped]
    gone_docs = next(i for i, t in backend.tasks.items() if t.title == "p4 task 0")
    del backend.tasks[gone_docs]
    # A refresh of the project cannot tell a dropped task from one that moved away: it waits.
    await env.api.post(f"{V1}/weekly/{WEEK}/refresh")
    assert (await _milestone(weekly, WEEK, "Login flow"))["state"] == "active"
    await env.sync()  # a full sync: the task is gone for good
    assert (await _milestone(weekly, WEEK, "Login flow"))["state"] == "done"
    # Docs has only a dropped task: never done by itself.
    assert (await _milestone(weekly, WEEK, "Docs"))["state"] == "active"


async def test_a_milestone_with_no_task_is_never_done_automatically(env: ProjectsEnv) -> None:
    weekly = await _setup(env, {})
    await weekly.add(WEEK, "Login flow")
    await env.sync()
    assert (await _milestone(weekly, WEEK, "Login flow"))["state"] == "active"


async def test_marked_done_by_hand_keeps_the_open_tasks_and_uses_today(env: ProjectsEnv) -> None:
    weekly = await _setup(env, {"p3": 2})
    env.app.state.clock = lambda: datetime(2030, 3, 6, 12, tzinfo=UTC)
    await weekly.add(WEEK, "Login flow")
    milestone = await _milestone(weekly, WEEK, "Login flow")
    preview = await env.api.post(f"{V1}/milestones/{milestone['id']}/done", json={"dry_run": True})
    assert (
        preview.json()["open_tasks"] == 2
        and "Nothing is moved or deleted" in preview.json()["message"]
    )
    assert (await _milestone(weekly, WEEK, "Login flow"))["state"] == "active"  # nothing written
    done = await env.api.post(f"{V1}/milestones/{milestone['id']}/done", json={})
    assert done.status_code == 200, done.text
    body = done.json()
    assert body["open_tasks"] == 2 and "2 open tasks stay" in body["message"]
    assert (body["milestone"]["state"], body["milestone"]["done_by"]) == ("done", "user")
    assert body["milestone"]["done_on"] == "2030-03-06"
    open_tasks = [t for t in env.world.tasks["default"].tasks.values() if not t.done]
    assert len(open_tasks) == 2  # nothing was moved or deleted
    again = await env.api.post(f"{V1}/milestones/{milestone['id']}/done", json={})
    assert again.status_code == 422 and again.json()["code"] == "not_unfinished"
