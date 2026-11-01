"""Review latency target (SC-008): a review of a year of goals and tasks opens in under 5 s."""

import time
import uuid
from datetime import UTC, date, datetime, timedelta

from httpx import AsyncClient
from sqlalchemy import update

from tefteri.db.models.task import Task
from tefteri.domain.entities import RemoteTask
from tests.conftest import V1, connect_all
from tests.fakes.world import FakeWorld

LIMIT_SECONDS = 5


async def _goal(api: AsyncClient, kind: str, start: date, title: str, parent: str | None) -> str:
    r = await api.post(
        f"{V1}/goals",
        json={
            "period_type": kind,
            "period_start": start.isoformat(),
            "title": title,
            "parent_id": parent,
        },
    )
    assert r.status_code == 201, r.text
    goal_id: str = r.json()["id"]
    return goal_id


async def test_year_review_opens_in_time(api: AsyncClient, world: FakeWorld) -> None:
    fake = world.tasks["default"]
    start = datetime(2025, 1, 1, 9, tzinfo=UTC)
    for i in range(2000):
        fake.tasks[f"t{i}"] = RemoteTask(
            f"t{i}", "p1", f"Task {i}", "v1", done=i % 3 == 0, due_at=start + timedelta(hours=4 * i)
        )
    await connect_all(api)
    await api.post(f"{V1}/sync")

    year = await _goal(api, "year", date(2025, 1, 1), "2025", None)
    week_ids: list[str] = []
    for month in range(1, 13):
        month_id = await _goal(api, "month", date(2025, month, 1), f"Month {month}", year)
        monday = date(2025, month, 1) + timedelta(days=(7 - date(2025, month, 1).weekday()) % 7)
        while monday.month == month:
            week_ids.append(await _goal(api, "week", monday, f"Week {monday}", month_id))
            monday += timedelta(days=7)
    async with api.app.state.session_factory() as db:  # type: ignore[attr-defined]
        for i, week in enumerate(week_ids):
            await db.execute(
                update(Task)
                .where(Task.remote_id.in_([f"t{n}" for n in range(i, 2000, len(week_ids))]))
                .values(goal_id=uuid.UUID(week))
            )
        await db.commit()
    plan = (
        await api.post(
            f"{V1}/plans",
            json={"period_type": "year", "period_start": "2025-01-01", "title": "2025"},
        )
    ).json()

    for params in ({}, {"refresh": True}):
        started = time.perf_counter()
        r = await api.get(f"{V1}/plans/{plan['id']}/review", params=params)
        elapsed = time.perf_counter() - started
        assert r.status_code == 200, r.text
        assert r.json()["planned_count"] == 2001  # the year goal and every task
        assert elapsed < LIMIT_SECONDS, f"review took {elapsed:.1f} s"
