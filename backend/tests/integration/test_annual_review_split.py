"""Integration tests of the year split (spec 008, user story 3)."""

from datetime import UTC, datetime

from tests.integration.conftest import make_snapshot, store_snapshot
from tests.integration.monthly_review_helpers import add_key_result, setup_review

TODAY_AT = datetime(2026, 11, 13, 12, tzinfo=UTC)


async def test_the_year_bar_is_the_sum_of_the_months(env) -> None:
    env.app.state.clock = lambda: TODAY_AT
    env.app.state.key_result_service._clock = lambda: TODAY_AT
    rows = await setup_review(env, "Open source")
    await add_key_result(env, rows, metric="Stars", themes=("Open source",), year=2025)
    user_id = await env.user_id()
    async with env.db() as db:
        for month, (aligned, maintenance, off_plan, hidden) in enumerate(
            [
                (10, 2, 1, 1),
                (5, 5, 0, 2),
                (0, 0, 8, 0),
            ],
            start=1,
        ):
            await store_snapshot(
                db,
                user_id,
                f"2025-{month:02d}",
                make_snapshot(
                    f"2025-{month:02d}",
                    categories={
                        "goal_aligned": aligned,
                        "maintenance": maintenance,
                        "off_plan": off_plan,
                        "hidden": hidden,
                    },
                ),
            )
        review = await env.app.state.annual_review_service.review(db, user_id, 2025)
    counts = review["split"]["counts"]
    assert counts == {"goal_aligned": 15, "maintenance": 7, "off_plan": 9}
    assert review["split"]["total"] == 31
    assert review["split"]["hidden"] == 3
    assert sum(counts.values()) == review["split"]["total"]
    percentages = review["split"]["percentages"]
    assert sum(percentages.values()) == 100
    month_rows = review["split"]["months"]
    assert len(month_rows) == 12
    assert month_rows[0]["counts"]["goal_aligned"] == 10
    assert month_rows[3]["counts"] is None
    assert month_rows[0]["not_stored"] is False


async def test_live_changes_do_not_change_the_bar(env) -> None:
    env.app.state.clock = lambda: TODAY_AT
    env.app.state.key_result_service._clock = lambda: TODAY_AT
    rows = await setup_review(env, "Open source")
    await add_key_result(env, rows, metric="Stars", themes=("Open source",), year=2025)
    user_id = await env.user_id()
    async with env.db() as db:
        await store_snapshot(
            db,
            user_id,
            "2025-01",
            make_snapshot(
                "2025-01",
                categories={
                    "goal_aligned": 4,
                    "maintenance": 3,
                    "off_plan": 2,
                    "hidden": 1,
                },
            ),
        )
        first = await env.app.state.annual_review_service.review(db, user_id, 2025)
        # A changed task category in the live rows is not read by the review.
        await db.execute(
            __import__("sqlalchemy").text(
                "update task_categories set category = 'off_plan'"
            )
        )
        second = await env.app.state.annual_review_service.review(db, user_id, 2025)
    assert first["split"]["counts"] == second["split"]["counts"]
    assert first["split"]["percentages"] == second["split"]["percentages"]
