"""The numbers of the review: tasks, milestones, pace and the focus share (FR-020, FR-021)."""

import json
import uuid
from datetime import date

from sqlalchemy.ext.asyncio import AsyncSession

from tefteri.domain.entities import Container
from tefteri.services.weekly import MAX_EXTRA_DONE
from tests.conftest import V1
from tests.integration.conftest import ProjectsEnv
from tests.integration.weekly_helpers import NEXT, WEEK, Weekly


class _Focus:
    def __init__(self, themes: set[uuid.UUID]) -> None:
        self.themes = themes

    async def themes_for_month(
        self, db: AsyncSession, user_id: uuid.UUID, month_start: date
    ) -> set[uuid.UUID] | None:
        return self.themes


async def _setup(env: ProjectsEnv) -> Weekly:
    weekly = Weekly(env)
    await env.connect(
        Container("p2", "Open source"),
        Container("p3", "Login flow", "p2"),
        Container("p4", "Garden"),
        Container("p5", "Compost", "p4"),
        tasks={"p3": 2, "p5": 2},
    )
    await weekly.label(
        **{
            "Open source": "theme",
            "Garden": "theme",
            "Login flow": "milestone",
            "Compost": "milestone",
        }
    )
    return weekly


async def test_the_summary_counts_tasks_milestones_and_the_pace(env: ProjectsEnv) -> None:
    weekly = await _setup(env)
    await weekly.commit(WEEK, "Login flow", "Compost")
    await weekly.complete("p3 task 0", "p3 task 1", "p5 task 0")
    summary = (await weekly.look_back(WEEK))["summary"]
    assert (summary["committed_tasks"], summary["done_tasks"]) == (4, 3)
    assert (summary["milestones_committed"], summary["milestones_done"]) == (2, 1)
    assert summary["note"] is None and summary["focus_share"] is None  # no focus data
    pace = {p["day"]: p["done"] for p in summary["pace"]}
    assert len(pace) == 7 and pace["2030-03-06"] == 3 and sum(pace.values()) == 3
    assert list(pace)[0] == str(WEEK)


async def test_the_focus_share_is_the_share_of_completed_tasks_under_focus_themes(
    env: ProjectsEnv,
) -> None:
    weekly = await _setup(env)
    garden = (await env.rows())["Garden"].id
    env.app.state.weekly_service._focus = _Focus({garden})  # noqa: SLF001
    await weekly.commit(WEEK, "Login flow", "Compost")
    await weekly.complete("p3 task 0", "p5 task 0", "p5 task 1")
    summary = (await weekly.look_back(WEEK))["summary"]
    assert summary["focus_share"] == 2 / 3
    nothing_done = await _setup_nothing_done(env, weekly)
    assert nothing_done is None


async def _setup_nothing_done(env: ProjectsEnv, weekly: Weekly) -> float | None:
    await weekly.commit(NEXT, "Login flow")
    summary = (await weekly.look_back(NEXT))["summary"]  # NEXT + 7: nothing is done
    share: float | None = summary["focus_share"]
    return share


async def test_with_nothing_committed_there_are_no_ratios_and_a_note(env: ProjectsEnv) -> None:
    weekly = await _setup(env)
    await weekly.api.post(f"{V1}/weekly/{WEEK}/start")
    assert (await weekly.api.post(f"{V1}/weekly/{WEEK}/commit")).status_code == 200
    summary = (await weekly.look_back(WEEK))["summary"]
    assert summary["committed_tasks"] == 0 and summary["done_tasks"] == 0
    assert summary["focus_share"] is None
    assert summary["note"] and "No task was committed" in summary["note"]
    # A week with milestones but no task with a day has the same note, and no division by zero.
    await weekly.add(NEXT, "Login flow")
    await weekly.api.post(f"{V1}/weekly/{NEXT}/commit")
    again = (await weekly.look_back(NEXT))["summary"]
    assert again["committed_tasks"] == 0 and again["note"] and again["focus_share"] is None


async def test_the_weekly_flow_has_no_goal_field_and_done_outside_the_plan_is_unchanged(
    env: ProjectsEnv,
) -> None:
    weekly = await _setup(env)
    await weekly.commit(WEEK, "Login flow")
    await weekly.complete("p5 task 0")  # not committed: done outside the plan
    await env.sync()
    state = await weekly.state(WEEK)
    assert [e["title"] for e in state["done_outside_plan"]] == ["p5 task 0"]
    assert MAX_EXTRA_DONE == 200
    await weekly.review(WEEK, {"name": "Login flow", "decision": "decide_later"})
    texts = [
        json.dumps(await weekly.state(WEEK)),
        json.dumps(await weekly.state(NEXT)),
        json.dumps((await weekly.api.get(f"{V1}/weekly/history")).json()),
    ]
    for text in texts:
        assert "goal" not in text.lower()
