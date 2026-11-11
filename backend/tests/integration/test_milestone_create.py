"""A milestone is created under a theme with a done-state (FR-009 to FR-011)."""

from httpx import Response
from sqlalchemy import select

from tefteri.db.models.milestone import Milestone
from tefteri.db.models.weekly import WeeklyPlanProject
from tefteri.domain.entities import Container
from tefteri.domain.enums import Capability
from tests.conftest import V1
from tests.integration.conftest import ProjectsEnv
from tests.integration.weekly_helpers import WEEK, Weekly


async def _setup(env: ProjectsEnv) -> Weekly:
    weekly = Weekly(env)
    await env.connect(Container("p2", "Open source"))
    await weekly.label(**{"Open source": "theme"})
    return weekly


async def _create(
    weekly: Weekly, done_state: str = "Users sign in with a passkey", name: str = "Login flow"
) -> Response:
    return await weekly.api.post(
        f"{V1}/weekly/{WEEK}/milestones",
        json={"parent_id": await weekly.cid("Open source"), "name": name, "done_state": done_state},
    )


async def test_a_new_milestone_is_in_the_task_app_labelled_and_in_the_plan(
    env: ProjectsEnv,
) -> None:
    weekly = await _setup(env)
    r = await _create(weekly)
    assert r.status_code == 201, r.text
    (entry,) = r.json()["plan"]["projects"]
    assert entry["name"] == "Login flow" and entry["done_state"] == "Users sign in with a passkey"
    assert (entry["milestone_state"], entry["created_here"]) == ("active", True)
    assert entry["theme"]["name"] == "Open source"
    created = env.world.tasks["default"].containers[-1]
    assert (created.name, created.parent_id) == ("Login flow", "p2")
    assert (await env.rows())["Login flow"].label == "milestone"
    assert [(h.label, h.source) for h in await env.history("Login flow")] == [("milestone", "user")]
    async with env.db() as db:
        (milestone,) = (await db.execute(select(Milestone))).scalars()
        assert milestone.done_state == "Users sign in with a passkey"
        assert milestone.state == "active" and milestone.rollover_count == 0
    # The done-state is shown wherever the milestone is shown (FR-011).
    found = await weekly.candidates(WEEK)
    assert found["Login flow"]["done_state"] == "Users sign in with a passkey"
    assert found["Login flow"]["selected"] is True


async def test_a_blank_done_state_is_refused_before_the_task_app_is_called(
    env: ProjectsEnv,
) -> None:
    weekly = await _setup(env)
    before = len(env.world.tasks["default"].containers)
    for blank in ("", "   "):
        r = await _create(weekly, done_state=blank)
        assert r.status_code == 422 and r.json()["code"] == "done_state_required"
        assert "ship the login flow" in r.json()["detail"]  # the hint has an example
    env.world.tasks["default"].unavailable = True  # the task app would fail, but it is not called
    r = await _create(weekly, done_state="")
    assert r.status_code == 422 and r.json()["code"] == "done_state_required"
    assert len(env.world.tasks["default"].containers) == before
    env.world.tasks["default"].unavailable = False
    async with env.db() as db:
        assert (await db.execute(select(Milestone))).scalars().all() == []


async def test_a_task_app_failure_records_nothing(env: ProjectsEnv) -> None:
    weekly = await _setup(env)
    backend = env.world.tasks["default"]
    backend.unavailable = True
    down = await _create(weekly)
    assert down.status_code == 502
    backend.unavailable = False
    backend.supported.discard(Capability.SUBPROJECTS)
    unsupported = await _create(weekly)
    assert unsupported.status_code == 409 and unsupported.json()["code"] == "not_supported"
    backend.supported.add(Capability.SUBPROJECTS)
    assert "Login flow" not in await env.rows()  # no label row, no history entry
    async with env.db() as db:
        assert (await db.execute(select(Milestone))).scalars().all() == []
        assert (await db.execute(select(WeeklyPlanProject))).scalars().all() == []
    assert not (await weekly.entries(WEEK))


async def test_a_parent_that_is_not_a_theme_is_refused(env: ProjectsEnv) -> None:
    weekly = await _setup(env)
    await weekly.label(**{"Open source": "maintenance"})
    r = await _create(weekly)
    assert r.status_code == 422 and r.json()["code"] == "invalid"
    unknown = await weekly.api.post(
        f"{V1}/weekly/{WEEK}/milestones",
        json={
            "parent_id": "00000000-0000-0000-0000-000000000000",
            "name": "x",
            "done_state": "x",
        },
    )
    assert unknown.status_code == 404
