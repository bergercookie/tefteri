"""Monthly focus changes, effect previews, append-only history and undo."""

from datetime import date

import pytest
from sqlalchemy import select

from tefteri.db.models.connection import SourceContainer
from tefteri.db.models.monthly import FocusChange, MonthlyReview, MonthlyReviewSnapshot
from tefteri.db.models.weekly import WeeklyPlan, WeeklyPlanProject
from tefteri.domain.entities import Container
from tefteri.domain.enums import ProjectLabel
from tefteri.services.errors import AlreadyUndone, Conflict, LeftThisMonth
from tests.integration.conftest import ProjectsEnv
from tests.integration.monthly_helpers import MONTH, TODAY, done_milestone, label, setup_month


async def test_swap_dry_run_and_undo_preserve_weekly_commitments_and_history(
    env: ProjectsEnv,
) -> None:
    rows = await setup_month(
        env,
        *(Container(f"t{i}", f"Theme {i}") for i in range(4)),
        Container("m3", "Earlier milestone", "t3"),
    )
    await label(env, "Earlier milestone", ProjectLabel.MILESTONE)
    service = env.app.state.monthly_focus_service
    user_id = await env.user_id()
    async with env.db() as db:
        await service.save_plan(
            db,
            user_id,
            MONTH,
            [(rows[f"Theme {i}"].id, i) for i in range(3)],
            tz="UTC",
        )
    async with env.db() as db:
        review = MonthlyReview(
            user_id=user_id,
            month=MONTH,
            current_version=1,
            current_changed_at=TODAY,
        )
        db.add(review)
        await db.flush()
        snapshot = MonthlyReviewSnapshot(
            review_id=review.id,
            version=1,
            schema_version=1,
            payload={"themes": [{"name": "Frozen theme"}]},
            values_written=[],
        )
        db.add(snapshot)
        await db.flush()
        snapshot_id = snapshot.id
    await done_milestone(
        env,
        "Earlier milestone",
        done_on=date(2030, 3, 2),
        theme_name="Theme 3",
    )
    async with env.db() as db:
        container_id = (
            await db.execute(select(SourceContainer.id).where(SourceContainer.remote_id == "m3"))
        ).scalar_one()
        weekly_plan = WeeklyPlan(
            user_id=user_id,
            week_start=date(2030, 3, 4),
            status="committed",
        )
        db.add(weekly_plan)
        await db.flush()
        db.add(
            WeeklyPlanProject(
                plan_id=weekly_plan.id,
                container_id=container_id,
                name="Committed milestone",
                position=0,
                theme_project_id=rows["Theme 0"].id,
                theme_name="Theme 0",
            )
        )
        await db.flush()
    before_weekly = await _weekly_projects(env)

    async with env.db() as db:
        preview = await service.change(
            db,
            user_id,
            MONTH,
            kind="swap",
            out_project_id=rows["Theme 0"].id,
            in_project_id=rows["Theme 3"].id,
            target=2,
            dry_run=True,
            tz="UTC",
        )
    async with env.db() as db:
        assert (await db.execute(select(FocusChange))).scalars().all() == []
    assert preview.effect.counts_from == date(2030, 3, 15)
    assert preview.effect.finished_earlier_in_month == 1
    assert preview.effect.finished_earlier[0]["done_on"] == date(2030, 3, 2)
    assert preview.effect.weekly_commitments_unchanged == 1

    async with env.db() as db:
        changed = await service.change(
            db,
            user_id,
            MONTH,
            kind="swap",
            out_project_id=rows["Theme 0"].id,
            in_project_id=rows["Theme 3"].id,
            target=2,
            dry_run=False,
            tz="UTC",
        )
    async with env.db() as db:
        after = await service.plan(db, user_id, MONTH, tz="UTC")
    assert {entry.project_id for entry in after.entries if entry.left_on is None} == {
        rows["Theme 1"].id,
        rows["Theme 2"].id,
        rows["Theme 3"].id,
    }
    assert await _weekly_projects(env) == before_weekly
    async with env.db() as db:
        snapshot_after_swap = await db.get(MonthlyReviewSnapshot, snapshot_id)
        assert snapshot_after_swap is not None
        assert snapshot_after_swap.payload == {"themes": [{"name": "Frozen theme"}]}

    async with env.db() as db:
        history = await service.history(db, user_id, MONTH, tz="UTC")
    assert len(history.changes) == 1
    assert history.changes[0].out_name == "Theme 0"
    assert history.changes[0].in_name == "Theme 3"
    async with env.db() as db:
        await service.undo(db, user_id, MONTH, changed.batch_id, tz="UTC")
    async with env.db() as db:
        undone = await service.plan(db, user_id, MONTH, tz="UTC")
        logs = list((await db.execute(select(FocusChange))).scalars())
    assert {entry.project_id for entry in undone.entries if entry.left_on is None} == {
        rows[f"Theme {i}"].id for i in range(3)
    }
    assert len(logs) == 2 and logs[-1].source == "undo"


async def test_change_validation_and_undo_conflicts(env: ProjectsEnv) -> None:
    rows = await setup_month(env, *(Container(f"t{i}", f"Theme {i}") for i in range(4)))
    service = env.app.state.monthly_focus_service
    user_id = await env.user_id()
    async with env.db() as db:
        await service.save_plan(
            db, user_id, MONTH, [(rows[f"Theme {i}"].id, None) for i in range(3)], tz="UTC"
        )
    async with env.db() as db:
        with pytest.raises(Conflict) as membership:
            await service.save_plan(
                db,
                user_id,
                MONTH,
                [(rows[f"Theme {i}"].id, None) for i in (0, 1, 3)],
                tz="UTC",
            )
    assert membership.value.code == "use_changes"

    async with env.db() as db:
        with pytest.raises(Conflict) as already:
            await service.change(
                db,
                user_id,
                MONTH,
                kind="add",
                in_project_id=rows["Theme 1"].id,
                tz="UTC",
            )
    assert already.value.code == "already_in_focus"
    async with env.db() as db:
        with pytest.raises(Conflict) as not_current:
            await service.change(
                db,
                user_id,
                date(2030, 4, 1),
                kind="add",
                in_project_id=rows["Theme 3"].id,
                tz="UTC",
            )
    assert not_current.value.code == "not_current_month"

    async with env.db() as db:
        first = await service.change(
            db,
            user_id,
            MONTH,
            kind="target",
            out_project_id=rows["Theme 0"].id,
            target=4,
            tz="UTC",
        )
        await service.change(
            db,
            user_id,
            MONTH,
            kind="target",
            out_project_id=rows["Theme 0"].id,
            target=5,
            tz="UTC",
        )
    async with env.db() as db:
        with pytest.raises(Conflict) as not_undoable:
            await service.undo(db, user_id, MONTH, first.batch_id, tz="UTC")
    assert not_undoable.value.code == "not_undoable"


async def test_add_remove_target_change_history_and_double_undo(env: ProjectsEnv) -> None:
    rows = await setup_month(env, *(Container(f"t{i}", f"Theme {i}") for i in range(3)))
    service = env.app.state.monthly_focus_service
    user_id = await env.user_id()
    async with env.db() as db:
        await service.save_plan(
            db, user_id, MONTH, [(rows["Theme 0"].id, 1), (rows["Theme 1"].id, None)], tz="UTC"
        )

    async with env.db() as db:
        await service.change(
            db,
            user_id,
            MONTH,
            kind="add",
            in_project_id=rows["Theme 2"].id,
            target=0,
            tz="UTC",
        )
        await service.change(
            db,
            user_id,
            MONTH,
            kind="target",
            out_project_id=rows["Theme 0"].id,
            target=3,
            tz="UTC",
        )
        removed = await service.change(
            db,
            user_id,
            MONTH,
            kind="remove",
            out_project_id=rows["Theme 1"].id,
            tz="UTC",
        )
    async with env.db() as db:
        history = await service.history(db, user_id, MONTH, tz="UTC")
    assert [row.kind for row in history.changes] == ["add", "target", "remove"]
    assert all(row.on == date(2030, 3, 15) for row in history.changes)
    assert history.changes[0].in_name == "Theme 2"
    assert (history.changes[1].target_before, history.changes[1].target_after) == (1, 3)
    assert history.changes[2].out_name == "Theme 1"
    async with env.db() as db:
        with pytest.raises(Conflict) as left:
            await service.change(
                db,
                user_id,
                MONTH,
                kind="add",
                in_project_id=rows["Theme 1"].id,
                tz="UTC",
            )
    assert isinstance(left.value, LeftThisMonth)
    async with env.db() as db:
        await service.undo(db, user_id, MONTH, removed.batch_id, tz="UTC")
    async with env.db() as db:
        with pytest.raises(AlreadyUndone):
            await service.undo(db, user_id, MONTH, removed.batch_id, tz="UTC")


async def _weekly_projects(env: ProjectsEnv) -> list[tuple[str, int]]:
    from tefteri.db.models.weekly import WeeklyPlan, WeeklyPlanProject

    async with env.db() as db:
        return list(
            (
                await db.execute(
                    select(WeeklyPlanProject.name, WeeklyPlanProject.position)
                    .join(WeeklyPlan, WeeklyPlan.id == WeeklyPlanProject.plan_id)
                    .where(WeeklyPlan.user_id == await env.user_id())
                )
            ).all()
        )
