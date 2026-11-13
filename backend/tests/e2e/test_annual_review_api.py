"""E2E tests of the annual review API (spec 008, M3)."""

from datetime import UTC, datetime

from sqlalchemy import select

from tefteri.db.models.user import User
from tefteri.db.session import session_scope
from tests.integration.conftest import make_snapshot, store_snapshot

TODAY_AT = datetime(2026, 11, 13, 12, tzinfo=UTC)


async def _store(api) -> None:
    api.app.state.clock = lambda: TODAY_AT
    api.app.state.key_result_service._clock = lambda: TODAY_AT
    async with session_scope(api.app.state.session_factory) as db:
        user = (await db.execute(select(User).where(User.username == "admin"))).scalar_one()
        await store_snapshot(db, user.id, "2025-01", make_snapshot("2025-01"))


async def test_review_shape_for_every_year_state(api) -> None:
    await _store(api)
    past = await api.get("/api/v1/annual-review/2025")
    assert past.status_code == 200, past.text
    body = past.json()
    assert body["state"] == "past"
    assert len(body["months"]) == 12
    assert body["rules"]["hit"] == "last_value_reaches_target"
    assert body["drill_down"] == {
        "live": True,
        "route": "/statistics/tasks",
        "query": {"period": "year", "day": "2025-01-01"},
    }

    current = await api.get("/api/v1/annual-review/2026")
    assert current.status_code == 200
    assert current.json()["state"] == "current"
    assert current.json()["in_progress"] is True
    assert current.json()["empty"]["reason"] == "no_goals"

    future = await api.get("/api/v1/annual-review/2028")
    assert future.status_code == 200
    assert future.json()["empty"]["reason"] == "future_year"
    assert future.json()["next_year"]["available"] is False

    empty = await api.get("/api/v1/annual-review/2024")
    assert empty.status_code == 200
    assert empty.json()["empty"]["reason"] == "no_goals"


async def test_a_year_outside_the_range_is_invalid(api) -> None:
    for year in (1999, 2101):
        response = await api.get(f"/api/v1/annual-review/{year}")
        assert response.status_code == 422
        assert response.json()["code"] == "invalid"


async def test_notes_over_http(api) -> None:
    await _store(api)
    put = await api.put(
        "/api/v1/annual-review/2025/notes", json={"goal_id": None, "body": "A year."}
    )
    assert put.status_code == 200, put.text
    deleted = await api.delete("/api/v1/annual-review/2025/notes")
    assert deleted.status_code == 200
    assert deleted.json()["deleted"]["body"] == "A year."
    missing = await api.delete("/api/v1/annual-review/2025/notes")
    assert missing.status_code == 404


async def test_the_old_year_view_still_answers(api) -> None:
    response = await api.get("/api/v1/views/year/2025")
    assert response.status_code == 200
