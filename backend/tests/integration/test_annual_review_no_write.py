"""The review changes no row and reads no task table (spec 008, FR-001, FR-014, SC-002)."""

import hashlib
from datetime import UTC, datetime
from pathlib import Path

from sqlalchemy import text

from tefteri.db.base import Base
from tests.integration.conftest import make_snapshot, store_snapshot
from tests.integration.monthly_review_helpers import add_key_result, setup_review

TODAY_AT = datetime(2026, 11, 13, 12, tzinfo=UTC)


async def _digest(db) -> str:
    digest = hashlib.sha256()
    for table in sorted(Base.metadata.tables):
        digest.update(table.encode())
        rows = (await db.execute(text(f"select * from {table}"))).all()
        digest.update(repr(rows).encode())
    return digest.hexdigest()


async def test_opening_the_review_changes_no_row(env) -> None:
    env.app.state.clock = lambda: TODAY_AT
    env.app.state.key_result_service._clock = lambda: TODAY_AT
    rows = await setup_review(env, "Open source")
    key_result = await add_key_result(
        env, rows, metric="Stars", themes=("Open source",), year=2025
    )
    user_id = await env.user_id()
    async with env.db() as db:
        await store_snapshot(
            db,
            user_id,
            "2025-01",
            make_snapshot("2025-01", key_results=[
                {
                    "key_result_id": str(key_result.id),
                    "start_value": 0,
                    "base_value": 0,
                    "latest_value": 30,
                    "latest_at": "2025-01-08T12:00:00Z",
                    "target": 100,
                    "deadline": "2025-12-31",
                    "status": "active",
                    "retired": False,
                }
            ]),
        )
    async with env.db() as db:
        before = await _digest(db)
        for year in (2024, 2025, 2026):
            await env.app.state.annual_review_service.review(db, user_id, year)
        after = await _digest(db)
    assert before == after


def test_the_review_source_has_no_write_and_no_task_read() -> None:
    source = (
        Path(__file__).parents[2] / "src" / "tefteri" / "services" / "annual_review.py"
    ).read_text()
    domain = (
        Path(__file__).parents[2] / "src" / "tefteri" / "domain" / "annual_review.py"
    ).read_text()
    combined = (source + domain).lower()
    for word in ("insert(", "update(", "delete("):
        assert word not in combined
    for table in ("tasks", "milestones", "weekly_plans"):
        assert f"select({table}" not in combined
        assert f"from tefteri.db.models.{table}" not in combined
        assert f"dbtable = '{table}'" not in combined
