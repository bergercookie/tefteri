"""A theme can be marked as work; everything under it is work."""

from typing import Any

from tefteri.domain.entities import TaskDraft
from tests.conftest import V1
from tests.integration.stats_helpers import WEEK, Stats, at


async def _projects(s: Stats) -> dict[str, dict[str, Any]]:
    tree = (await s.api.get(f"{V1}/projects/classification")).json()
    return {p["name"]: p for c in tree["connections"] for p in c["projects"]}


async def _work(s: Stats, name: str, work: bool = True) -> Any:
    project = (await _projects(s))[name]
    return await s.api.put(f"{V1}/projects/{project['id']}/work", json={"work": work})


async def test_a_theme_is_marked_as_work_and_its_projects_follow(env) -> None:  # type: ignore[no-untyped-def]
    s = Stats(env)
    await s.standard()
    before = await _projects(s)
    assert all(not p["is_work"] and not p["in_work"] for p in before.values())

    r = await _work(s, "Open source")
    assert r.status_code == 200, r.text
    assert r.json()["is_work"] is True and r.json()["in_work"] is True
    after = await _projects(s)
    # The theme, and the milestones under it, are work. Others are not.
    assert (after["Open source"]["is_work"], after["Open source"]["in_work"]) == (True, True)
    assert (after["Login flow"]["is_work"], after["Login flow"]["in_work"]) == (False, True)
    assert after["Docs"]["in_work"] is True
    assert after["Chores"]["in_work"] is False and after["Misc"]["in_work"] is False

    off = await _work(s, "Open source", False)
    assert off.json()["is_work"] is False
    assert all(not p["in_work"] for p in (await _projects(s)).values())


async def test_only_a_theme_can_be_work(env) -> None:  # type: ignore[no-untyped-def]
    s = Stats(env)
    await s.standard()
    wrong = await _work(s, "Login flow")  # a milestone
    assert wrong.status_code == 422 and wrong.json()["code"] == "not_a_theme"
    unlabeled = await _work(s, "Misc")
    assert unlabeled.status_code == 422
    gone = await s.api.put(
        f"{V1}/projects/00000000-0000-0000-0000-000000000001/work", json={"work": True}
    )
    assert gone.status_code == 404


async def test_the_mark_counts_only_while_the_label_is_theme(env) -> None:  # type: ignore[no-untyped-def]
    s = Stats(env)
    await s.standard()
    await _work(s, "Open source")
    await s.weekly.label(**{"Open source": "milestone"})
    projects = await _projects(s)
    assert projects["Open source"]["is_work"] is False
    assert projects["Login flow"]["in_work"] is False
    # The mark waits: the project is a theme again, and it is work again.
    await s.weekly.label(**{"Open source": "theme"})
    assert (await _projects(s))["Login flow"]["in_work"] is True


async def test_the_nearest_theme_decides(env) -> None:  # type: ignore[no-untyped-def]
    s = Stats(env)
    await s.standard()
    await _work(s, "Open source")
    # A theme inside a work theme that is not marked itself is not work.
    await s.weekly.label(**{"Docs": "theme"})
    projects = await _projects(s)
    assert projects["Docs"]["in_work"] is False
    assert projects["Login flow"]["in_work"] is True


async def test_tasks_say_if_they_are_work_in_every_list(env) -> None:  # type: ignore[no-untyped-def]
    s = Stats(env)
    await s.standard()
    await s.backend.create_task(TaskDraft("p3", "Fix login", due_at=at(6)))  # under Open source
    await s.backend.create_task(TaskDraft("p6", "Wash up", due_at=at(7)))  # under Chores
    await s.backend.create_task(TaskDraft("p3", "Ship docs", due_at=at(8)))
    await s.sync()
    await _work(s, "Open source")

    tasks = {t["title"]: t for t in (await s.api.get(f"{V1}/tasks")).json()}
    assert tasks["Fix login"]["work"] is True and tasks["Wash up"]["work"] is False

    week = {t["title"]: t for t in (await s.api.get(f"{V1}/views/week/{WEEK}")).json()["tasks"]}
    assert week["Fix login"]["work"] is True and week["Wash up"]["work"] is False

    day = (await s.api.get(f"{V1}/views/day/2030-03-06")).json()["tasks"]
    assert [(t["title"], t["work"]) for t in day] == [("Fix login", True)]

    one = (await s.api.get(f"{V1}/tasks/{tasks['Wash up']['id']}")).json()
    assert one["work"] is False

    open_ = (await s.api.get(f"{V1}/statistics/open", params={"day": str(WEEK)})).json()
    by_title = {i["title"]: i["project"]["work"] for i in open_["items"]}
    assert by_title == {"Fix login": True, "Wash up": False, "Ship docs": True}


async def test_completed_tasks_say_if_they_are_work(env) -> None:  # type: ignore[no-untyped-def]
    s = Stats(env)
    await s.standard()
    await s.done("p3", "Fixed login", at(6))
    await s.done("p6", "Washed up", at(7))
    await s.sync()
    await _work(s, "Open source")
    page = await s.page(period="week", day=str(WEEK))
    by_title = {i["title"]: i["project"]["work"] for i in page["items"]}
    assert by_title == {"Fixed login": True, "Washed up": False}


async def test_calendar_tasks_say_if_they_are_work(env) -> None:  # type: ignore[no-untyped-def]
    s = Stats(env)
    await s.standard()
    await s.backend.create_task(TaskDraft("p3", "Fix login", due_at=at(6)))
    await s.backend.create_task(TaskDraft("p6", "Wash up", due_at=at(7)))
    await s.sync()
    await _work(s, "Open source")
    items = (await s.api.get(f"{V1}/calendar")).json()
    by_title = {i["title"]: i["work"] for i in items if i["type"] == "task"}
    assert by_title == {"Fix login": True, "Wash up": False}
