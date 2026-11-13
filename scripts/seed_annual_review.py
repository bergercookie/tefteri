#!/usr/bin/env python3
"""Seed a demo database with fake annual-review data (spec 008, constitution II).

The script writes fake data only: one demo user, three years of goals and key results, theme
links, and monthly review snapshots. It never talks to a task app. Run it through
``just backend::seed-annual-review``.
"""

from __future__ import annotations

import asyncio
import os
import sys
import uuid
from datetime import UTC, date, datetime
from pathlib import Path

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine

BACKEND = Path(__file__).resolve().parents[1] / "backend"
sys.path.insert(0, str(BACKEND / "src"))

from tefteri.auth.passwords import hash_password  # noqa: E402
from tefteri.db.models.goal import Goal  # noqa: E402
from tefteri.db.models.key_result import KeyResult, KeyResultTheme  # noqa: E402
from tefteri.db.models.monthly import MonthlyReview, MonthlyReviewSnapshot  # noqa: E402
from tefteri.db.models.project_label import ProjectLabel  # noqa: E402
from tefteri.db.models.user import User  # noqa: E402

USERNAME = "annual-review-demo"
PASSWORD = "annual-review-demo-password"  # noqa: S105 - fake, throw-away demo password


async def seed(db: AsyncSession, year: int) -> None:
    """Write the demo user, goals and snapshots."""
    user = (await db.execute(select(User).where(User.username == USERNAME))).scalar_one_or_none()
    if user is None:
        user = User(
            username=USERNAME,
            password_hash=hash_password(PASSWORD),
            is_admin=False,
            timezone="UTC",
        )
        db.add(user)
        await db.flush()

    now = datetime.now(UTC)
    connection_id = uuid.uuid4()
    themes = {}
    for name in ("Open source", "Health"):
        row = ProjectLabel(
            user_id=user.id,
            connection_id=connection_id,
            remote_id=f"demo-{uuid.uuid4()}",
            name=name,
            label="theme",
        )
        db.add(row)
        await db.flush()
        themes[name] = row

    goal = Goal(
        user_id=user.id,
        period_type="year",
        period_start=date(year, 1, 1),
        title="Get better at open source",
        status="active",
        position=0,
    )
    db.add(goal)
    await db.flush()
    key_result = KeyResult(
        user_id=user.id,
        goal_id=goal.id,
        year=year,
        metric="Stars on one repository",
        start_value=120,
        target=500,
        deadline=date(year, 12, 31),
        update_source="manual",
        status="active",
        slot=1,
        position=0,
    )
    db.add(key_result)
    await db.flush()
    db.add(
        KeyResultTheme(
            user_id=user.id,
            key_result_id=key_result.id,
            project_id=themes["Open source"].id,
            year=year,
            started_at=datetime.combine(date(year, 1, 1), datetime.min.time(), UTC),
        )
    )
    retired_goal = Goal(
        user_id=user.id,
        period_type="year",
        period_start=date(year, 1, 1),
        title="Run a half marathon",
        status="retired",
        retired_at=datetime(year, 6, 15, tzinfo=UTC),
        retired_reason="The plan changed.",
        position=1,
    )
    db.add(retired_goal)
    await db.flush()

    for month in range(1, 13):
        if month in (3, 4, 9, 10):
            continue
        start = date(year, month, 1)
        review = MonthlyReview(
            user_id=user.id,
            month=start,
            current_version=1,
            current_changed_at=now,
        )
        db.add(review)
        await db.flush()
        value = 120 + month * 28
        payload = {
            "schema_version": 1,
            "month": start.isoformat(),
            "taken_at": f"{year}-{month:02d}-28T12:00:00Z",
            "themes": [
                {
                    "project_id": str(themes["Open source"].id),
                    "name": "Open source",
                    "target": 2,
                    "done": 1,
                    "status": "in_focus",
                    "orphaned": None,
                    "milestones": [
                        {
                            "milestone_id": f"demo-{month}",
                            "name": f"Ship demo {month}",
                            "done_on": f"{year}-{month:02d}-08",
                        }
                    ],
                    "key_result_ids": [str(key_result.id)],
                }
            ],
            "outside_focus": [],
            "categories": {
                "goal_aligned": 12,
                "maintenance": 4,
                "off_plan": 3,
                "hidden": 1,
            },
            "key_results": [
                {
                    "key_result_id": str(key_result.id),
                    "start_value": 120,
                    "base_value": value - 20,
                    "latest_value": value,
                    "latest_at": f"{year}-{month:02d}-08T12:00:00Z",
                    "target": 500,
                    "deadline": f"{year}-12-31",
                    "status": "active",
                    "retired": False,
                }
            ],
        }
        db.add(
            MonthlyReviewSnapshot(
                review_id=review.id,
                version=1,
                schema_version=1,
                payload=payload,
                values_written=[],
                created_at=now,
            )
        )
    await db.commit()


async def main() -> None:
    """Open the configured database and seed the previous and current years."""
    url = os.environ.get("TEFTERI_DATABASE_URL", "")
    if not url or "demo" not in url:
        raise SystemExit(
            "Set TEFTERI_DATABASE_URL to an absolute sqlite file whose name includes 'demo'."
        )
    engine = create_async_engine(url)
    factory = async_sessionmaker(engine, expire_on_commit=False)
    async with factory() as db:
        today = date.today()
        await seed(db, today.year - 1)
        await seed(db, today.year)
    await engine.dispose()
    print(f"Demo data written. Sign in as {USERNAME} with password {PASSWORD}.")


if __name__ == "__main__":
    asyncio.run(main())
