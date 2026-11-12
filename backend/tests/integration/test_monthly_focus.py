"""Monthly focus planning, eligible-theme picker and target integration tests."""

from datetime import date

import pytest
from sqlalchemy import select

from tefteri.db.models.connection import Connection
from tefteri.db.models.project_label import ProjectLabel as ProjectLabelRow
from tefteri.db.models.user import User
from tefteri.domain.entities import Container
from tefteri.domain.enums import ProjectLabel
from tefteri.services.errors import Conflict, Invalid, NotAFocusTheme, NotFound
from tests.integration.conftest import ProjectsEnv
from tests.integration.monthly_helpers import MONTH, done_milestone, label, setup_month


async def test_picker_only_offers_live_eligible_themes(env: ProjectsEnv) -> None:
    rows = await setup_month(
        env,
        Container("t1", "Theme"),
        Container("m1", "Milestone"),
        Container("a1", "Maintenance"),
        Container("i1", "Ignored"),
        Container("o1", "Orphan"),
        Container("u1", "Unsorted"),
    )
    await label(env, "Milestone", ProjectLabel.MILESTONE)
    await label(env, "Maintenance", ProjectLabel.MAINTENANCE)
    await label(env, "Ignored", ProjectLabel.IGNORED)
    await label(env, "Orphan", ProjectLabel.THEME)
    env.world.tasks["default"].containers.remove(
        next(c for c in env.world.tasks["default"].containers if c.remote_id == "o1")
    )
    await env.sync()

    async with env.db() as db:
        picker = await env.app.state.monthly_focus_service.themes(db, await env.user_id(), MONTH)

    assert [theme.project_id for theme in picker.themes] == [rows["Theme"].id]
    assert picker.unsorted_count >= 1
    assert picker.task_connections
    filtered = await _picker_for_connection(env)
    assert [theme.project_id for theme in filtered.themes] == [rows["Theme"].id]
    async with env.db() as db:
        with pytest.raises(NotAFocusTheme):
            await env.app.state.monthly_focus_service.save_plan(
                db,
                await env.user_id(),
                MONTH,
                [(rows["Milestone"].id, None)],
                tz="UTC",
            )


async def test_focus_save_reload_soft_count_notes_and_empty_focus(env: ProjectsEnv) -> None:
    rows = await setup_month(env, *(Container(f"t{i}", f"Theme {i}") for i in range(6)))
    service = env.app.state.monthly_focus_service
    user_id = await env.user_id()

    for selected, note, month in (
        (4, None, MONTH),
        (6, "above", date(2030, 4, 1)),
        (0, "empty", date(2030, 5, 1)),
    ):
        async with env.db() as db:
            await service.save_plan(
                db,
                user_id,
                month,
                [(rows[f"Theme {i}"].id, None) for i in range(selected)],
                tz="UTC",
            )
        async with env.db() as db:
            plan = await service.plan(db, user_id, month, tz="UTC")
        assert plan.count_note == note
        assert len(plan.entries) == selected


async def test_focus_save_rejects_duplicate_foreign_and_past_theme(
    env: ProjectsEnv, make_user
) -> None:
    rows = await setup_month(env, Container("t1", "Theme"))
    service = env.app.state.monthly_focus_service
    user_id = await env.user_id()
    await make_user("focus-owner")
    async with env.db() as db:
        foreign_user = (
            await db.execute(select(User).where(User.username == "focus-owner"))
        ).scalar_one()
        connection = Connection(
            user_id=foreign_user.id,
            kind="tasks",
            provider="fake",
            display_name="Foreign connection",
            settings={},
        )
        db.add(connection)
        await db.flush()
        foreign_project = ProjectLabelRow(
            user_id=foreign_user.id,
            connection_id=connection.id,
            remote_id="foreign-theme",
            name="Foreign theme",
            label=ProjectLabel.THEME.value,
        )
        db.add(foreign_project)
        await db.flush()
        foreign_project_id = foreign_project.id

    async with env.db() as db:
        with pytest.raises(Invalid) as duplicate:
            await service.save_plan(db, user_id, MONTH, [(rows["Theme"].id, None)] * 2, tz="UTC")
    assert duplicate.value.code == "duplicate_theme"
    async with env.db() as db:
        with pytest.raises(NotFound):
            await service.save_plan(db, user_id, MONTH, [(foreign_project_id, None)], tz="UTC")
    async with env.db() as db:
        with pytest.raises(Conflict) as past_month:
            await service.save_plan(
                db, user_id, date(2030, 2, 1), [(rows["Theme"].id, None)], tz="UTC"
            )
    assert past_month.value.code == "past_month"


async def test_picker_search_and_last_month_done_hint(env: ProjectsEnv) -> None:
    containers = [Container(f"t{i:03}", f"Theme {i:03}") for i in range(300)]
    containers.append(Container("m1", "March milestone"))
    await setup_month(env, *containers)
    await label(env, "March milestone", ProjectLabel.MILESTONE)
    await done_milestone(
        env,
        "March milestone",
        done_on=date(2030, 2, 14),
        theme_name="Theme 172",
    )
    async with env.db() as db:
        picker = await env.app.state.monthly_focus_service.themes(
            db, await env.user_id(), MONTH, q="Theme 172"
        )

    assert [theme.name for theme in picker.themes] == ["Theme 172"]
    assert picker.themes[0].last_month_done == 1


@pytest.mark.parametrize("target", [-1, 2.5, "abc", True])
async def test_invalid_targets_are_rejected_without_saving(
    env: ProjectsEnv, target: object
) -> None:
    rows = await setup_month(env, Container("t1", "Theme"))
    service = env.app.state.monthly_focus_service
    async with env.db() as db:
        with pytest.raises(Invalid) as invalid:
            await service.save_plan(
                db, await env.user_id(), MONTH, [(rows["Theme"].id, target)], tz="UTC"
            )
    assert invalid.value.code == "invalid_target"

    async with env.db() as db:
        plan = await service.plan(db, await env.user_id(), MONTH, tz="UTC")
    assert plan.focus_known is False


async def test_targets_round_trip_and_first_current_month_save_counts_from_day_one(
    env: ProjectsEnv,
) -> None:
    rows = await setup_month(env, *(Container(f"t{i}", f"Theme {i}") for i in range(3)))
    service = env.app.state.monthly_focus_service
    async with env.db() as db:
        await service.save_plan(
            db,
            await env.user_id(),
            MONTH,
            [
                (rows["Theme 0"].id, 3),
                (rows["Theme 1"].id, 0),
                (rows["Theme 2"].id, None),
            ],
            tz="UTC",
        )
    async with env.db() as db:
        plan = await service.plan(db, await env.user_id(), MONTH, tz="UTC")

    assert [entry.target for entry in plan.entries] == [3, 0, None]
    assert [entry.marker for entry in plan.entries] == ["missed", "met", "no_target"]
    assert {entry.counts_from for entry in plan.entries} == {MONTH}
    assert not any(
        any(word in key.lower() for word in ("hours", "duration", "effort")) for key in vars(plan)
    )


async def _picker_for_connection(env: ProjectsEnv):
    async with env.db() as db:
        return await env.app.state.monthly_focus_service.themes(
            db, await env.user_id(), MONTH, connection_id=env.connection_uuid()
        )
