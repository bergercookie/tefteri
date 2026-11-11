"""The review decides on every unfinished milestone: recommit, park, close or decide later."""

from datetime import timedelta
from typing import Any

from sqlalchemy import select

from tefteri.db.models.milestone import Milestone, MilestoneRollover
from tefteri.domain.entities import Container
from tests.conftest import V1
from tests.integration.conftest import ProjectsEnv
from tests.integration.weekly_helpers import AFTER, NEXT, WEEK, Weekly


async def _setup(env: ProjectsEnv) -> Weekly:
    weekly = Weekly(env)
    await env.connect(
        Container("p2", "Open source"),
        Container("p3", "Login flow", "p2"),
        Container("p4", "Docs", "p2"),
        Container("p5", "Release", "p2"),
        Container("p6", "Website", "p2"),
        tasks={"p3": 2, "p4": 2, "p5": 2, "p6": 2},
    )
    await weekly.label(
        **{
            "Open source": "theme",
            "Login flow": "milestone",
            "Docs": "milestone",
            "Release": "milestone",
            "Website": "milestone",
        }
    )
    return weekly


async def _milestone(weekly: Weekly, week: Any, name: str) -> dict[str, Any]:
    entry = (await weekly.entries(week))[name]
    body: dict[str, Any] = (await weekly.api.get(f"{V1}/milestones/{entry['milestone_id']}")).json()
    return body


async def test_recommit_adds_the_milestone_to_the_next_plan_with_one_rollover_event(
    env: ProjectsEnv,
) -> None:
    weekly = await _setup(env)
    await weekly.commit(WEEK, "Login flow", "Docs")
    r = await weekly.review(WEEK, {"name": "Login flow", "decision": "recommit"})
    assert r.status_code == 200, r.text
    assert r.json()["nudges"] == [] and r.json()["notices"] == []
    plan = (await weekly.state(NEXT))["plan"]
    assert plan["status"] == "draft" and [p["name"] for p in plan["projects"]] == ["Login flow"]
    assert plan["projects"][0]["rollover_count"] == 1
    milestone = await _milestone(weekly, NEXT, "Login flow")
    assert milestone["rollover_count"] == 1
    assert milestone["rollovers"] == [
        {"from_week": str(WEEK), "to_week": str(NEXT), "expected": False}
    ]
    async with env.db() as db:
        assert len((await db.execute(select(MilestoneRollover))).scalars().all()) == 1
    back = await weekly.look_back_entries(WEEK)
    assert back["Login flow"]["decision"] == "recommit" and back["Login flow"]["legacy"] is False


async def test_park_sets_the_state_and_leaves_the_count_and_the_due_dates(
    env: ProjectsEnv,
) -> None:
    weekly = await _setup(env)
    await weekly.commit(WEEK, "Docs")
    before = {t.remote_id: t.due_at for t in env.world.tasks["default"].tasks.values()}
    r = await weekly.review(WEEK, {"name": "Docs", "decision": "park"})
    assert r.status_code == 200, r.text
    found = await weekly.candidates(NEXT)
    assert found["Docs"]["state"] == "parked" and found["Docs"]["rollover_count"] == 0
    assert {t.remote_id: t.due_at for t in env.world.tasks["default"].tasks.values()} == before
    assert (await weekly.state(NEXT))["plan"] is None  # a park puts nothing in the next plan
    async with env.db() as db:
        assert (await db.execute(select(MilestoneRollover))).scalars().all() == []


async def test_a_parked_milestone_committed_again_continues_from_its_count(
    env: ProjectsEnv,
) -> None:
    weekly = await _setup(env)
    await weekly.commit(WEEK, "Docs")
    await weekly.review(WEEK, {"name": "Docs", "decision": "recommit"})
    await weekly.commit(NEXT)  # Docs is already in the plan of the next week
    await weekly.review(NEXT, {"name": "Docs", "decision": "park"})
    parked = await weekly.candidates(AFTER)
    assert parked["Docs"]["state"] == "parked" and parked["Docs"]["rollover_count"] == 1
    await weekly.add(AFTER, "Docs")
    plan = (await weekly.state(AFTER))["plan"]
    assert plan["projects"][0]["rollover_count"] == 1  # parking did not reset or raise it
    assert plan["projects"][0]["milestone_state"] == "parked"


async def test_decide_later_and_no_answer_change_nothing_and_leave_a_reminder(
    env: ProjectsEnv,
) -> None:
    weekly = await _setup(env)
    await weekly.commit(WEEK, "Login flow", "Docs", "Release")
    before = await _milestone(weekly, WEEK, "Login flow")
    r = await weekly.review(WEEK, {"name": "Login flow", "decision": "decide_later"})
    assert r.status_code == 200, r.text
    after = await _milestone(weekly, WEEK, "Login flow")
    assert (after["state"], after["rollover_count"]) == (before["state"], before["rollover_count"])
    assert after["rollovers"] == []
    found = await weekly.candidates(NEXT)
    # Decide later and no answer both leave the milestone open (FR-036, SC-013).
    assert found["Login flow"]["decision_open"] is True and found["Docs"]["decision_open"] is True
    assert found["Login flow"]["state"] == "active" and found["Docs"]["rollover_count"] == 0
    back = await weekly.look_back_entries(WEEK)
    assert {p["decision"] for p in back.values()} == {"decide_later"}
    assert (await weekly.state(NEXT))["plan"] is None
    # A later real decision clears the reminder.
    await weekly.commit(NEXT, "Login flow")
    await weekly.review(NEXT, {"name": "Login flow", "decision": "recommit"})
    assert (await weekly.candidates(AFTER))["Login flow"]["decision_open"] is False


async def test_a_finished_milestone_needs_no_decision(env: ProjectsEnv) -> None:
    weekly = await _setup(env)
    await weekly.commit(WEEK, "Login flow", "Docs")
    await weekly.complete("p3 task 0", "p3 task 1")
    back = await weekly.look_back_entries(WEEK)
    assert (
        back["Login flow"]["completed"] is True and back["Login flow"]["milestone_state"] == "done"
    )
    r = await weekly.review(WEEK, {"name": "Login flow", "decision": "recommit"})  # ignored
    assert r.status_code == 200, r.text
    assert (await weekly.state(NEXT))["plan"] is None
    after = await weekly.look_back_entries(WEEK)
    assert (after["Login flow"]["outcome"], after["Login flow"]["decision"]) == ("done", None)
    async with env.db() as db:
        assert (await db.execute(select(MilestoneRollover))).scalars().all() == []


async def test_a_recommit_into_a_committed_next_plan_reverts_it_to_draft_with_a_notice(
    env: ProjectsEnv,
) -> None:
    weekly = await _setup(env)
    await weekly.commit(WEEK, "Login flow")
    await weekly.commit(NEXT, "Website")
    assert (await weekly.state(NEXT))["plan"]["status"] == "committed"
    r = await weekly.review(WEEK, {"name": "Login flow", "decision": "recommit"})
    assert r.status_code == 200, r.text
    assert any("draft" in n for n in r.json()["notices"])
    plan = (await weekly.state(NEXT))["plan"]
    assert plan["status"] == "draft"
    assert sorted(p["name"] for p in plan["projects"]) == ["Login flow", "Website"]


async def test_the_review_is_stored_once_and_old_fields_are_rejected(env: ProjectsEnv) -> None:
    weekly = await _setup(env)
    await weekly.commit(WEEK, "Login flow")
    back = await weekly.look_back(WEEK)
    entry = back["projects"][0]["id"]
    for old in ({"leftover": "carry"}, {"finished_anyway": True}):
        bad = await weekly.api.post(
            f"{V1}/weekly/reviews/{back['plan_id']}",
            json={"projects": [{"plan_project_id": entry, **old}]},
        )
        assert bad.status_code == 422, old
    unknown = await weekly.api.post(
        f"{V1}/weekly/reviews/{back['plan_id']}",
        json={"projects": [{"plan_project_id": entry, "decision": "later"}]},
    )
    assert unknown.status_code == 422
    first = await weekly.review(WEEK, {"name": "Login flow", "decision": "recommit"})
    assert first.status_code == 200
    second = await weekly.review(WEEK, {"name": "Login flow", "decision": "recommit"})
    assert second.status_code == 422
    async with env.db() as db:
        assert len((await db.execute(select(MilestoneRollover))).scalars().all()) == 1


async def test_close_in_a_review_needs_a_milestone_that_is_closed_already(
    env: ProjectsEnv,
) -> None:
    weekly = await _setup(env)
    await weekly.commit(WEEK, "Login flow")
    r = await weekly.review(WEEK, {"name": "Login flow", "decision": "close"})
    assert r.status_code == 422 and r.json()["code"] == "confirm_required"
    milestone = await _milestone(weekly, WEEK, "Login flow")
    closed = await env.api.post(f"{V1}/milestones/{milestone['id']}/close", json={"confirm": True})
    assert closed.status_code == 200, closed.text
    ok = await weekly.review(WEEK, {"name": "Login flow", "decision": "close"})
    assert ok.status_code == 200, ok.text
    assert (await weekly.look_back_entries(WEEK))["Login flow"]["decision"] == "close"


# -- the rollover count and the nudge (FR-019, FR-029, FR-030) ----------------------------------


async def _round(
    weekly: Weekly, week: Any, decision: str = "recommit", expected: bool = False
) -> Any:
    """Commit what is in the plan of ``week`` and review it from the week after."""
    await weekly.commit(week)
    r = await weekly.review(
        week, {"name": "Login flow", "decision": decision, "expected": expected}
    )
    assert r.status_code == 200, r.text
    return r.json()


async def test_the_first_recommit_has_no_nudge_and_the_second_unmarked_one_has(
    env: ProjectsEnv,
) -> None:
    weekly = await _setup(env)
    await weekly.commit(WEEK, "Login flow")
    first = (await weekly.review(WEEK, {"name": "Login flow", "decision": "recommit"})).json()
    assert first["nudges"] == []
    assert (await weekly.candidates(NEXT))["Login flow"]["needs_rescope"] is False
    second = await _round(weekly, NEXT)
    assert [n["name"] for n in second["nudges"]] == ["Login flow"]
    assert second["nudges"][0]["milestone_id"]
    assert (await _milestone(weekly, AFTER, "Login flow"))["rollover_count"] == 2
    assert (await weekly.candidates(AFTER))["Login flow"]["needs_rescope"] is True
    assert (await weekly.entries(AFTER))["Login flow"]["needs_rescope"] is True
    # Ignoring the nudge never blocks committing it.
    assert (await weekly.api.post(f"{V1}/weekly/{AFTER}/commit")).status_code == 200


async def test_a_marked_event_stores_its_marker_on_its_own_row_and_gives_no_nudge(
    env: ProjectsEnv,
) -> None:
    weekly = await _setup(env)
    await weekly.commit(WEEK, "Login flow")
    await weekly.review(WEEK, {"name": "Login flow", "decision": "recommit", "expected": True})
    marked = await _milestone(weekly, NEXT, "Login flow")
    assert [r["expected"] for r in marked["rollovers"]] == [True] and marked[
        "needs_rescope"
    ] is False
    second = await _round(weekly, NEXT)  # unmarked, after a marked one
    assert second["nudges"] == []
    done = await _milestone(weekly, AFTER, "Login flow")
    assert [r["expected"] for r in done["rollovers"]] == [True, False]
    assert done["needs_rescope"] is False


async def test_unmarked_marked_unmarked_gives_no_nudge(env: ProjectsEnv) -> None:
    weekly = await _setup(env)
    await weekly.commit(WEEK, "Login flow")
    await weekly.review(WEEK, {"name": "Login flow", "decision": "recommit", "expected": False})
    await _round(weekly, NEXT, expected=True)
    third = await _round(weekly, AFTER, expected=False)
    assert third["nudges"] == []
    final = await _milestone(weekly, AFTER + timedelta(days=7), "Login flow")
    assert [r["expected"] for r in final["rollovers"]] == [False, True, False]
    assert final["rollover_count"] == 3 and final["needs_rescope"] is False


async def test_the_count_equals_the_rows_and_a_done_milestone_keeps_its_history(
    env: ProjectsEnv,
) -> None:
    weekly = await _setup(env)
    await weekly.commit(WEEK, "Login flow")
    await weekly.review(WEEK, {"name": "Login flow", "decision": "recommit", "expected": True})
    await _round(weekly, NEXT, decision="decide_later")
    await weekly.commit(AFTER, "Login flow")
    await weekly.complete("p3 task 0", "p3 task 1")
    done = await _milestone(weekly, AFTER, "Login flow")
    assert done["state"] == "done"
    assert (done["rollover_count"], [r["expected"] for r in done["rollovers"]]) == (1, [True])
    async with env.db() as db:
        (m,) = (await db.execute(select(Milestone))).scalars()
        rows = (await db.execute(select(MilestoneRollover))).scalars().all()
        assert m.rollover_count == len(rows) == 1
    history = (await weekly.api.get(f"{V1}/weekly/history")).json()
    assert history["entries"][0]["projects"][0]["rollover_count"] == 1
