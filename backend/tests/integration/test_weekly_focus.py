"""Outside focus and the focus share come from the monthly focus, and are never stored."""

import uuid
from datetime import date

from sqlalchemy.ext.asyncio import AsyncSession

from tefteri.domain.entities import Container
from tests.conftest import V1
from tests.integration.conftest import ProjectsEnv
from tests.integration.weekly_helpers import WEEK, Weekly


class FakeFocus:
    """A provider that the test fills, as feature 007 will do with the real focus."""

    def __init__(self) -> None:
        self.by_month: dict[date, set[uuid.UUID]] = {}
        self.asked: list[date] = []

    async def themes_for_month(
        self, db: AsyncSession, user_id: uuid.UUID, month_start: date
    ) -> set[uuid.UUID] | None:
        self.asked.append(month_start)
        return self.by_month.get(month_start)


async def _setup(env: ProjectsEnv) -> tuple[Weekly, FakeFocus]:
    weekly = Weekly(env)
    await env.connect(
        Container("p2", "Open source"),
        Container("p3", "Login flow", "p2"),
        Container("p4", "Garden"),
        Container("p5", "Compost", "p4"),
        Container("p6", "Loose"),
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
    focus = FakeFocus()
    env.app.state.weekly_service._focus = focus  # noqa: SLF001 - the seam of feature 007
    return weekly, focus


async def _theme_id(env: ProjectsEnv, name: str) -> uuid.UUID:
    return (await env.rows())[name].id


async def test_with_focus_the_focus_themes_come_first_and_other_milestones_are_outside(
    env: ProjectsEnv,
) -> None:
    weekly, focus = await _setup(env)
    focus.by_month[date(2030, 3, 1)] = {await _theme_id(env, "Garden")}
    themes = (await env.api.get(f"{V1}/weekly/{WEEK}/themes")).json()
    assert themes["focus_known"] is True
    assert [(t["name"], t["in_focus"]) for t in themes["themes"]] == [
        ("Garden", True),
        ("Open source", False),
    ]
    found = await weekly.candidates(WEEK)
    assert (found["Compost"]["in_focus"], found["Login flow"]["in_focus"]) == (True, False)
    assert list(found)[0] == "Compost"  # focus milestones first
    await weekly.commit(WEEK, "Login flow", "Compost", "Loose")
    plan = (await weekly.state(WEEK))["plan"]
    assert plan["focus_known"] is True and plan["month"] == "2030-03-01"
    entries = {p["name"]: p for p in plan["projects"]}
    assert entries["Login flow"]["outside_focus"] is True
    assert entries["Compost"]["outside_focus"] is False
    assert entries["Loose"]["outside_focus"] is True  # no theme is outside a focus that exists
    back = await weekly.look_back_entries(WEEK)
    assert back["Login flow"]["outside_focus"] is True and back["Compost"]["outside_focus"] is False


async def test_changing_the_focus_changes_the_display_and_nothing_is_stored(
    env: ProjectsEnv,
) -> None:
    weekly, focus = await _setup(env)
    focus.by_month[date(2030, 3, 1)] = {await _theme_id(env, "Garden")}
    await weekly.commit(WEEK, "Login flow", "Compost")
    assert (await weekly.entries(WEEK))["Login flow"]["outside_focus"] is True
    focus.by_month[date(2030, 3, 1)] = {await _theme_id(env, "Open source")}
    entries = await weekly.entries(WEEK)
    assert entries["Login flow"]["outside_focus"] is False
    assert entries["Compost"]["outside_focus"] is True


async def test_without_focus_data_nothing_is_highlighted_or_outside(env: ProjectsEnv) -> None:
    weekly, _ = await _setup(env)  # the provider knows no month
    themes = (await env.api.get(f"{V1}/weekly/{WEEK}/themes")).json()
    assert themes["focus_known"] is False and {t["in_focus"] for t in themes["themes"]} == {None}
    found = await weekly.candidates(WEEK)
    assert {c["in_focus"] for c in found.values()} == {None}
    await weekly.commit(WEEK, "Login flow")
    plan = (await weekly.state(WEEK))["plan"]
    assert plan["focus_known"] is False and plan["projects"][0]["outside_focus"] is False
    assert (await weekly.look_back_entries(WEEK))["Login flow"]["outside_focus"] is False


async def test_the_default_provider_knows_no_focus(env: ProjectsEnv) -> None:
    weekly = Weekly(env)
    await env.connect(Container("p2", "Open source"), Container("p3", "Login flow", "p2"))
    await weekly.label(**{"Open source": "theme", "Login flow": "milestone"})
    plan = (await weekly.state(WEEK))["plan"]
    assert plan is None
    await weekly.add(WEEK, "Login flow")
    plan = (await weekly.state(WEEK))["plan"]
    assert (plan["focus_known"], plan["projects"][0]["outside_focus"]) == (False, False)


async def test_the_focus_of_the_month_of_the_monday_is_used(env: ProjectsEnv) -> None:
    weekly, focus = await _setup(env)
    monday = date(2030, 4, 29)  # the week ends in May
    await weekly.add(monday, "Compost")
    await weekly.state(monday)
    assert set(focus.asked) == {date(2030, 4, 1)}
    focus.asked.clear()
    await weekly.add(date(2030, 5, 6), "Compost")
    assert set(focus.asked) == {date(2030, 5, 1)}
