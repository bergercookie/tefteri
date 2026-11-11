"""The weekly milestone API end to end: picker, create, milestones, close, review, history."""

import uuid
from collections.abc import Awaitable, Callable
from datetime import UTC, date, datetime
from typing import Any

from httpx import AsyncClient
from sqlalchemy import select

from tefteri.db.models.project_label import ProjectLabel as ProjectLabelRow
from tefteri.db.models.user import User
from tefteri.db.models.weekly import WeeklyPlan, WeeklyPlanProject
from tefteri.db.session import session_scope
from tefteri.domain.entities import Container, TaskDraft
from tefteri.domain.enums import Capability
from tests.conftest import V1, connect_all
from tests.fakes.world import FakeWorld

WEEK = date(2030, 3, 4)
NEXT = date(2030, 3, 11)


async def _setup(api: AsyncClient, world: FakeWorld) -> dict[str, dict[str, Any]]:
    """Open source (theme) with Login flow and Docs (milestones), plus an unsorted Loose end."""
    backend = world.tasks["default"]
    backend.containers.extend(
        [
            Container("p2", "Open source"),
            Container("p3", "Login flow", "p2"),
            Container("p4", "Docs", "p2"),
            Container("p5", "Loose end"),
        ]
    )
    for project, count in (("p3", 3), ("p4", 2), ("p5", 1)):
        for n in range(count):
            await backend.create_task(TaskDraft(project, f"{project} task {n}"))
    await connect_all(api)
    await api.post(f"{V1}/sync")
    projects = await _projects(api)
    r = await api.put(
        f"{V1}/projects/labels",
        json={
            "changes": [
                {"id": projects["Open source"]["id"], "label": "theme"},
                {"id": projects["Login flow"]["id"], "label": "milestone"},
                {"id": projects["Docs"]["id"], "label": "milestone"},
            ]
        },
    )
    assert r.status_code == 200, r.text
    return projects


async def _projects(api: AsyncClient) -> dict[str, dict[str, Any]]:
    tree = (await api.get(f"{V1}/projects/classification")).json()
    return {p["name"]: p for c in tree["connections"] for p in c["projects"]}


async def _containers(api: AsyncClient, week: date = WEEK) -> dict[str, str]:
    found = (await api.get(f"{V1}/weekly/{week}/candidates")).json()
    themes = (await api.get(f"{V1}/weekly/{week}/themes")).json()["themes"]
    return {c["name"]: c["container_id"] for c in found} | {
        t["name"]: t["container_id"] for t in themes
    }


# -- the picker (T054) ------------------------------------------------------------------------


async def test_candidates_and_themes_have_the_contract_shape(
    api: AsyncClient, world: FakeWorld
) -> None:
    await _setup(api, world)
    found = {c["name"]: c for c in (await api.get(f"{V1}/weekly/{WEEK}/candidates")).json()}
    assert set(found) == {"Login flow", "Docs", "Loose end", "Inbox"}
    login = found["Login flow"]
    assert set(login) == {
        "container_id",
        "connection_id",
        "connection_name",
        "name",
        "path",
        "kind",
        "milestone_id",
        "done_state",
        "state",
        "theme",
        "in_focus",
        "rollover_count",
        "needs_rescope",
        "decision_open",
        "open_tasks",
        "carried_tasks",
        "selected",
        "unsorted",
    }
    assert (login["kind"], login["state"], login["in_focus"]) == ("milestone", "active", None)
    assert login["theme"]["name"] == "Open source" and login["open_tasks"] == 3
    assert found["Loose end"]["kind"] == "unsorted" and found["Loose end"]["theme"] is None
    themes = (await api.get(f"{V1}/weekly/{WEEK}/themes")).json()
    assert set(themes) == {"focus_known", "themes", "unsorted_count"}
    (theme,) = themes["themes"]
    assert theme["name"] == "Open source" and theme["milestones"] == 2
    assert set(theme) == {
        "id",
        "container_id",
        "connection_id",
        "name",
        "in_focus",
        "milestones",
        "open_milestones",
    }


async def test_adding_codes_privacy_and_no_cap_rejection(
    api: AsyncClient,
    world: FakeWorld,
    make_user: Callable[..., Awaitable[AsyncClient]],
) -> None:
    await _setup(api, world)
    ids = await _containers(api)
    theme = await api.post(
        f"{V1}/weekly/{WEEK}/projects", json={"container_id": ids["Open source"]}
    )
    assert theme.status_code == 422 and theme.json()["code"] == "not_a_milestone"
    for name in ("Login flow", "Docs", "Loose end", "Inbox"):
        r = await api.post(f"{V1}/weekly/{WEEK}/projects", json={"container_id": ids[name]})
        assert r.status_code == 201, (name, r.text)
    plan = r.json()["plan"]
    assert (plan["milestone_count"], plan["over_cap"], plan["milestone_cap"]) == (4, True, 3)
    other = await make_user("sam")
    foreign = await other.post(f"{V1}/weekly/{WEEK}/projects", json={"container_id": ids["Docs"]})
    assert foreign.status_code == 404
    assert (await other.get(f"{V1}/weekly/{WEEK}/candidates")).json() == []
    assert (await other.get(f"{V1}/weekly/{WEEK}/themes")).json()["themes"] == []
    projects = await _projects(api)
    await api.put(
        f"{V1}/projects/labels",
        json={"changes": [{"id": projects["Docs"]["id"], "label": "ignored"}]},
    )
    await api.delete(f"{V1}/weekly/{WEEK}/projects/{plan['projects'][1]['id']}")
    ignored = await api.post(f"{V1}/weekly/{WEEK}/projects", json={"container_id": ids["Docs"]})
    assert ignored.status_code == 422 and ignored.json()["code"] == "not_eligible"


# -- creating a milestone (T055) --------------------------------------------------------------


async def test_creating_a_milestone_and_its_failures(
    api: AsyncClient,
    world: FakeWorld,
    make_user: Callable[..., Awaitable[AsyncClient]],
) -> None:
    await _setup(api, world)
    ids = await _containers(api)
    body = {"parent_id": ids["Open source"], "name": "Passkeys", "done_state": "Sign in works"}
    r = await api.post(f"{V1}/weekly/{WEEK}/milestones", json=body)
    assert r.status_code == 201, r.text
    entry = r.json()["plan"]["projects"][0]
    assert (entry["name"], entry["done_state"], entry["milestone_state"]) == (
        "Passkeys",
        "Sign in works",
        "active",
    )
    blank = await api.post(f"{V1}/weekly/{WEEK}/milestones", json={**body, "done_state": " "})
    assert blank.status_code == 422 and blank.json()["code"] == "done_state_required"
    other = await make_user("sam")
    assert (await other.post(f"{V1}/weekly/{WEEK}/milestones", json=body)).status_code == 404
    backend = world.tasks["default"]
    before = len(backend.containers)
    backend.supported.discard(Capability.SUBPROJECTS)
    unsupported = await api.post(f"{V1}/weekly/{WEEK}/milestones", json={**body, "name": "B"})
    assert unsupported.status_code == 409 and unsupported.json()["code"] == "not_supported"
    backend.supported.add(Capability.SUBPROJECTS)
    backend.unavailable = True
    down = await api.post(f"{V1}/weekly/{WEEK}/milestones", json={**body, "name": "C"})
    backend.unavailable = False
    assert down.status_code == 502 and "connection" in down.json()
    assert len(backend.containers) == before
    assert {"B", "C"}.isdisjoint((await _projects(api)).keys())  # nothing recorded
    old = await api.post(
        f"{V1}/weekly/{WEEK}/subprojects", json={"parent_id": ids["Open source"], "name": "x"}
    )
    assert old.status_code == 404


# -- the milestone routes (T056) --------------------------------------------------------------


async def _milestone_id(api: AsyncClient, name: str = "Login flow") -> str:
    ids = await _containers(api)
    state = (
        await api.post(f"{V1}/weekly/{WEEK}/projects", json={"container_id": ids[name]})
    ).json()
    entry = next(p for p in state["plan"]["projects"] if p["name"] == name)
    return str(entry["milestone_id"])


async def test_get_and_patch_a_milestone(
    api: AsyncClient,
    world: FakeWorld,
    make_user: Callable[..., Awaitable[AsyncClient]],
) -> None:
    await _setup(api, world)
    milestone = await _milestone_id(api)
    got = (await api.get(f"{V1}/milestones/{milestone}")).json()
    assert set(got) == {
        "id",
        "project_id",
        "name",
        "done_state",
        "state",
        "theme",
        "rollover_count",
        "needs_rescope",
        "done_on",
        "done_theme_name",
        "done_by",
        "orphaned",
        "rollovers",
        "open_tasks",
        "can_close",
        "last_closure",
    }
    assert (got["name"], got["state"], got["done_state"], got["open_tasks"]) == (
        "Login flow",
        "active",
        None,
        3,
    )
    assert got["can_close"] == {"available": True, "reason": None}
    patched = await api.patch(
        f"{V1}/milestones/{milestone}", json={"done_state": " Sign in works "}
    )
    assert patched.status_code == 200 and patched.json()["done_state"] == "Sign in works"
    blank = await api.patch(f"{V1}/milestones/{milestone}", json={"done_state": "  "})
    assert blank.status_code == 422 and blank.json()["code"] == "done_state_required"
    other = await make_user("sam")
    assert (await other.get(f"{V1}/milestones/{milestone}")).status_code == 404
    assert (
        await other.patch(f"{V1}/milestones/{milestone}", json={"done_state": "x"})
    ).status_code == 404
    unknown = uuid.uuid4()
    assert (await api.get(f"{V1}/milestones/{unknown}")).status_code == 404


async def test_close_codes_and_the_partial_failure_body(api: AsyncClient, world: FakeWorld) -> None:
    await _setup(api, world)
    milestone = await _milestone_id(api)
    close = f"{V1}/milestones/{milestone}/close"
    dry = await api.post(close, json={"dry_run": True})
    assert dry.status_code == 200
    assert set(dry.json()) == {"open_tasks", "theme", "message"} and dry.json()["open_tasks"] == 3
    needs = await api.post(close, json={})
    assert needs.status_code == 422 and needs.json()["code"] == "confirm_required"
    backend = world.tasks["default"]
    backend.moves_allowed = 1
    failed = await api.post(close, json={"confirm": True})
    assert failed.status_code == 502
    body = failed.json()
    assert (body["remaining"], len(body["moved"])) == (2, 1)
    assert set(body["moved"][0]) == {"task_id", "title"} and "connection" in body
    backend.moves_allowed = None
    done = await api.post(close, json={"confirm": True})
    assert done.status_code == 200, done.text
    assert set(done.json()) == {"milestone", "moved", "closure_id"} and done.json()["moved"] == 3
    again = await api.post(close, json={"confirm": True})
    assert again.status_code == 422 and again.json()["code"] == "not_unfinished"
    reopened = await api.post(f"{V1}/milestones/{milestone}/reopen")
    assert reopened.status_code == 200
    assert set(reopened.json()) == {"milestone", "moved_back", "not_moved_back"}
    assert reopened.json()["moved_back"] == 3 and reopened.json()["milestone"]["state"] == "active"
    nothing = await api.post(f"{V1}/milestones/{milestone}/reopen")
    assert nothing.status_code == 422 and nothing.json()["code"] == "invalid"


async def test_close_without_a_theme_or_the_capability(api: AsyncClient, world: FakeWorld) -> None:
    await _setup(api, world)
    loose = await _milestone_id(api, "Loose end")
    no_theme = await api.post(f"{V1}/milestones/{loose}/close", json={"confirm": True})
    assert no_theme.status_code == 422 and no_theme.json()["code"] == "no_theme"
    milestone = await _milestone_id(api)
    world.tasks["default"].supported.discard(Capability.MOVE_TASKS)
    unsupported = await api.post(f"{V1}/milestones/{milestone}/close", json={"confirm": True})
    assert unsupported.status_code == 409 and unsupported.json()["code"] == "not_supported"
    done = await api.post(f"{V1}/milestones/{milestone}/done", json={})
    assert done.status_code == 200 and done.json()["milestone"]["state"] == "done"
    closed = await api.post(f"{V1}/milestones/{milestone}/close", json={"dry_run": True})
    assert closed.status_code == 422 and closed.json()["code"] == "not_unfinished"


# -- the review and the history (T057) --------------------------------------------------------


async def _committed_week(api: AsyncClient) -> None:
    ids = await _containers(api)
    for name in ("Login flow", "Docs", "Loose end"):
        await api.post(f"{V1}/weekly/{WEEK}/projects", json={"container_id": ids[name]})
    await api.post(f"{V1}/weekly/{WEEK}/spread")
    assert (await api.post(f"{V1}/weekly/{WEEK}/commit")).status_code == 200


async def test_review_decisions_notices_and_history(api: AsyncClient, world: FakeWorld) -> None:
    await _setup(api, world)
    await _committed_week(api)
    back = (await api.get(f"{V1}/weekly/{NEXT}")).json()["look_back"]
    assert set(back) == {"plan_id", "week_start", "reviewed", "reflection", "summary", "projects"}
    assert set(back["summary"]) == {
        "committed_tasks",
        "done_tasks",
        "milestones_committed",
        "milestones_done",
        "pace",
        "focus_share",
        "note",
    }
    ids = {p["name"]: p["id"] for p in back["projects"]}
    review = f"{V1}/weekly/reviews/{back['plan_id']}"
    bad = await api.post(
        review, json={"projects": [{"plan_project_id": ids["Docs"], "leftover": "carry"}]}
    )
    assert bad.status_code == 422
    done = await api.post(
        review,
        json={
            "projects": [
                {"plan_project_id": ids["Login flow"], "decision": "recommit", "expected": True},
                {"plan_project_id": ids["Docs"], "mark_done": True},
            ],
            "reflection": "ok",
        },
    )
    assert done.status_code == 200, done.text
    body = done.json()
    assert set(body) == {"entries", "totals", "notices", "nudges"}
    assert any("stay" in n for n in body["notices"]) and body["nudges"] == []
    entry = body["entries"][0]
    by_name = {p["name"]: p for p in entry["projects"]}
    assert (by_name["Login flow"]["decision"], by_name["Docs"]["decision"]) == ("recommit", None)
    assert by_name["Loose end"]["decision"] == "decide_later"  # a missing decision
    assert by_name["Docs"]["done"] is True and by_name["Docs"]["done_on"] is not None
    assert by_name["Login flow"]["rollover_count"] == 1
    assert set(by_name["Login flow"]) == {
        "name",
        "done",
        "decision",
        "legacy",
        "milestone_id",
        "theme_name",
        "done_on",
        "rollover_count",
    }
    state = (await api.get(f"{V1}/weekly/{NEXT}")).json()
    assert [p["name"] for p in state["plan"]["projects"]] == ["Login flow"]


async def test_history_shows_an_old_week_under_the_new_names(
    api: AsyncClient, world: FakeWorld
) -> None:
    await _setup(api, world)
    app: Any = api.app  # type: ignore[attr-defined]
    async with session_scope(app.state.session_factory) as db:
        user = (await db.execute(select(User).where(User.username == "admin"))).scalar_one()
        plan = WeeklyPlan(
            user_id=user.id,
            week_start=date(2026, 11, 2),
            status="committed",
            committed_at=datetime(2026, 11, 2, tzinfo=UTC),
            reviewed_at=datetime(2026, 11, 9, tzinfo=UTC),
            reflection="",
            retro_skipped=False,
        )
        db.add(plan)
        await db.flush()
        for n, action in enumerate(("carry", "backlog")):
            db.add(
                WeeklyPlanProject(
                    plan_id=plan.id,
                    name=f"Old {action}",
                    position=n,
                    created_here=False,
                    committed_task_ids=[],
                    outcome="not_done",
                    leftover_action=action,
                    reviewed_committed=1,
                    reviewed_done=0,
                )
            )
        labels = (await db.execute(select(ProjectLabelRow.label))).scalars().all()
    history = (await api.get(f"{V1}/weekly/history")).json()
    shown = {p["name"]: (p["decision"], p["legacy"]) for p in history["entries"][0]["projects"]}
    assert shown == {"Old carry": ("recommit", True), "Old backlog": ("park", True)}
    async with session_scope(app.state.session_factory) as db:
        assert (await db.execute(select(ProjectLabelRow.label))).scalars().all() == labels
