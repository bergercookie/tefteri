"""Helpers for the integration tests of work categories and statistics (spec 005)."""

from dataclasses import replace
from datetime import UTC, date, datetime, timedelta
from typing import Any

from httpx import AsyncClient
from sqlalchemy import select

from tefteri.db.models.task import Task
from tefteri.db.models.task_category import TaskCategory
from tefteri.domain.entities import Container, RemoteTask, TaskDraft
from tests.conftest import V1
from tests.fakes.world import FakeWorld
from tests.integration.conftest import ProjectsEnv
from tests.integration.weekly_helpers import NEXT, WEEK, Weekly

__all__ = [
    "NEXT",
    "WEEK",
    "Stats",
    "at",
]


def at(day: int, hour: int = 10, minute: int = 0) -> datetime:
    """A UTC time in March 2030: ``at(6)`` is Wednesday 6 March, in the week of ``WEEK``."""
    return datetime(2030, 3, day, hour, minute, tzinfo=UTC)


class Stats:
    """Small helpers on top of the app, so that a test reads as the story it tells."""

    def __init__(self, env: ProjectsEnv) -> None:
        self.env = env
        self.api: AsyncClient = env.api
        self.world: FakeWorld = env.world
        self.weekly = Weekly(env)
        self.backend = env.world.tasks["default"]

    async def standard(self) -> None:
        """Connect a world with every kind of project, and label them.

        Open source (theme) holds Login flow and Docs (milestones). Chores (maintenance) holds
        Dishes (no label). Old (ignored) holds Old child. Misc has no label.
        """
        await self.env.connect(
            Container("p2", "Open source"),
            Container("p3", "Login flow", "p2"),
            Container("p4", "Docs", "p2"),
            Container("p5", "Chores"),
            Container("p6", "Dishes", "p5"),
            Container("p7", "Old"),
            Container("p8", "Old child", "p7"),
            Container("p9", "Misc"),
        )
        await self.weekly.label(
            **{
                "Open source": "theme",
                "Login flow": "milestone",
                "Docs": "milestone",
                "Chores": "maintenance",
                "Old": "ignored",
            }
        )

    async def add(self, project: str, title: str) -> None:
        """Create an open task in the project with this remote id (``p3``) in the task app."""
        await self.backend.create_task(TaskDraft(project, title))

    def finish(self, title: str, when: datetime | None) -> None:
        """Mark a task done in the task app at ``when`` (``None``: done with no time)."""
        remote_id, task = next((i, t) for i, t in self.backend.tasks.items() if t.title == title)
        self.backend.tasks[remote_id] = replace(
            task, done=True, done_at=when, version=task.version + "+"
        )

    def reopen(self, title: str) -> None:
        remote_id, task = next((i, t) for i, t in self.backend.tasks.items() if t.title == title)
        self.backend.tasks[remote_id] = replace(
            task, done=False, done_at=None, version=task.version + "+"
        )

    def move(self, title: str, project: str) -> None:
        remote_id, task = next((i, t) for i, t in self.backend.tasks.items() if t.title == title)
        self.backend.tasks[remote_id] = replace(
            task, container_id=project, version=task.version + "+"
        )

    async def done(self, project: str, title: str, when: datetime | None) -> None:
        """Create a task in the project and finish it at once."""
        await self.add(project, title)
        self.finish(title, when)

    def bulk(
        self, project: str, n: int, prefix: str, when: datetime, *, step: timedelta | None = None
    ) -> None:
        """Put ``n`` done tasks into the task app. ``step=None``: all share one completion time."""
        for i in range(n):
            remote_id = f"{prefix}-{i}"
            self.backend.tasks[remote_id] = RemoteTask(
                remote_id,
                project,
                f"{prefix} {i:04d}",
                "v1",
                done=True,
                done_at=when + (step * i if step else timedelta(0)),
            )

    async def rows(self) -> dict[str, TaskCategory]:
        """The stored categories by the title of the task."""
        async with self.env.db() as db:
            found = (
                await db.execute(
                    select(Task.title, TaskCategory)
                    .select_from(Task)
                    .join(TaskCategory, TaskCategory.task_id == Task.id)
                )
            ).all()
        return {title: row for title, row in found}

    async def snapshot(self) -> dict[str, dict[str, Any]]:
        """Every column of every stored row, by task title."""
        return {
            title: {c.name: getattr(row, c.name) for c in TaskCategory.__table__.columns}
            for title, row in (await self.rows()).items()
        }

    async def sync(self) -> None:
        await self.env.sync()

    async def stats(self, period: str, day: date, **params: Any) -> dict[str, Any]:
        r = await self.api.get(
            f"{V1}/statistics", params={"period": period, "day": str(day)} | params
        )
        assert r.status_code == 200, r.text
        body: dict[str, Any] = r.json()
        return body

    async def page(self, **params: Any) -> dict[str, Any]:
        r = await self.api.get(f"{V1}/statistics/tasks", params=params)
        assert r.status_code == 200, r.text
        body: dict[str, Any] = r.json()
        return body

    async def all_tasks(self, limit: int = 50, **params: Any) -> list[dict[str, Any]]:
        """Follow the cursor to the end and return every item."""
        items: list[dict[str, Any]] = []
        cursor: str | None = None
        while True:
            extra = {"cursor": cursor} if cursor else {}
            page = await self.page(limit=limit, **params, **extra)
            items.extend(page["items"])
            cursor = page["next_cursor"]
            if cursor is None:
                return items

    async def titles(self, category: str | None = None, week: date = WEEK) -> list[str]:
        extra: dict[str, Any] = {"category": category} if category else {}
        items = await self.all_tasks(50, period="week", day=str(week), **extra)
        return [t["title"] for t in items]


def week_days(start: date = WEEK) -> list[date]:
    return [start + timedelta(days=i) for i in range(7)]
