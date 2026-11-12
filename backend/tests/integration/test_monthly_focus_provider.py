"""The real monthly provider supplies focus to weekly planning through the existing seam."""

from datetime import date

from tefteri.domain.entities import Container
from tests.conftest import V1
from tests.integration.conftest import ProjectsEnv
from tests.integration.monthly_helpers import MONTH, setup_month
from tests.integration.weekly_helpers import WEEK, Weekly


async def test_weekly_service_uses_saved_month_focus_and_swaps(
    env: ProjectsEnv,
) -> None:
    rows = await setup_month(
        env,
        Container("t1", "Theme one"),
        Container("t2", "Theme two"),
        Container("m1", "Milestone one", "t1"),
        Container("m2", "Milestone two", "t2"),
    )
    weekly = Weekly(env)
    await weekly.label(**{"Milestone one": "milestone", "Milestone two": "milestone"})
    service = env.app.state.monthly_focus_service
    user_id = await env.user_id()

    assert (await weekly.state(WEEK))["plan"] is None
    no_focus = (await env.api.get(f"{V1}/weekly/{WEEK}/themes")).json()
    assert no_focus["focus_known"] is False
    async with env.db() as db:
        await service.save_plan(db, user_id, MONTH, [(rows["Theme one"].id, 1)], tz="UTC")
    themes = (await env.api.get(f"{V1}/weekly/{WEEK}/themes")).json()
    assert themes["focus_known"] is True
    assert next(t for t in themes["themes"] if t["name"] == "Theme one")["in_focus"] is True

    async with env.db() as db:
        await service.change(
            db,
            user_id,
            MONTH,
            kind="swap",
            out_project_id=rows["Theme one"].id,
            in_project_id=rows["Theme two"].id,
            target=2,
            tz="UTC",
        )
    swapped = (await env.api.get(f"{V1}/weekly/{WEEK}/themes")).json()
    assert next(t for t in swapped["themes"] if t["name"] == "Theme one")["in_focus"] is False
    assert next(t for t in swapped["themes"] if t["name"] == "Theme two")["in_focus"] is True


async def test_saved_empty_focus_is_known_and_highlights_nothing(env: ProjectsEnv) -> None:
    await setup_month(env, Container("t1", "Theme one"), Container("m1", "Milestone one", "t1"))
    weekly = Weekly(env)
    await weekly.label(**{"Milestone one": "milestone"})
    async with env.db() as db:
        await env.app.state.monthly_focus_service.save_plan(
            db, await env.user_id(), MONTH, [], tz="UTC"
        )
    empty = (await env.api.get(f"{V1}/weekly/{WEEK}/themes")).json()
    assert empty["focus_known"] is True
    assert all(theme["in_focus"] is False for theme in empty["themes"])


async def test_removing_the_last_entry_keeps_the_saved_focus_known(env: ProjectsEnv) -> None:
    rows = await setup_month(env, Container("t1", "Theme one"))
    service = env.app.state.monthly_focus_service
    user_id = await env.user_id()
    async with env.db() as db:
        await service.save_plan(db, user_id, MONTH, [(rows["Theme one"].id, 1)], tz="UTC")
    async with env.db() as db:
        await service.change(
            db,
            user_id,
            MONTH,
            kind="remove",
            out_project_id=rows["Theme one"].id,
            tz="UTC",
        )
    async with env.db() as db:
        assert await service.themes_for_month(db, user_id, MONTH) == set()


async def test_five_theme_focus_does_not_limit_weekly_milestones(env: ProjectsEnv) -> None:
    containers = [
        item
        for index in range(6)
        for item in (
            Container(f"t{index}", f"Theme {index}"),
            Container(f"m{index}", f"Milestone {index}", f"t{index}"),
        )
    ]
    rows = await setup_month(env, *containers)
    weekly = Weekly(env)
    await weekly.label(**{f"Milestone {index}": "milestone" for index in range(6)})
    user_id = await env.user_id()
    async with env.db() as db:
        await env.app.state.monthly_focus_service.save_plan(
            db, user_id, MONTH, [(rows[f"Theme {index}"].id, None) for index in range(5)], tz="UTC"
        )

    week = date(2030, 3, 18)
    candidates = await weekly.candidates(week)
    assert {f"Milestone {index}" for index in range(6)} <= set(candidates)

    committed = await weekly.commit(week, *(f"Milestone {index}" for index in range(4)))
    assert committed["plan"]["milestone_count"] == 4
    assert committed["plan"]["over_cap"] is True
