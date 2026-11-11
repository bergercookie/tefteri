"""Close and return tasks to the parent theme, and undo it by reopening (FR-026, FR-027, FR-037)."""

from dataclasses import replace
from typing import Any

from sqlalchemy import select

from tefteri.db.models.milestone import MilestoneClosure
from tefteri.db.models.task import Task
from tefteri.domain.entities import Container
from tefteri.domain.enums import Capability
from tests.conftest import V1
from tests.integration.conftest import ProjectsEnv
from tests.integration.weekly_helpers import WEEK, Weekly


async def _setup(env: ProjectsEnv, tasks: int = 5) -> tuple[Weekly, str]:
    weekly = Weekly(env)
    await env.connect(
        Container("p2", "Open source"),
        Container("p3", "Login flow", "p2"),
        Container("p4", "Loose end"),
        tasks={"p3": tasks, "p4": 1},
    )
    await weekly.label(
        **{"Open source": "theme", "Login flow": "milestone", "Loose end": "milestone"}
    )
    entry = (await weekly.add(WEEK, "Login flow"))["plan"]["projects"][0]
    return weekly, str(entry["milestone_id"])


def _remote_containers(env: ProjectsEnv) -> dict[str, str]:
    return {t.title: t.container_id for t in env.world.tasks["default"].tasks.values()}


async def _close(weekly: Weekly, milestone: str, **body: Any):  # type: ignore[no-untyped-def]
    return await weekly.api.post(f"{V1}/milestones/{milestone}/close", json=body)


async def test_a_dry_run_says_the_count_and_the_theme_and_moves_nothing(env: ProjectsEnv) -> None:
    weekly, milestone = await _setup(env)
    before = _remote_containers(env)
    r = await _close(weekly, milestone, dry_run=True)
    assert r.status_code == 200, r.text
    assert r.json()["open_tasks"] == 5 and r.json()["theme"]["name"] == "Open source"
    assert r.json()["message"] == "5 open tasks will move to Open source."
    assert _remote_containers(env) == before
    assert (await weekly.api.get(f"{V1}/milestones/{milestone}")).json()["state"] == "active"
    neither = await _close(weekly, milestone)
    assert neither.status_code == 422 and neither.json()["code"] == "confirm_required"
    assert _remote_containers(env) == before


async def test_a_confirmed_close_moves_every_open_task_then_closes(env: ProjectsEnv) -> None:
    weekly, milestone = await _setup(env)
    r = await _close(weekly, milestone, confirm=True)
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["moved"] == 5 and body["milestone"]["state"] == "closed"
    assert body["milestone"]["last_closure"]["status"] == "closed"
    moved = {t: c for t, c in _remote_containers(env).items() if t.startswith("p3 task")}
    assert set(moved.values()) == {"p2"}  # in the theme, in the task app
    async with env.db() as db:
        tasks = (await db.execute(select(Task).where(Task.title.like("p3 task%")))).scalars().all()
        containers = {t.container_id for t in tasks}
        assert len(containers) == 1  # in the local copy too
    entry = (await weekly.entries(WEEK))["Login flow"]
    assert entry["open_tasks"] == 0 and entry["milestone_state"] == "closed"
    assert "Login flow" not in await weekly.candidates(WEEK)  # a closed one is not offered
    assert (await _close(weekly, milestone, confirm=True)).json()["code"] == "not_unfinished"


async def test_a_failure_part_way_keeps_the_moved_tasks_and_a_retry_finishes_the_rest(
    env: ProjectsEnv,
) -> None:
    weekly, milestone = await _setup(env)
    backend = env.world.tasks["default"]
    backend.moves_allowed = 2  # the third move fails
    failed = await _close(weekly, milestone, confirm=True)
    assert failed.status_code == 502, failed.text
    body = failed.json()
    assert body["code"] == "backend_unavailable" and body["remaining"] == 3
    assert "2 of 5 tasks already moved to Open source" in body["detail"]
    assert "Nothing was changed" not in body["detail"]
    assert len(body["moved"]) == 2 and all(m["title"].startswith("p3 task") for m in body["moved"])
    assert (await weekly.api.get(f"{V1}/milestones/{milestone}")).json()["state"] == "active"
    in_theme = [t for t, c in _remote_containers(env).items() if c == "p2"]
    assert len(in_theme) == 2
    async with env.db() as db:  # the log survived the failure
        (closure,) = (await db.execute(select(MilestoneClosure))).scalars()
        assert closure.status == "moving" and len(closure.moved) == 2
    backend.moves_allowed = None
    calls: list[str] = []
    original = backend.move_task

    async def counting(remote_id, container, expected_version):  # type: ignore[no-untyped-def]
        calls.append(remote_id)
        return await original(remote_id, container, expected_version)

    backend.move_task = counting  # type: ignore[method-assign]
    done = await _close(weekly, milestone, confirm=True)
    assert done.status_code == 200, done.text
    assert len(calls) == 3  # only the tasks that were left
    assert done.json()["moved"] == 5 and done.json()["milestone"]["state"] == "closed"
    async with env.db() as db:
        closures = (await db.execute(select(MilestoneClosure))).scalars().all()
        assert len(closures) == 1 and closures[0].status == "closed"


async def test_close_is_refused_without_a_usable_theme_or_without_the_capability(
    env: ProjectsEnv,
) -> None:
    weekly, milestone = await _setup(env)
    loose = (await weekly.add(WEEK, "Loose end"))["plan"]["projects"][1]["milestone_id"]
    no_theme = await _close(weekly, loose, confirm=True)
    assert no_theme.status_code == 422 and no_theme.json()["code"] == "no_theme"
    info = (await weekly.api.get(f"{V1}/milestones/{loose}")).json()
    assert info["can_close"] == {"available": False, "reason": "no_theme"}
    await weekly.label(**{"Open source": "ignored"})
    ignored = await _close(weekly, milestone, dry_run=True)
    assert ignored.status_code == 422 and ignored.json()["code"] == "no_theme"
    back = (await weekly.api.get(f"{V1}/milestones/{milestone}")).json()
    assert back["can_close"]["reason"] in ("no_theme", "theme_unusable")
    await weekly.label(**{"Open source": "theme"})
    env.world.tasks["default"].supported.discard(Capability.MOVE_TASKS)
    unsupported = await _close(weekly, milestone, confirm=True)
    assert unsupported.status_code == 409 and unsupported.json()["code"] == "not_supported"
    can = (await weekly.api.get(f"{V1}/milestones/{milestone}")).json()["can_close"]
    assert can == {"available": False, "reason": "not_supported"}
    assert _remote_containers(env)["p3 task 0"] == "p3"


async def test_an_orphaned_theme_hides_the_close_option(env: ProjectsEnv) -> None:
    weekly, milestone = await _setup(env)
    backend = env.world.tasks["default"]
    backend.containers = [c for c in backend.containers if c.remote_id != "p2"]
    backend.containers = [
        Container("p3", "Login flow", None) if c.remote_id == "p3" else c
        for c in backend.containers
    ]
    await env.sync()
    r = await _close(weekly, milestone, confirm=True)
    assert r.status_code == 422 and r.json()["code"] == "no_theme"
    assert _remote_containers(env)["p3 task 0"] == "p3"


async def test_reopen_moves_back_what_is_unchanged_and_lists_the_rest(env: ProjectsEnv) -> None:
    weekly, milestone = await _setup(env)
    await _close(weekly, milestone, confirm=True)
    backend = env.world.tasks["default"]
    edited = next(i for i, t in backend.tasks.items() if t.title == "p3 task 0")
    backend.edit_remotely(edited, "p3 task 0 (edited)")
    moved_again = next(i for i, t in backend.tasks.items() if t.title == "p3 task 1")
    backend.tasks[moved_again] = replace(
        backend.tasks[moved_again], container_id="p4", version="moved-elsewhere"
    )
    await env.sync()
    r = await weekly.api.post(f"{V1}/milestones/{milestone}/reopen")
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["milestone"]["state"] == "active" and body["moved_back"] == 3
    reasons = {n["title"]: n["reason"] for n in body["not_moved_back"]}
    assert reasons == {"p3 task 0 (edited)": "changed", "p3 task 1": "moved"}
    containers = _remote_containers(env)
    assert [containers[f"p3 task {n}"] for n in (2, 3, 4)] == ["p3", "p3", "p3"]
    assert containers["p3 task 0 (edited)"] == "p2"  # it stays where it is now
    again = await weekly.api.post(f"{V1}/milestones/{milestone}/reopen")
    assert again.status_code == 422  # it is active already
    assert "Login flow" in await weekly.candidates(WEEK)


async def test_reopen_never_fails_when_the_task_app_is_down(env: ProjectsEnv) -> None:
    weekly, milestone = await _setup(env, tasks=2)
    await _close(weekly, milestone, confirm=True)
    env.world.tasks["default"].unavailable = True
    r = await weekly.api.post(f"{V1}/milestones/{milestone}/reopen")
    env.world.tasks["default"].unavailable = False
    assert r.status_code == 200, r.text
    assert r.json()["milestone"]["state"] == "active" and r.json()["moved_back"] == 0
    assert {n["reason"] for n in r.json()["not_moved_back"]} == {"failed"}


async def test_a_milestone_done_by_hand_reopens_with_its_done_fields_cleared(
    env: ProjectsEnv,
) -> None:
    weekly, milestone = await _setup(env, tasks=2)
    done = await weekly.api.post(f"{V1}/milestones/{milestone}/done", json={})
    assert done.json()["milestone"]["state"] == "done"
    r = await weekly.api.post(f"{V1}/milestones/{milestone}/reopen")
    assert r.status_code == 200, r.text
    reopened = r.json()["milestone"]
    assert reopened["state"] == "active"
    assert (reopened["done_on"], reopened["done_by"], reopened["done_theme_name"]) == (
        None,
        None,
        None,
    )
    assert _remote_containers(env)["p3 task 0"] == "p3"  # nothing moved
