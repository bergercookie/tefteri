"""Old month goals remain readable and untouched."""

from tefteri.db.models.goal import Goal
from tests.conftest import V1
from tests.integration.conftest import ProjectsEnv
from tests.integration.monthly_review_helpers import MONTH, setup_review


async def test_old_month_goal_is_not_reviewed_or_modified_and_checklists_remain(
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
        await db.flush()
        before = (old_goal.id, old_goal.title)

    async with env.db() as db:
        draft = await env.app.state.monthly_review_service.draft(db, user_id, MONTH, tz="UTC")
    assert all(item["name"] != "Legacy month goal" for item in draft.snapshot["themes"])
    async with env.db() as db:
        stored_goal = await db.get(Goal, before[0])
        assert stored_goal is not None and (stored_goal.id, stored_goal.title) == before
    response = await env.api.get(f"{V1}/checklists/month/{MONTH.isoformat()}")
    assert response.status_code == 200
