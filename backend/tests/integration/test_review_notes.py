"""Integration tests of review notes (spec 008, FR-017)."""

from datetime import UTC, date, datetime

from sqlalchemy import select

from tefteri.db.models.goal import Goal
from tests.integration.conftest import legacy_goal
from tests.integration.monthly_review_helpers import add_key_result, setup_review

TODAY_AT = datetime(2026, 11, 13, 12, tzinfo=UTC)


async def _goal(env):
    env.app.state.clock = lambda: TODAY_AT
    env.app.state.key_result_service._clock = lambda: TODAY_AT
    rows = await setup_review(env, "Open source")
    key_result = await add_key_result(
        env,
        rows,
        metric="Stars",
        themes=("Open source",),
        year=2025,
    )
    async with env.db() as db:
        goal = (
            await db.execute(select(Goal).where(Goal.id == key_result.goal_id))
        ).scalar_one()
    return goal


async def test_put_replace_delete_and_undo(env) -> None:
    goal = await _goal(env)
    put = await env.api.put(
        "/api/v1/annual-review/2025/notes", json={"goal_id": None, "body": "  A year.  "}
    )
    assert put.status_code == 200, put.text
    assert put.json()["body"] == "A year."
    assert put.json()["goal_id"] is None

    replaced = await env.api.put(
        "/api/v1/annual-review/2025/notes", json={"goal_id": None, "body": "A better year."}
    )
    assert replaced.json()["id"] == put.json()["id"]

    goal_note = await env.api.put(
        "/api/v1/annual-review/2025/notes",
        json={"goal_id": str(goal.id), "body": "Talks went well."},
    )
    assert goal_note.status_code == 200, goal_note.text

    review = await env.api.get("/api/v1/annual-review/2025")
    assert review.json()["year_note"]["body"] == "A better year."
    assert review.json()["goals"][0]["note"]["body"] == "Talks went well."

    deleted = await env.api.delete("/api/v1/annual-review/2025/notes")
    assert deleted.status_code == 200, deleted.text
    assert deleted.json()["deleted"]["body"] == "A better year."

    undo = await env.api.put(
        "/api/v1/annual-review/2025/notes",
        json={"goal_id": None, "body": deleted.json()["deleted"]["body"]},
    )
    assert undo.status_code == 200
    assert undo.json()["body"] == "A better year."


async def test_invalid_and_not_found_notes(env) -> None:
    goal = await _goal(env)
    empty = await env.api.put(
        "/api/v1/annual-review/2025/notes", json={"goal_id": None, "body": "   "}
    )
    assert empty.status_code == 422
    assert empty.json()["code"] == "invalid"

    too_long = await env.api.put(
        "/api/v1/annual-review/2025/notes", json={"goal_id": None, "body": "x" * 2001}
    )
    assert too_long.status_code == 422

    other_year = await env.api.put(
        "/api/v1/annual-review/2024/notes",
        json={"goal_id": str(goal.id), "body": "Wrong year"},
    )
    assert other_year.status_code == 404
    assert other_year.json()["code"] == "not_found"

    missing = await env.api.delete("/api/v1/annual-review/2025/notes")
    assert missing.status_code == 404


async def test_a_future_year_is_refused(env) -> None:
    await _goal(env)
    future = await env.api.put(
        "/api/v1/annual-review/2028/notes", json={"goal_id": None, "body": "Too soon."}
    )
    assert future.status_code == 409
    assert future.json()["code"] == "future_year"


async def test_a_month_goal_is_not_a_note_scope(env) -> None:
    await _goal(env)
    month_goal = await legacy_goal(
        env.api, period_type="month", period_start=date(2025, 3, 1)
    )
    response = await env.api.put(
        "/api/v1/annual-review/2025/notes",
        json={"goal_id": str(month_goal), "body": "No."},
    )
    assert response.status_code == 404
