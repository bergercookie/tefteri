"""Integration tests of the annual review service (spec 008, M2)."""

from datetime import UTC, date, datetime

from sqlalchemy import select

from tefteri.db.models.goal import Goal
from tests.integration.conftest import make_snapshot, store_review_note, store_snapshot
from tests.integration.monthly_review_helpers import add_key_result, setup_review

TODAY = date(2026, 11, 13)
TODAY_AT = datetime(2026, 11, 13, 12, tzinfo=UTC)


async def _prepare(env):
    env.app.state.clock = lambda: TODAY_AT
    env.app.state.key_result_service._clock = lambda: TODAY_AT
    rows = await setup_review(env, "Open source")
    goal = await add_key_result(
        env,
        rows,
        metric="Stars",
        themes=("Open source",),
        start_value=100,
        target=500,
        year=2025,
        values=((date(2025, 11, 2), 530),),
    )
    return rows, goal


def _key_result(title: str, value: float, at: str) -> dict[str, object]:
    return {
        "key_result_id": title,
        "goal_id": None,
        "goal_title": "Goal",
        "metric": "Stars",
        "update_source": "manual",
        "start_value": 100,
        "base_value": 100,
        "latest_value": value,
        "latest_at": at,
        "status": "active",
        "entered_in_review": False,
        "after_month_end": False,
        "target": 500,
        "deadline": "2025-12-31",
        "past_deadline": False,
        "retired": False,
        "theme_ids": [],
        "shared": False,
        "flags": [],
    }


async def test_review_of_a_past_year(env) -> None:
    rows, key_result = await _prepare(env)
    user_id = await env.user_id()
    async with env.db() as db:
        for month in range(1, 13):
            await store_snapshot(
                db,
                user_id,
                f"2025-{month:02d}",
                make_snapshot(
                    f"2025-{month:02d}",
                    themes=[
                        {
                            "project_id": str(rows["Open source"].id),
                            "name": "Open source",
                            "target": 2,
                            "done": 1,
                            "status": "in_focus",
                            "milestones": [
                                {
                                    "milestone_id": f"m{month}",
                                    "name": f"Ship {month}",
                                    "done_on": f"2025-{month:02d}-08",
                                }
                            ],
                        }
                    ],
                    categories={
                        "goal_aligned": 10,
                        "maintenance": 5,
                        "off_plan": 5,
                        "hidden": 1,
                    },
                    key_results=[
                        _key_result(
                            str(key_result.id),
                            100 + month * 40,
                            f"2025-{month:02d}-08T12:00:00Z",
                        )
                    ],
                ),
            )

    async with env.db() as db:
        review = await env.app.state.annual_review_service.review(db, user_id, 2025)
    assert review["state"] == "past"
    assert review["coverage"]["stored"] == 12
    goal = review["goals"][0]
    found = goal["key_results"][0]
    assert found["outcome"] == "hit"
    assert found["last_value"] == 580
    assert found["last_month"] == "2025-12"
    assert len(found["series"]) == 12
    assert found["deadline_line"]["state"] == "reached"
    assert found["themes"][0]["shipped"] == 12
    assert review["split"]["months_covered"] == 12
    assert review["split"]["counts"]["goal_aligned"] == 120
    assert review["split"]["counts"]["maintenance"] == 60
    assert review["split"]["counts"]["off_plan"] == 60
    assert review["split"]["hidden"] == 12
    assert review["milestones_shipped"]["count"] == 12
    assert review["year_note"] is None


async def test_note_is_returned_on_the_review(env) -> None:
    rows, key_result = await _prepare(env)
    user_id = await env.user_id()
    async with env.db() as db:
        goal = (await db.execute(select(Goal))).scalars().first()
        await store_snapshot(
            db,
            user_id,
            "2025-01",
            make_snapshot(
                "2025-01",
                key_results=[
                    _key_result(str(key_result.id), 150, "2025-01-08T12:00:00Z")
                ],
            ),
        )
        await store_review_note(db, user_id, 2025, goal_id=None, body="A year of learning.")
        await store_review_note(db, user_id, 2025, goal_id=goal.id, body="Talks went well.")

    async with env.db() as db:
        review = await env.app.state.annual_review_service.review(db, user_id, 2025)
    assert review["year_note"]["body"] == "A year of learning."
    assert review["goals"][0]["note"]["body"] == "Talks went well."


async def test_no_snapshots_still_lists_goals(env) -> None:
    env.app.state.clock = lambda: TODAY_AT
    env.app.state.key_result_service._clock = lambda: TODAY_AT
    rows = await setup_review(env, "Open source")
    await add_key_result(
        env,
        rows,
        metric="Stars",
        themes=("Open source",),
        start_value=100,
        target=500,
        year=2025,
    )
    user_id = await env.user_id()
    async with env.db() as db:
        review = await env.app.state.annual_review_service.review(db, user_id, 2025)
    assert review["empty"]["reason"] == "no_snapshots"
    assert review["coverage"]["stored"] == 0
    found = review["goals"][0]["key_results"][0]
    assert found["outcome"] == "no_value"
    assert found["last_value"] is None
    assert all(point["value"] is None for point in found["series"])


async def test_current_year_is_in_progress(env) -> None:
    env.app.state.clock = lambda: TODAY_AT
    env.app.state.key_result_service._clock = lambda: TODAY_AT
    rows = await setup_review(env, "Open source")
    await add_key_result(
        env,
        rows,
        metric="Stars",
        themes=("Open source",),
        start_value=100,
        target=500,
        year=2026,
    )
    user_id = await env.user_id()
    async with env.db() as db:
        await store_snapshot(
            db,
            user_id,
            "2026-01",
            make_snapshot("2026-01"),
        )
        review = await env.app.state.annual_review_service.review(db, user_id, 2026)
    assert review["state"] == "current"
    assert review["in_progress"] is True
    assert review["goals"][0]["key_results"][0]["outcome"] == "in_progress"
    assert review["coverage"]["expected"] == 11


async def test_future_year(env) -> None:
    user_id = await env.user_id()
    async with env.db() as db:
        review = await env.app.state.annual_review_service.review(db, user_id, 2028)
    assert review["empty"]["reason"] == "future_year"
    assert review["goals"] == []
    assert review["next_year"]["available"] is False


async def test_api_returns_the_review_with_enum_values(env) -> None:
    rows, key_result = await _prepare(env)
    user_id = await env.user_id()
    async with env.db() as db:
        await store_snapshot(
            db,
            user_id,
            "2025-01",
            make_snapshot(
                "2025-01",
                key_results=[
                    _key_result(str(key_result.id), 150, "2025-01-08T12:00:00Z")
                ],
            ),
        )
    response = await env.api.get("/api/v1/annual-review/2025")
    assert response.status_code == 200, response.text
    body = response.json()
    assert body["state"] == "past"
    assert body["goals"][0]["key_results"][0]["outcome"] == "missed"
    assert body["months"][0]["status"] == "stored"
    assert body["split"]["months"][0]["percentages"] is not None
