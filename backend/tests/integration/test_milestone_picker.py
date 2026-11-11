"""The weekly picker offers milestones, groups them under their theme, and labels on pick."""

from httpx import AsyncClient
from sqlalchemy import select

from tefteri.db.models.milestone import Milestone
from tefteri.domain.entities import Container
from tests.conftest import V1
from tests.integration.conftest import ProjectsEnv
from tests.integration.weekly_helpers import NEXT, WEEK, Weekly


async def _setup(env: ProjectsEnv) -> Weekly:
    weekly = Weekly(env)
    await env.connect(
        Container("p2", "Open source"),
        Container("p3", "Login flow", "p2"),
        Container("p4", "Docs", "p2"),
        Container("p5", "Chores"),
        Container("p6", "Old stuff"),
        Container("p7", "Loose end"),
        Container("p8", "Website"),
        Container("p9", "Design", "p8"),
        Container("p10", "Taxes", "p5"),
        tasks={"p3": 3, "p4": 1, "p7": 2},
    )
    await weekly.label(
        **{
            "Open source": "theme",
            "Login flow": "milestone",
            "Docs": "milestone",
            "Chores": "maintenance",
            "Old stuff": "ignored",
        }
    )
    return weekly


async def test_only_milestones_and_unsorted_leaf_projects_are_offered(env: ProjectsEnv) -> None:
    weekly = await _setup(env)
    found = await weekly.candidates(WEEK)
    # A theme, maintenance, ignored, what is inside a routine, and an unclassified project that
    # has subprojects are never offered (SC-003).
    assert set(found) == {"Login flow", "Docs", "Loose end", "Design", "Inbox"}
    assert found["Login flow"]["kind"] == "milestone" and found["Login flow"]["unsorted"] is False
    assert found["Loose end"]["kind"] == "unsorted" and found["Loose end"]["unsorted"] is True
    assert found["Login flow"]["open_tasks"] == 3


async def test_milestones_carry_their_parent_theme_and_no_theme_is_null(env: ProjectsEnv) -> None:
    weekly = await _setup(env)
    found = await weekly.candidates(WEEK)
    assert found["Login flow"]["theme"]["name"] == "Open source"
    assert found["Login flow"]["path"] == "Open source › Login flow"
    assert found["Docs"]["theme"]["id"] == found["Login flow"]["theme"]["id"]
    assert found["Loose end"]["theme"] is None
    # The unclassified Website has a subproject, so it counts as a theme for its child.
    assert found["Design"]["theme"]["name"] == "Website"


async def test_a_second_add_changes_nothing_and_a_pick_labels_the_project(
    env: ProjectsEnv, api: AsyncClient
) -> None:
    weekly = await _setup(env)
    first = await weekly.add(WEEK, "Loose end")
    second = await weekly.add(WEEK, "Loose end")
    assert [p["id"] for p in first["plan"]["projects"]] == [
        p["id"] for p in second["plan"]["projects"]
    ]
    found = await weekly.candidates(WEEK)
    assert found["Loose end"]["selected"] is True and found["Loose end"]["kind"] == "milestone"
    history = await env.history("Loose end")
    assert [(h.label, h.source) for h in history] == [("milestone", "user")]
    async with env.db() as db:
        assert len((await db.execute(select(Milestone))).scalars().all()) == 1


async def test_a_theme_or_a_parent_without_a_label_is_refused_with_a_code(
    env: ProjectsEnv,
) -> None:
    weekly = await _setup(env)
    theme = await weekly.try_add(WEEK, "Open source")
    assert theme.status_code == 422 and theme.json()["code"] == "not_a_milestone"
    parent = await weekly.try_add(WEEK, "Website")  # unclassified, has a subproject
    assert parent.status_code == 422 and parent.json()["code"] == "not_a_milestone"
    for name in ("Chores", "Old stuff", "Taxes"):  # maintenance, ignored, inside a routine
        r = await weekly.try_add(WEEK, name)
        assert r.status_code == 422 and r.json()["code"] == "not_eligible", name
    assert (await weekly.state(WEEK))["plan"] is None or not (await weekly.entries(WEEK))


async def test_another_user_gets_404_for_a_project_that_is_not_theirs(
    env: ProjectsEnv, make_user: object
) -> None:
    weekly = await _setup(env)
    other = await make_user("sam")  # type: ignore[operator]
    r = await other.post(
        f"{V1}/weekly/{WEEK}/projects", json={"container_id": await weekly.cid("Docs")}
    )
    assert r.status_code == 404
    assert (await other.get(f"{V1}/weekly/{WEEK}/candidates")).json() == []


async def test_a_parked_milestone_is_listed_as_parked_and_a_closed_one_is_not(
    env: ProjectsEnv,
) -> None:
    weekly = await _setup(env)
    await weekly.commit(WEEK, "Login flow", "Docs")
    reviewed = await weekly.review(
        WEEK,
        {"name": "Login flow", "decision": "park"},
        {"name": "Docs", "decision": "decide_later"},
    )
    assert reviewed.status_code == 200, reviewed.text
    found = await weekly.candidates(NEXT)
    assert found["Login flow"]["state"] == "parked" and found["Login flow"]["rollover_count"] == 0
    assert found["Docs"]["decision_open"] is True  # "decide later" leaves a reminder (FR-036)
    assert found["Login flow"]["decision_open"] is False
    closed = await api_close(env, weekly, "Docs")
    assert closed == 200
    assert "Docs" not in await weekly.candidates(NEXT)


async def api_close(env: ProjectsEnv, weekly: Weekly, name: str) -> int:
    async with env.db() as db:
        milestone = (
            await db.execute(
                select(Milestone).where(Milestone.project_id == (await env.rows())[name].id)
            )
        ).scalar_one()
    r = await env.api.post(f"{V1}/milestones/{milestone.id}/close", json={"confirm": True})
    return r.status_code


async def test_themes_list_live_themes_with_their_milestone_counts(env: ProjectsEnv) -> None:
    weekly = await _setup(env)
    r = await env.api.get(f"{V1}/weekly/{WEEK}/themes")
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["focus_known"] is False
    names = {t["name"]: t for t in body["themes"]}
    # Maintenance and ignored projects are not themes. Website acts as one: it has a subproject.
    assert set(names) == {"Open source", "Website"}
    assert (names["Open source"]["milestones"], names["Open source"]["open_milestones"]) == (2, 2)
    assert names["Website"]["milestones"] == 0
    assert names["Open source"]["container_id"] == await weekly.cid("Open source")
    # Inbox, Loose end, Website, Design and Taxes have no label: five unsorted projects.
    assert body["unsorted_count"] == 5
