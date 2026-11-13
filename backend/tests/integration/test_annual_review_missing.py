"""Integration tests of missing months and empty years (spec 008, user story 4)."""

from datetime import UTC, datetime

from tests.integration.conftest import make_snapshot, store_snapshot
from tests.integration.monthly_review_helpers import add_key_result, setup_review

TODAY_AT = datetime(2026, 11, 13, 12, tzinfo=UTC)


def _entry(key_result_id: str, value: float, month: int) -> dict[str, object]:
    return {
        "key_result_id": key_result_id,
        "metric": "Stars",
        "update_source": "manual",
        "start_value": 10,
        "base_value": 10,
        "latest_value": value,
        "latest_at": f"2025-{month:02d}-08T12:00:00Z",
        "target": 50,
        "deadline": "2025-12-31",
        "status": "active",
        "retired": False,
    }


async def test_eight_of_twelve_months_are_missing(env) -> None:
    env.app.state.clock = lambda: TODAY_AT
    env.app.state.key_result_service._clock = lambda: TODAY_AT
    rows = await setup_review(env, "Open source")
    key_result = await add_key_result(
        env,
        rows,
        metric="Stars",
        themes=("Open source",),
        start_value=10,
        target=50,
        year=2025,
    )
    user_id = await env.user_id()
    stored = [1, 2, 5, 6, 7, 8, 11, 12]
    async with env.db() as db:
        for month in stored:
            await store_snapshot(
                db,
                user_id,
                f"2025-{month:02d}",
                make_snapshot(
                    f"2025-{month:02d}",
                    key_results=[_entry(str(key_result.id), 10 + month * 2, month)],
                ),
            )
        review = await env.app.state.annual_review_service.review(db, user_id, 2025)
    assert review["coverage"]["stored"] == 8
    assert review["coverage"]["missing"] == [
        "2025-03",
        "2025-04",
        "2025-09",
        "2025-10",
    ]
    gaps = [
        point
        for point in review["goals"][0]["key_results"][0]["series"]
        if point["value"] is None
    ]
    assert len(gaps) == 4
    assert all(point["status"] == "missing" for point in gaps)
    assert review["split"]["months_covered"] == 8
    for month in review["months"]:
        if month["status"] == "missing":
            assert month["action"] == "open_monthly_review"


async def test_a_year_with_no_goals_and_no_snapshots(env) -> None:
    env.app.state.clock = lambda: TODAY_AT
    user_id = await env.user_id()
    async with env.db() as db:
        review = await env.app.state.annual_review_service.review(db, user_id, 2024)
    assert review["empty"]["reason"] == "no_goals"
    assert review["goals"] == []
    assert review["coverage"]["stored"] == 0
    assert review["split"]["total"] == 0
    assert review["split"]["percentages"] == {
        "goal_aligned": 0,
        "maintenance": 0,
        "off_plan": 0,
    }


async def test_old_shape_without_categories_is_not_stored(env) -> None:
    env.app.state.clock = lambda: TODAY_AT
    env.app.state.key_result_service._clock = lambda: TODAY_AT
    rows = await setup_review(env, "Open source")
    await add_key_result(env, rows, metric="Stars", themes=("Open source",), year=2025)
    user_id = await env.user_id()
    async with env.db() as db:
        payload = make_snapshot("2025-01")
        payload.pop("categories")
        await store_snapshot(db, user_id, "2025-01", payload)
        review = await env.app.state.annual_review_service.review(db, user_id, 2025)
    month = review["split"]["months"][0]
    assert month["counts"] is None
    assert month["not_stored"] is True
    assert review["split"]["months_covered"] == 0


async def test_a_reopened_month_uses_the_current_version(env) -> None:
    env.app.state.clock = lambda: TODAY_AT
    env.app.state.key_result_service._clock = lambda: TODAY_AT
    rows = await setup_review(env, "Open source")
    await add_key_result(env, rows, metric="Stars", themes=("Open source",), year=2025)
    user_id = await env.user_id()
    async with env.db() as db:
        await store_snapshot(db, user_id, "2025-01", make_snapshot("2025-01"))
        await store_snapshot(
            db,
            user_id,
            "2025-01",
            make_snapshot(
                "2025-01",
                categories={
                    "goal_aligned": 9,
                    "maintenance": 1,
                    "off_plan": 0,
                    "hidden": 0,
                },
            ),
            version=2,
        )
        review = await env.app.state.annual_review_service.review(db, user_id, 2025)
    assert review["months"][0]["version"] == 2
    assert review["split"]["counts"]["goal_aligned"] == 9
