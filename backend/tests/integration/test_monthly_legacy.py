"""Old month goals and period reviews remain readable and untouched."""

from datetime import datetime

from sqlalchemy import func, select

from tefteri.db.models.goal import Goal, Plan
from tefteri.db.models.review import PeriodReview
from tests.conftest import V1
from tests.integration.conftest import ProjectsEnv
from tests.integration.monthly_review_helpers import MONTH, setup_review


async def test_old_month_rows_are_not_reviewed_or_modified_and_checklists_remain(
    env: ProjectsEnv,
) -> None:
    await setup_review(env, "Theme")
    user_id = await env.user_id()
    async with env.db() as db:
        old_goal = Goal(
            user_id=user_id,
            period_type="month",
            period_start=MONTH,
            title="Legacy month goal",
            status="active",
        )
        db.add(old_goal)
        plan = Plan(
            user_id=user_id,
            period_type="month",
            period_start=MONTH,
            title="Old plan",
        )
        db.add(plan)
        await db.flush()
        old_review = PeriodReview(
            user_id=user_id,
            plan_id=plan.id,
            generated_at=datetime.now().astimezone(),
            planned_count=1,
            completed_count=0,
            carried_over=[],
            items=[{"goal": "old"}],
        )
        db.add(old_review)
        await db.flush()
        before = (old_goal.id, old_goal.title, old_review.id, list(old_review.items))

    async with env.db() as db:
        draft = await env.app.state.monthly_review_service.draft(db, user_id, MONTH, tz="UTC")
    assert all(item["name"] != "Legacy month goal" for item in draft.snapshot["themes"])
    async with env.db() as db:
        stored_goal = await db.get(Goal, before[0])
        stored_review = await db.get(PeriodReview, before[2])
        assert stored_goal is not None and (stored_goal.id, stored_goal.title) == before[:2]
        assert stored_review is not None and (stored_review.id, stored_review.items) == before[2:]
        assert (
            await db.scalar(
                select(func.count())
                .select_from(PeriodReview)
                .where(PeriodReview.user_id == user_id)
            )
            == 1
        )
    response = await env.api.get(f"{V1}/checklists/month/{MONTH.isoformat()}")
    assert response.status_code == 200
