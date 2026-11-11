"""The weekly planning workflow: choose projects, give tasks a day, commit, look back."""

from collections.abc import Awaitable, Callable
from dataclasses import replace
from datetime import UTC, date, datetime, timedelta
from typing import Any

from httpx import AsyncClient

from tefteri.domain.entities import Container, TaskDraft
from tefteri.domain.enums import Capability
from tests.conftest import V1, connect_all
from tests.fakes.world import FakeWorld

FUTURE = date(2030, 3, 4)  # a Monday, later than any "today" the tests run on
PAST = date(2026, 11, 2)  # a Monday that has passed
NEXT_AFTER_PAST = date(2026, 11, 9)


async def _setup(api: AsyncClient, world: FakeWorld) -> dict[str, str]:
    """Connect the apps with four projects, two tasks each in the first three."""
    backend = world.tasks["default"]
    backend.containers.extend(
        [Container("p2", "Website"), Container("p3", "Garden"), Container("p4", "Taxes")]
    )
    for project in ("p1", "p2", "p3"):
        for n in (1, 2):
            await backend.create_task(TaskDraft(project, f"{project} task {n}"))
    await connect_all(api)
    await api.post(f"{V1}/sync")
    return await _containers(api)


async def _containers(api: AsyncClient) -> dict[str, str]:
    """Return the container ids by project name."""
    out = await api.get(f"{V1}/weekly/{FUTURE}/candidates")
    assert out.status_code == 200, out.text
    return {c["name"]: c["container_id"] for c in out.json()}


async def _label(api: AsyncClient, **labels: str) -> None:
    """Label projects by name through the project API (spec 003)."""
    tree = (await api.get(f"{V1}/projects/classification")).json()
    by_name = {p["name"]: p["id"] for c in tree["connections"] for p in c["projects"]}
    r = await api.put(
        f"{V1}/projects/labels",
        json={"changes": [{"id": by_name[n], "label": label} for n, label in labels.items()]},
    )
    assert r.status_code == 200, r.text


async def _add(api: AsyncClient, week: date, container_id: str) -> Any:
    r = await api.post(f"{V1}/weekly/{week}/projects", json={"container_id": container_id})
    assert r.status_code == 201, r.text
    return r.json()


async def test_candidates_list_milestones_and_unsorted_leaf_projects_with_task_counts(
    api: AsyncClient, world: FakeWorld
) -> None:
    await _setup(api, world)
    await _label(api, Garden="theme", Taxes="milestone")
    found = (await api.get(f"{V1}/weekly/{FUTURE}/candidates")).json()
    by_name = {c["name"]: c for c in found}
    assert set(by_name) == {"Inbox", "Website", "Taxes"}  # a labelled theme is not listed
    assert by_name["Website"]["open_tasks"] == 2 and by_name["Taxes"]["open_tasks"] == 0
    assert by_name["Website"]["kind"] == "unsorted" and by_name["Website"]["unsorted"] is True
    taxes = by_name["Taxes"]
    assert (taxes["kind"], taxes["state"], taxes["unsorted"]) == ("milestone", "active", False)
    assert taxes["theme"] is None and taxes["in_focus"] is None  # no theme, no focus data
    assert (taxes["rollover_count"], taxes["needs_rescope"], taxes["decision_open"]) == (
        0,
        False,
        False,
    )
    assert not any(c["selected"] for c in found)


async def test_more_than_three_milestones_are_accepted_and_only_warn(
    api: AsyncClient, world: FakeWorld
) -> None:
    ids = await _setup(api, world)
    for name in ("Inbox", "Website", "Garden"):
        state = await _add(api, FUTURE, ids[name])
    assert [p["name"] for p in state["plan"]["projects"]] == ["Inbox", "Website", "Garden"]
    assert state["plan"]["over_cap"] is False and state["plan"]["milestone_cap"] == 3
    assert "max_projects" not in state["plan"]
    again = await api.post(f"{V1}/weekly/{FUTURE}/projects", json={"container_id": ids["Garden"]})
    assert again.status_code == 201  # adding twice changes nothing
    assert len(again.json()["plan"]["projects"]) == 3
    fourth = await api.post(f"{V1}/weekly/{FUTURE}/projects", json={"container_id": ids["Taxes"]})
    assert fourth.status_code == 201, fourth.text  # no hard cap any more
    plan = fourth.json()["plan"]
    assert (plan["milestone_count"], plan["over_cap"]) == (4, True)
    removed = await api.delete(f"{V1}/weekly/{FUTURE}/projects/{plan['projects'][0]['id']}")
    plan = removed.json()["plan"]
    assert [p["name"] for p in plan["projects"]] == ["Website", "Garden", "Taxes"]
    assert (plan["milestone_count"], plan["over_cap"]) == (3, False)
    # Picking labelled the unsorted projects milestone (spec 004, R-05).
    found = {c["name"]: c for c in (await api.get(f"{V1}/weekly/{FUTURE}/candidates")).json()}
    assert found["Garden"]["kind"] == "milestone" and found["Garden"]["selected"] is True


async def test_a_project_of_another_user_cannot_be_chosen(
    api: AsyncClient, world: FakeWorld, make_user: Callable[..., Awaitable[AsyncClient]]
) -> None:
    ids = await _setup(api, world)
    other = await make_user("sam")
    r = await other.post(f"{V1}/weekly/{FUTURE}/projects", json={"container_id": ids["Inbox"]})
    assert r.status_code == 404


async def test_new_milestone_is_created_in_the_task_app_labelled_and_added(
    api: AsyncClient, world: FakeWorld
) -> None:
    ids = await _setup(api, world)
    await _label(api, Website="theme")
    r = await api.post(
        f"{V1}/weekly/{FUTURE}/milestones",
        json={
            "parent_id": ids["Website"],
            "name": "Launch",
            "done_state": "The site is live",
        },
    )
    assert r.status_code == 201, r.text
    project = r.json()["plan"]["projects"][0]
    assert project["name"] == "Launch" and project["created_here"] is True
    assert project["open_tasks"] == 0 and project["done_state"] == "The site is live"
    assert project["milestone_state"] == "active" and project["theme"]["name"] == "Website"
    created = world.tasks["default"].containers[-1]
    assert (created.name, created.parent_id) == ("Launch", "p2")
    found = {c["name"]: c for c in (await api.get(f"{V1}/weekly/{FUTURE}/candidates")).json()}
    assert found["Launch"]["path"] == "Website › Launch" and found["Launch"]["selected"]
    assert (found["Launch"]["kind"], found["Launch"]["done_state"]) == (
        "milestone",
        "The site is live",
    )
    blank = await api.post(
        f"{V1}/weekly/{FUTURE}/milestones",
        json={"parent_id": ids["Website"], "name": "   ", "done_state": "x"},
    )
    assert blank.status_code == 422
    old = await api.post(
        f"{V1}/weekly/{FUTURE}/subprojects", json={"parent_id": ids["Website"], "name": "Launch"}
    )
    assert old.status_code in (404, 405)  # the old route is gone


async def test_milestone_needs_a_done_state_and_support_and_creates_nothing_otherwise(
    api: AsyncClient, world: FakeWorld
) -> None:
    ids = await _setup(api, world)
    await _label(api, Inbox="theme")
    body = {"parent_id": ids["Inbox"], "name": "x", "done_state": "x is done"}
    before = len(world.tasks["default"].containers)
    world.tasks["default"].supported.discard(Capability.SUBPROJECTS)
    unsupported = await api.post(f"{V1}/weekly/{FUTURE}/milestones", json=body)
    assert unsupported.status_code == 409 and unsupported.json()["code"] == "not_supported"
    world.tasks["default"].supported.add(Capability.SUBPROJECTS)
    world.tasks["default"].unavailable = True
    down = await api.post(f"{V1}/weekly/{FUTURE}/milestones", json=body)
    assert down.status_code == 502
    world.tasks["default"].unavailable = False
    blank = await api.post(f"{V1}/weekly/{FUTURE}/milestones", json={**body, "done_state": "  "})
    assert blank.status_code == 422 and blank.json()["code"] == "done_state_required"
    assert len(world.tasks["default"].containers) == before  # nothing was created in the app


async def test_refresh_shows_tasks_added_in_the_task_app(
    api: AsyncClient, world: FakeWorld
) -> None:
    ids = await _setup(api, world)
    await _label(api, Website="theme")
    state = (
        await api.post(
            f"{V1}/weekly/{FUTURE}/milestones",
            json={"parent_id": ids["Website"], "name": "Launch", "done_state": "Launched"},
        )
    ).json()
    new_id = world.tasks["default"].containers[-1].remote_id
    assert state["plan"]["projects"][0]["open_tasks"] == 0
    await world.tasks["default"].create_task(TaskDraft(new_id, "Write copy"))
    await world.tasks["default"].create_task(TaskDraft(new_id, "Pick fonts"))
    refreshed = (await api.post(f"{V1}/weekly/{FUTURE}/refresh")).json()
    project = refreshed["plan"]["projects"][0]
    assert project["open_tasks"] == 2
    assert sorted(t["title"] for t in project["tasks"]) == ["Pick fonts", "Write copy"]
    (task_id,) = [
        r.remote_id for r in world.tasks["default"].tasks.values() if r.title == "Pick fonts"
    ]
    del world.tasks["default"].tasks[task_id]
    after = (await api.post(f"{V1}/weekly/{FUTURE}/refresh")).json()
    assert [t["title"] for t in after["plan"]["projects"][0]["tasks"]] == ["Write copy"]


async def test_give_days_spread_and_commit(api: AsyncClient, world: FakeWorld) -> None:
    ids = await _setup(api, world)
    for name in ("Inbox", "Website"):
        state = await _add(api, FUTURE, ids[name])
    first = state["plan"]["projects"][0]["tasks"][0]
    day = FUTURE + timedelta(days=2)
    put = await api.put(f"{V1}/tasks/{first['id']}/schedule", json={"date": str(day)})
    assert put.status_code == 200, put.text
    spread = (await api.post(f"{V1}/weekly/{FUTURE}/spread")).json()
    tasks = [t for p in spread["plan"]["projects"] for t in p["tasks"]]
    days = sorted(t["planned_day"] for t in tasks)
    assert None not in days and len(days) == 4
    assert all(date.fromisoformat(d).weekday() < 5 for d in days)
    assert len(set(days)) == 4  # four tasks, five weekdays: nobody shares a day
    assert next(t for t in tasks if t["id"] == first["id"])["planned_day"] == str(day)
    assert all(p["scheduled_tasks"] == 2 for p in spread["plan"]["projects"])
    done = (await api.post(f"{V1}/weekly/{FUTURE}/commit")).json()
    assert done["plan"]["status"] == "committed" and done["plan"]["committed_at"]
    edit = await api.post(f"{V1}/weekly/{FUTURE}/projects", json={"container_id": ids["Garden"]})
    assert edit.status_code == 422 and "Change the plan" in edit.json()["detail"]
    reopened = (await api.post(f"{V1}/weekly/{FUTURE}/reopen")).json()
    assert reopened["plan"]["status"] == "draft"


async def test_a_committed_plan_keeps_its_tasks_when_they_get_done(
    api: AsyncClient, world: FakeWorld
) -> None:
    ids = await _setup(api, world)
    state = await _add(api, FUTURE, ids["Website"])
    await api.post(f"{V1}/weekly/{FUTURE}/spread")
    before = (await api.post(f"{V1}/weekly/{FUTURE}/commit")).json()["plan"]["projects"][0]
    assert before["committed_tasks"] != [] and len(before["committed_tasks"]) == 2
    first = state["plan"]["projects"][0]["tasks"][0]["id"]
    await api.post(f"{V1}/tasks/{first}/complete")
    after = (await api.get(f"{V1}/weekly/{FUTURE}")).json()["plan"]["projects"][0]
    assert after["open_tasks"] == 1 and after["done_tasks"] == 1
    assert len(after["committed_tasks"]) == 2  # still two tasks were committed
    assert sorted(t["done"] for t in after["committed_tasks"]) == [False, True]
    draft = (await api.post(f"{V1}/weekly/{FUTURE}/reopen")).json()["plan"]["projects"][0]
    assert draft["committed_tasks"] == []


async def test_a_done_task_reports_the_local_day_it_was_completed(
    api: AsyncClient, world: FakeWorld
) -> None:
    admin = (await api.get(f"{V1}/auth/me")).json()
    await api.patch(f"{V1}/users/{admin['id']}", json={"timezone": "Europe/Athens"})
    ids = await _setup(api, world)
    state = await _add(api, FUTURE, ids["Website"])
    await api.post(f"{V1}/weekly/{FUTURE}/spread")
    await api.post(f"{V1}/weekly/{FUTURE}/commit")
    first = state["plan"]["projects"][0]["tasks"][0]["id"]
    await api.post(f"{V1}/tasks/{first}/complete")
    project = (await api.get(f"{V1}/weekly/{FUTURE}")).json()["plan"]["projects"][0]
    days = {t["id"]: t["completed_day"] for t in project["committed_tasks"]}
    # 22:30 UTC is already the next day in Athens (the test user's time zone), in March.
    assert days[first] == "2030-03-07"
    assert [d for i, d in days.items() if i != first] == [None]


def _finish(world: FakeWorld, title: str, at: datetime | None) -> None:
    """Mark a task done in the task app at ``at`` (``None``: done, but with no time)."""
    backend = world.tasks["default"]
    remote_id, task = next((i, t) for i, t in backend.tasks.items() if t.title == title)
    backend.tasks[remote_id] = replace(task, done=True, done_at=at, version=task.version + "+")


async def _extra(api: AsyncClient, week: date) -> list[dict[str, Any]]:
    state = (await api.get(f"{V1}/weekly/{week}")).json()
    extra: list[dict[str, Any]] = state["done_outside_plan"]
    return extra


async def _committed_website(api: AsyncClient, world: FakeWorld) -> dict[str, str]:
    ids = await _setup(api, world)
    await _add(api, FUTURE, ids["Website"])
    await api.post(f"{V1}/weekly/{FUTURE}/spread")
    await api.post(f"{V1}/weekly/{FUTURE}/commit")
    return ids


async def test_tasks_done_outside_the_plan_are_listed_with_their_day(
    api: AsyncClient, world: FakeWorld
) -> None:
    await _committed_website(api, world)
    assert await _extra(api, FUTURE) == []  # nothing is done yet

    # A task of the plan: it counts for the plan, not as an extra.
    _finish(world, "p2 task 1", datetime(2030, 3, 5, 10, tzinfo=UTC))
    # Tasks that the plan did not promise: another project, and one added after the commit.
    _finish(world, "p3 task 1", datetime(2030, 3, 6, 9, tzinfo=UTC))
    await world.tasks["default"].create_task(TaskDraft("p2", "Added later"))
    _finish(world, "Added later", datetime(2030, 3, 4, 8, tzinfo=UTC))
    await api.post(f"{V1}/sync")
    # Not in the list: done another week, done with no time, and still open.
    _finish(world, "p1 task 1", datetime(2030, 3, 12, 9, tzinfo=UTC))
    _finish(world, "p1 task 2", None)
    await api.post(f"{V1}/sync")

    extra = await _extra(api, FUTURE)
    assert [(e["title"], e["completed_day"], e["project"]) for e in extra] == [
        ("Added later", "2030-03-04", "Website"),
        ("p3 task 1", "2030-03-06", "Garden"),
    ]
    state = (await api.get(f"{V1}/weekly/{FUTURE}")).json()
    plan = state["plan"]["projects"][0]
    assert sorted(t["title"] for t in plan["committed_tasks"] if t["done"]) == ["p2 task 1"]
    # Another week has its own list, and the next week sees the task done in it.
    assert await _extra(api, FUTURE + timedelta(days=7)) == []


async def test_the_week_follows_the_time_zone_of_the_user(
    api: AsyncClient, world: FakeWorld
) -> None:
    admin = (await api.get(f"{V1}/auth/me")).json()
    await api.patch(f"{V1}/users/{admin['id']}", json={"timezone": "Europe/Athens"})
    await _committed_website(api, world)
    # Sunday 22:30 UTC before the week is Monday 00:30 in Athens: it belongs to the week.
    _finish(world, "p3 task 1", datetime(2030, 3, 3, 22, 30, tzinfo=UTC))
    # Sunday 22:30 UTC at the end of the week is Monday 00:30 in Athens: it belongs to the next.
    _finish(world, "p3 task 2", datetime(2030, 3, 10, 22, 30, tzinfo=UTC))
    await api.post(f"{V1}/sync")
    extra = await _extra(api, FUTURE)
    assert [(e["title"], e["completed_day"]) for e in extra] == [("p3 task 1", "2030-03-04")]
    nxt = await _extra(api, FUTURE + timedelta(days=7))
    assert nxt == []  # that week has no committed plan


async def test_nothing_is_listed_before_the_plan_is_committed(
    api: AsyncClient, world: FakeWorld
) -> None:
    ids = await _setup(api, world)
    await _add(api, FUTURE, ids["Website"])  # a draft
    _finish(world, "p3 task 1", datetime(2030, 3, 6, 9, tzinfo=UTC))
    await api.post(f"{V1}/sync")
    assert await _extra(api, FUTURE) == []
    assert await _extra(api, FUTURE + timedelta(days=14)) == []  # no plan at all


async def test_an_extra_task_has_its_project_color_and_link(
    api: AsyncClient, world: FakeWorld
) -> None:
    await _committed_website(api, world)
    _finish(world, "p3 task 1", datetime(2030, 3, 6, 9, tzinfo=UTC))
    await api.post(f"{V1}/sync")
    (one,) = await _extra(api, FUTURE)
    assert set(one) == {"id", "title", "completed_day", "project", "project_color", "url"}
    assert one["project"] == "Garden"


async def test_commit_needs_a_started_plan_but_not_a_milestone(
    api: AsyncClient, world: FakeWorld
) -> None:
    await _setup(api, world)
    assert (await api.post(f"{V1}/weekly/{FUTURE}/commit")).status_code == 404
    await api.post(f"{V1}/weekly/{FUTURE}/start")
    empty = await api.post(f"{V1}/weekly/{FUTURE}/commit")
    assert empty.status_code == 200, empty.text  # a week with zero milestones is valid
    assert empty.json()["plan"]["status"] == "committed" and empty.json()["plan"]["projects"] == []


async def test_the_week_is_the_monday_week_of_any_day(api: AsyncClient, world: FakeWorld) -> None:
    await _setup(api, world)
    state = (await api.get(f"{V1}/weekly/{FUTURE + timedelta(days=4)}")).json()
    assert state["week_start"] == str(FUTURE) and state["week_end"] == str(FUTURE + timedelta(7))
    assert state["plan"] is None and state["look_back"] is None


async def _committed_past_week(api: AsyncClient, world: FakeWorld) -> dict[str, str]:
    """Commit the week of PAST with three projects and two tasks in each of two of them."""
    ids = await _setup(api, world)
    for name in ("Inbox", "Website", "Garden"):
        await _add(api, PAST, ids[name])
    await api.post(f"{V1}/weekly/{PAST}/spread")  # in the past: refused
    tasks = (await api.get(f"{V1}/tasks")).json()
    for n, t in enumerate(tasks):
        await api.put(
            f"{V1}/tasks/{t['id']}/schedule", json={"date": str(PAST + timedelta(days=n % 5))}
        )
    await api.post(f"{V1}/weekly/{PAST}/commit")
    return ids


async def test_look_back_counts_what_was_done_and_applies_the_decisions(
    api: AsyncClient, world: FakeWorld
) -> None:
    await _committed_past_week(api, world)
    # Inbox: both done. Website: one of two done. Garden: nothing done.
    tasks = (await api.get(f"{V1}/tasks")).json()
    by_title = {t["title"]: t for t in tasks}
    for title in ("p1 task 1", "p1 task 2", "p2 task 1"):
        await api.post(f"{V1}/tasks/{by_title[title]['id']}/complete")
    state = (await api.get(f"{V1}/weekly/{NEXT_AFTER_PAST}")).json()
    back = state["look_back"]
    assert back["week_start"] == str(PAST) and back["reviewed"] is False
    counts = {p["name"]: (p["done"], p["committed"], p["completed"]) for p in back["projects"]}
    assert counts == {
        "Inbox": (2, 2, True),
        "Website": (1, 2, False),
        "Garden": (0, 2, False),
    }
    assert back["summary"]["committed_tasks"] == 6 and back["summary"]["done_tasks"] == 3
    assert (back["summary"]["milestones_committed"], back["summary"]["milestones_done"]) == (3, 1)
    ids = {p["name"]: p["id"] for p in back["projects"]}
    answers = {
        "projects": [
            {"plan_project_id": ids["Website"], "mark_done": True},
            {"plan_project_id": ids["Garden"], "decision": "recommit"},
        ],
        "reflection": "Too much gardening.",
    }
    reviewed = await api.post(f"{V1}/weekly/reviews/{back['plan_id']}", json=answers)
    assert reviewed.status_code == 200, reviewed.text
    history = reviewed.json()
    assert "1 open task stays" in history["notices"][0]  # Website was marked done by hand
    assert history["totals"] == {
        "weeks": 1,
        "committed_projects": 3,
        "done_projects": 2,  # Inbox by its tasks, Website because the user said so
        "committed_tasks": 6,
        "done_tasks": 3,
    }
    entry = history["entries"][0]
    assert entry["reflection"] == "Too much gardening."
    assert {p["name"]: p["done"] for p in entry["projects"]} == {
        "Inbox": True,
        "Website": True,
        "Garden": False,
    }
    assert {p["name"]: p["decision"] for p in entry["projects"]} == {
        "Inbox": None,  # finished: no decision
        "Website": None,  # marked done: no decision
        "Garden": "recommit",
    }
    remote = {t.title: t for t in world.tasks["default"].tasks.values()}
    assert remote["p2 task 2"].due_at is not None  # park and mark done leave the days alone
    assert remote["p3 task 1"].due_at is not None  # recommitted: left as it was
    again = await api.post(f"{V1}/weekly/reviews/{back['plan_id']}", json=answers)
    assert again.status_code == 422
    after = (await api.get(f"{V1}/weekly/{NEXT_AFTER_PAST}")).json()["look_back"]
    assert after["reviewed"] is True
    assert {p["name"]: p["outcome"] for p in after["projects"]}["Website"] == "done"
    suggested = (await api.get(f"{V1}/weekly/{NEXT_AFTER_PAST}/candidates")).json()
    assert suggested[0]["name"] == "Garden" and suggested[0]["carried_tasks"] == 2


async def test_park_leaves_the_due_dates_of_the_leftover_tasks(
    api: AsyncClient, world: FakeWorld
) -> None:
    """The old backlog choice cleared the days (O-1). Parking a milestone does not."""
    await _committed_past_week(api, world)
    back = (await api.get(f"{V1}/weekly/{NEXT_AFTER_PAST}")).json()["look_back"]
    ids = {p["name"]: p["id"] for p in back["projects"]}
    done = await api.post(
        f"{V1}/weekly/reviews/{back['plan_id']}",
        json={"projects": [{"plan_project_id": ids["Website"], "decision": "park"}]},
    )
    assert done.status_code == 200, done.text
    remote = {t.title: t for t in world.tasks["default"].tasks.values()}
    assert remote["p2 task 1"].due_at is not None and remote["p2 task 2"].due_at is not None
    candidates = {
        c["name"]: c for c in (await api.get(f"{V1}/weekly/{NEXT_AFTER_PAST}/candidates")).json()
    }
    assert candidates["Website"]["state"] == "parked"
    assert candidates["Website"]["rollover_count"] == 0


async def test_look_back_ignores_draft_weeks_and_can_be_skipped(
    api: AsyncClient, world: FakeWorld
) -> None:
    ids = await _setup(api, world)
    await _add(api, PAST, ids["Inbox"])  # never committed
    state = (await api.get(f"{V1}/weekly/{NEXT_AFTER_PAST}")).json()
    assert state["look_back"] is None
    skipped = (await api.post(f"{V1}/weekly/{NEXT_AFTER_PAST}/skip-look-back")).json()
    assert skipped["plan"]["retro_skipped"] is True
    assert (await api.get(f"{V1}/weekly/history")).json()["entries"] == []


async def test_review_of_unknown_or_uncommitted_week_is_refused(
    api: AsyncClient, world: FakeWorld
) -> None:
    ids = await _setup(api, world)
    state = await _add(api, PAST, ids["Inbox"])
    unknown = "00000000-0000-0000-0000-000000000000"
    assert (await api.post(f"{V1}/weekly/reviews/{unknown}", json={})).status_code == 404
    assert (
        await api.post(f"{V1}/weekly/reviews/{state['plan']['id']}", json={})
    ).status_code == 404
    await api.post(f"{V1}/weekly/{PAST}/commit")
    bad = await api.post(
        f"{V1}/weekly/reviews/{state['plan']['id']}",
        json={
            "projects": [{"plan_project_id": state["plan"]["projects"][0]["id"], "decision": "x"}]
        },
    )
    assert bad.status_code == 422


async def test_a_parked_task_is_left_out_of_the_spread_and_the_commit(
    api: AsyncClient, world: FakeWorld
) -> None:
    ids = await _setup(api, world)
    state = await _add(api, FUTURE, ids["Website"])
    project = state["plan"]["projects"][0]
    parked_id = project["tasks"][0]["id"]
    parked = await api.put(f"{V1}/weekly/{FUTURE}/tasks/{parked_id}/parked", json={"parked": True})
    assert parked.status_code == 200, parked.text
    project = parked.json()["plan"]["projects"][0]
    assert project["open_tasks"] == 1 and project["parked_tasks"] == 1
    assert [t["parked"] for t in project["tasks"] if t["id"] == parked_id] == [True]

    spread = (await api.post(f"{V1}/weekly/{FUTURE}/spread")).json()["plan"]["projects"][0]
    by_id = {t["id"]: t for t in spread["tasks"]}
    assert by_id[parked_id]["planned_day"] is None
    assert spread["scheduled_tasks"] == 1

    committed = (await api.post(f"{V1}/weekly/{FUTURE}/commit")).json()["plan"]["projects"][0]
    assert [t["id"] for t in committed["committed_tasks"]] == [
        t["id"] for t in spread["tasks"] if not t["parked"]
    ]

    await api.post(f"{V1}/weekly/{FUTURE}/reopen")
    back = await api.put(f"{V1}/weekly/{FUTURE}/tasks/{parked_id}/parked", json={"parked": False})
    project = back.json()["plan"]["projects"][0]
    assert project["open_tasks"] == 2 and project["parked_tasks"] == 0


async def test_only_a_task_of_the_plan_can_be_parked(api: AsyncClient, world: FakeWorld) -> None:
    ids = await _setup(api, world)
    await _add(api, FUTURE, ids["Website"])
    other = next(t for t in (await api.get(f"{V1}/tasks")).json() if t["title"] == "p3 task 1")
    r = await api.put(f"{V1}/weekly/{FUTURE}/tasks/{other['id']}/parked", json={"parked": True})
    assert r.status_code == 404, r.text
