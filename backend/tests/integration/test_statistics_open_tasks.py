"""The unfinished tasks of a week, in the three work categories."""

from typing import Any

from tefteri.domain.entities import TaskDraft
from tests.conftest import V1
from tests.integration.stats_helpers import WEEK, Stats, at


async def _open(s: Stats, **params: Any) -> dict[str, Any]:
    r = await s.api.get(f"{V1}/statistics/open", params={"day": str(WEEK)} | params)
    assert r.status_code == 200, r.text
    body: dict[str, Any] = r.json()
    return body


async def _due(s: Stats, project: str, title: str, day: int) -> None:
    await s.backend.create_task(TaskDraft(project, title, due_at=at(day)))


async def test_open_tasks_of_the_week_fall_into_the_three_categories(env) -> None:  # type: ignore[no-untyped-def]
    s = Stats(env)
    await s.standard()
    await _due(s, "p3", "Fix login", 6)  # a milestone that is committed
    await _due(s, "p6", "Wash up", 7)  # inside a routine
    await _due(s, "p9", "Odd job", 8)  # a project without a label
    await _due(s, "p8", "Old chore", 8)  # inside an ignored project
    await _due(s, "p9", "Next week", 14)  # due outside the week
    await s.add("p9", "No date")  # no due date, so not of the week
    await s.done("p9", "Already done", at(5))
    await s.sync()
    await s.weekly.commit(WEEK, "Login flow")
    body = await _open(s)
    assert body["available"] is True
    assert body["counts"] == {"goal_aligned": 1, "maintenance": 1, "off_plan": 1}
    assert body["total"] == 3 and body["hidden"] == 1
    by_title = {i["title"]: i for i in body["items"]}
    assert set(by_title) == {"Fix login", "Wash up", "Odd job"}
    assert by_title["Fix login"]["category"] == "goal_aligned"
    assert by_title["Fix login"]["project"]["name"] == "Login flow"
    assert by_title["Odd job"]["unsorted"] is True
    assert [i["title"] for i in body["items"]] == ["Fix login", "Wash up", "Odd job"]


async def test_without_a_committed_plan_a_milestone_task_is_off_plan(env) -> None:  # type: ignore[no-untyped-def]
    s = Stats(env)
    await s.standard()
    await _due(s, "p3", "Fix login", 6)
    await s.sync()
    body = await _open(s)
    assert body["counts"]["goal_aligned"] == 0 and body["counts"]["off_plan"] == 1
