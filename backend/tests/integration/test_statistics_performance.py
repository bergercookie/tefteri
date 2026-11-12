"""Speed of the statistics and of the recorder (SC-003, spec 005)."""

import time
import uuid
from datetime import UTC, datetime, timedelta

from sqlalchemy import event, insert

from tefteri.db.models.connection import SourceContainer
from tefteri.db.models.task import Task
from tests.integration.conftest import ProjectsEnv
from tests.integration.stats_helpers import WEEK, Stats

WEEK_SECONDS = 2.0
YEAR_SECONDS = 3.0
RECORDER_SECONDS = 30.0
RECORDER_SELECTS = 80
"""A fixed number of reads plus one commitment read per week (about 53), never one per task."""


async def _insert_done_tasks(env: ProjectsEnv, n: int, start: datetime, step: timedelta) -> None:
    """Put ``n`` done tasks into the cache with one bulk insert, spread over the projects."""
    async with env.db() as db:
        user_id = await env.user_id()
        containers = list(
            (
                await db.execute(
                    SourceContainer.__table__.select().where(SourceContainer.user_id == user_id)
                )
            ).all()
        )
        connection_id = containers[0].connection_id
        rows = [
            {
                "id": uuid.uuid4(),
                "user_id": user_id,
                "connection_id": connection_id,
                "container_id": containers[i % len(containers)].id,
                "remote_id": f"bulk-{i}",
                "title": f"Bulk {i}",
                "description": "",
                "status": "done",
                "completed_at": start + step * i,
                "all_day": False,
                "labels": [],
                "remote_version": "v1",
                "sync_state": "synced",
            }
            for i in range(n)
        ]
        for i in range(0, n, 1000):
            await db.execute(insert(Task), rows[i : i + 1000])


async def test_a_week_of_a_thousand_tasks_returns_counts_and_the_first_page_fast(
    env: ProjectsEnv,
) -> None:
    s = Stats(env)
    await s.standard()
    await _insert_done_tasks(
        env, 1000, datetime(2030, 3, 4, 0, 0, tzinfo=UTC), timedelta(minutes=9)
    )
    async with env.db() as db:
        await env.app.state.category_recorder.record_new(db, await env.user_id(), {})
    started = time.perf_counter()
    stats = await s.stats("week", WEEK)
    page = await s.page(period="week", day=str(WEEK), limit=50)
    elapsed = time.perf_counter() - started
    assert stats["total"] + stats["hidden"] == 1000 and len(page["items"]) == 50
    assert elapsed < WEEK_SECONDS, f"{elapsed:.2f} s"


async def test_a_year_of_20000_tasks_returns_counts_parts_and_percentages_fast(
    env: ProjectsEnv,
) -> None:
    s = Stats(env)
    await s.standard()
    await _insert_done_tasks(env, 20000, datetime(2030, 1, 1, tzinfo=UTC), timedelta(minutes=26))
    async with env.db() as db:
        started = time.perf_counter()
        statements: list[str] = []
        engine = env.app.state.session_factory.kw["bind"].sync_engine

        def record(_c: object, _cur: object, statement: str, *_a: object) -> None:
            statements.append(statement.lstrip())

        event.listen(engine, "before_cursor_execute", record)
        try:
            written = await env.app.state.category_recorder.record_new(db, await env.user_id(), {})
        finally:
            event.remove(engine, "before_cursor_execute", record)
        recorded = time.perf_counter() - started
    assert written == 20000
    selects = sum(q.upper().startswith("SELECT") for q in statements)
    assert selects < RECORDER_SELECTS, selects  # not one query per task
    assert recorded < RECORDER_SECONDS, f"recorder: {recorded:.1f} s"
    started = time.perf_counter()
    stats = await s.stats("year", datetime(2030, 6, 1).date())
    elapsed = time.perf_counter() - started
    assert stats["total"] + stats["hidden"] == 20000 and len(stats["parts"]) == 12
    assert sum(stats["percentages"].values()) == 100
    assert elapsed < YEAR_SECONDS, f"{elapsed:.2f} s"
