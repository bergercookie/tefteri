"""Integration tests of mid-year changes and orphaned themes (spec 008, US5, US6)."""

from datetime import UTC, date, datetime

from sqlalchemy import select

from tefteri.db.models.goal import Goal
from tefteri.db.models.key_result import PlanChange
from tefteri.db.models.project_label import ProjectLabel as ProjectLabelRow
from tefteri.domain.enums import PlanChangeKind
from tests.integration.conftest import make_snapshot, store_snapshot
from tests.integration.monthly_review_helpers import add_key_result, setup_review

TODAY_AT = datetime(2026, 11, 13, 12, tzinfo=UTC)


async def test_retired_goal_and_retarget_change(env) -> None:
    env.app.state.clock = lambda: TODAY_AT
    env.app.state.key_result_service._clock = lambda: TODAY_AT
    rows = await setup_review(env, "Open source")
    key_result = await add_key_result(
        env,
        rows,
        metric="Stars",
        themes=("Open source",),
        start_value=0,
        target=100,
        year=2025,
    )
    user_id = await env.user_id()
    async with env.db() as db:
        goal = (await db.execute(select(Goal).where(Goal.id == key_result.goal_id))).scalar_one()
        goal.status = "retired"
        goal.retired_at = datetime(2025, 6, 15, tzinfo=UTC)
        goal.retired_reason = "The plan changed."
        db.add(
            PlanChange(
                user_id=user_id,
                year=2025,
                goal_id=goal.id,
                key_result_id=key_result.id,
                kind=PlanChangeKind.KEY_RESULT_EDITED.value,
                field="target",
                old_value="80",
                new_value="100",
                source="user",
                at=datetime(2025, 4, 1, tzinfo=UTC),
            )
        )
        await store_snapshot(
            db,
            user_id,
            "2025-01",
            make_snapshot(
                "2025-01",
                key_results=[
                    {
                        "key_result_id": str(key_result.id),
                        "start_value": 0,
                        "base_value": 0,
                        "latest_value": 90,
                        "latest_at": "2025-01-08T12:00:00Z",
                        "target": 100,
                        "deadline": "2025-12-31",
                        "status": "active",
                        "retired": False,
                    }
                ],
            ),
        )
        review = await env.app.state.annual_review_service.review(db, user_id, 2025)
    goal_out = review["goals"][0]
    assert goal_out["status"] == "retired"
    assert goal_out["retired_at"].date() == date(2025, 6, 15)
    assert goal_out["key_results"][0]["outcome"] == "retired"
    assert goal_out["key_results"][0]["changes"][0]["field"] == "target"


async def test_orphaned_and_relabelled_themes_stay(env) -> None:
    env.app.state.clock = lambda: TODAY_AT
    env.app.state.key_result_service._clock = lambda: TODAY_AT
    rows = await setup_review(env, "Open source")
    key_result = await add_key_result(
        env,
        rows,
        metric="Stars",
        themes=("Open source",),
        start_value=0,
        target=100,
        year=2025,
    )
    user_id = await env.user_id()
    async with env.db() as db:
        row = (
            await db.execute(
                select(ProjectLabelRow).where(ProjectLabelRow.id == rows["Open source"].id)
            )
        ).scalar_one()
        row.orphaned_reason = "missing"
        row.orphaned_at = datetime(2025, 8, 1, tzinfo=UTC)
        await store_snapshot(
            db,
            user_id,
            "2025-02",
            make_snapshot(
                "2025-02",
                themes=[
                    {
                        "project_id": str(row.id),
                        "name": "Open source",
                        "target": 1,
                        "done": 1,
                        "status": "in_focus",
                        "milestones": [
                            {"milestone_id": "m1", "name": "Ship", "done_on": "2025-02-08"}
                        ],
                    }
                ],
                key_results=[
                    {
                        "key_result_id": str(key_result.id),
                        "start_value": 0,
                        "base_value": 0,
                        "latest_value": 20,
                        "latest_at": "2025-02-08T12:00:00Z",
                        "target": 100,
                        "deadline": "2025-12-31",
                        "status": "active",
                        "retired": False,
                    }
                ],
            ),
        )
        review = await env.app.state.annual_review_service.review(db, user_id, 2025)
    theme = review["goals"][0]["key_results"][0]["themes"][0]
    assert theme["name"] == "Open source"
    assert theme["orphaned"]["reason"] == "missing"
    assert theme["shipped"] == 1
    assert review["goals"][0]["key_results"][0]["flags"][0]["code"] == "no_usable_theme"
