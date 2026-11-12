"""Monthly planning reads the annual key-result view without writing to it."""

from datetime import date

from sqlalchemy import select

from tefteri.db.models.goal import Goal
from tefteri.db.models.key_result import KeyResult, KeyResultTheme, KeyResultValue
from tefteri.domain.entities import Container
from tests.integration.conftest import ProjectsEnv
from tests.integration.monthly_helpers import MONTH, setup_month


async def test_plan_shows_key_results_flags_and_planning_year_boundaries(
    env: ProjectsEnv,
) -> None:
    rows = await setup_month(
        env,
        Container("t1", "Theme one"),
        Container("t2", "Theme two"),
        Container("t3", "Theme three"),
    )
    user_id = await env.user_id()
    async with env.db() as db:
        goal = Goal(
            user_id=user_id,
            period_type="year",
            period_start=date(2030, 1, 1),
            title="Annual goal",
            status="active",
            position=0,
        )
        db.add(goal)
        await db.flush()
        key_results = [
            KeyResult(
                user_id=user_id,
                goal_id=goal.id,
                year=2030,
                metric="Metric",
                start_value=10,
                target=50,
                deadline=date(2030, 12, 31),
                update_source="manual",
                status="active",
                slot=index,
                position=index,
            )
            for index in (1, 2)
        ]
        off_focus_goal = Goal(
            user_id=user_id,
            period_type="year",
            period_start=date(2030, 1, 1),
            title="Off-focus goal",
            status="active",
            position=1,
        )
        db.add(off_focus_goal)
        await db.flush()
        off_focus_result = KeyResult(
            user_id=user_id,
            goal_id=off_focus_goal.id,
            year=2030,
            metric="Off-focus metric",
            start_value=0,
            target=10,
            deadline=date(2030, 12, 31),
            update_source="manual",
            status="active",
            slot=1,
            position=0,
        )
        db.add(off_focus_result)
        await db.flush()
        key_results.append(
            KeyResult(
                user_id=user_id,
                goal_id=goal.id,
                year=2030,
                metric="Past deadline",
                start_value=0,
                target=10,
                deadline=date(2030, 2, 28),
                update_source="manual",
                status="active",
                slot=3,
                position=2,
            )
        )
        db.add_all(key_results)
        await db.flush()
        db.add_all(
            [
                KeyResultTheme(
                    user_id=user_id,
                    key_result_id=key_results[0].id,
                    project_id=rows["Theme one"].id,
                    year=2030,
                    started_at=env.app.state.clock(),
                ),
                KeyResultTheme(
                    user_id=user_id,
                    key_result_id=key_results[0].id,
                    project_id=rows["Theme two"].id,
                    year=2030,
                    started_at=env.app.state.clock(),
                ),
                KeyResultTheme(
                    user_id=user_id,
                    key_result_id=key_results[1].id,
                    project_id=rows["Theme one"].id,
                    year=2030,
                    started_at=env.app.state.clock(),
                ),
                KeyResultTheme(
                    user_id=user_id,
                    key_result_id=off_focus_result.id,
                    project_id=rows["Theme three"].id,
                    year=2030,
                    started_at=env.app.state.clock(),
                ),
                KeyResultValue(
                    user_id=user_id,
                    key_result_id=key_results[0].id,
                    value=20,
                    at=env.app.state.clock(),
                    on_date=date(2030, 3, 10),
                    source="manual",
                    seq=1,
                ),
            ]
        )
        await db.flush()
        await env.app.state.monthly_focus_service.save_plan(
            db,
            user_id,
            MONTH,
            [(rows["Theme one"].id, 3)],
            tz="UTC",
        )

    async with env.db() as db:
        plan = await env.app.state.monthly_focus_service.plan(db, user_id, MONTH, tz="UTC")
    assert len(plan.key_results) == 4
    first = next(result for result in plan.key_results if result.id == key_results[0].id)
    assert (first.start_value, first.current_value, first.current_at.date()) == (
        10,
        20,
        date(2030, 3, 15),
    )
    assert set(first.theme_ids) == {rows["Theme one"].id, rows["Theme two"].id}
    assert not any(flag["code"] == "no_theme_in_focus" for flag in first.flags)
    second = next(result for result in plan.key_results if result.id == key_results[1].id)
    assert rows["Theme one"].id in second.theme_ids
    assert not any(flag["code"] == "no_theme_in_focus" for flag in second.flags)
    no_theme = next(result for result in plan.key_results if result.metric == "Past deadline")
    assert no_theme.past_deadline is True
    assert {flag["code"] for flag in no_theme.flags} >= {
        "no_theme_in_focus",
        "no_usable_theme",
    }
    off_focus = next(result for result in plan.key_results if result.metric == "Off-focus metric")
    assert off_focus.goal_title == "Off-focus goal"
    assert any(flag["code"] == "no_theme_in_focus" for flag in off_focus.flags)
    assert second.goal_title == "Annual goal"
    assert plan.themes_without_key_result == []
    async with env.db() as db:
        assert (
            len(
                list(
                    (
                        await db.execute(
                            select(KeyResultValue).where(
                                KeyResultValue.key_result_id.in_([row.id for row in key_results])
                            )
                        )
                    ).scalars()
                )
            )
            == 1
        )


async def test_no_annual_plan_and_unlinked_theme_are_empty_nonblocking_reads(
    env: ProjectsEnv,
) -> None:
    rows = await setup_month(env, Container("t1", "Theme"))
    async with env.db() as db:
        await env.app.state.monthly_focus_service.save_plan(
            db, await env.user_id(), MONTH, [(rows["Theme"].id, None)], tz="UTC"
        )
    async with env.db() as db:
        plan = await env.app.state.monthly_focus_service.plan(
            db, await env.user_id(), MONTH, tz="UTC"
        )
    assert plan.key_results == []
    assert plan.themes_without_key_result == [rows["Theme"].id]


async def test_december_and_next_january_read_their_own_planning_years(
    env: ProjectsEnv,
) -> None:
    await setup_month(env)
    user_id = await env.user_id()
    async with env.db() as db:
        for year in (2029, 2030):
            goal = Goal(
                user_id=user_id,
                period_type="year",
                period_start=date(year, 1, 1),
                title=f"Goal {year}",
                status="active",
                position=0,
            )
            db.add(goal)
            await db.flush()
            db.add(
                KeyResult(
                    user_id=user_id,
                    goal_id=goal.id,
                    year=year,
                    metric=f"Metric {year}",
                    start_value=0,
                    target=10,
                    deadline=date(year, 12, 31),
                    update_source="manual",
                    status="active",
                    slot=1,
                    position=0,
                )
            )
        await db.flush()
        december = await env.app.state.monthly_focus_service.plan(
            db, user_id, date(2029, 12, 1), tz="UTC"
        )
        january = await env.app.state.monthly_focus_service.plan(
            db, user_id, date(2030, 1, 1), tz="UTC"
        )
    assert (december.planning_year, december.key_results[0].metric) == (2029, "Metric 2029")
    assert (january.planning_year, january.key_results[0].metric) == (2030, "Metric 2030")
