"""The review and its notes are private to the user (spec 008, FR-022)."""

from datetime import UTC, datetime

from sqlalchemy import select

from tefteri.db.models.goal import Goal
from tests.integration.conftest import make_snapshot, store_snapshot
from tests.integration.monthly_review_helpers import add_key_result, setup_review

TODAY_AT = datetime(2026, 11, 13, 12, tzinfo=UTC)


async def test_another_user_sees_nothing(env, make_user) -> None:
    env.app.state.clock = lambda: TODAY_AT
    env.app.state.key_result_service._clock = lambda: TODAY_AT
    rows = await setup_review(env, "Open source")
    await add_key_result(
        env, rows, metric="Stars", themes=("Open source",), year=2025
    )
    user_id = await env.user_id()
    async with env.db() as db:
        await store_snapshot(db, user_id, "2025-01", make_snapshot("2025-01"))
        goal = (await db.execute(select(Goal))).scalars().first()
    other = await make_user("other")

    review = await other.get("/api/v1/annual-review/2025")
    assert review.status_code == 200
    assert review.json()["goals"] == []
    assert review.json()["coverage"]["stored"] == 0

    note = await other.put(
        "/api/v1/annual-review/2025/notes",
        json={"goal_id": str(goal.id), "body": "Not mine."},
    )
    assert note.status_code == 404
