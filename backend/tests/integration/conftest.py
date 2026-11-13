"""Fixtures for the integration tests of project classification (spec 003)."""

import uuid
from collections.abc import AsyncIterator
from contextlib import asynccontextmanager
from datetime import UTC, date, datetime
from typing import TYPE_CHECKING, Any

import pytest
from httpx import AsyncClient
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from tefteri.db.models.goal import Goal
from tefteri.db.models.monthly import MonthlyReview, MonthlyReviewSnapshot
from tefteri.db.models.project_label import ProjectLabel as ProjectLabelRow
from tefteri.db.models.project_label import ProjectLabelHistory
from tefteri.db.models.review_note import ReviewNote
from tefteri.db.models.user import User
from tefteri.db.session import session_scope
from tefteri.domain.entities import Container, TaskDraft
from tefteri.services.classification import ClassificationService
from tests.conftest import V1, connect_all
from tests.fakes.world import FakeWorld

if TYPE_CHECKING:
    from tests.integration.weekly_helpers import Weekly


class ProjectsEnv:
    """The app under test, its fake task app, and a way to run services on one session."""

    def __init__(self, api: AsyncClient, world: FakeWorld) -> None:
        self.api = api
        self.world = world
        self.app: Any = api.app  # type: ignore[attr-defined]
        self.classification: ClassificationService = self.app.state.classification_service
        self.connection_id = ""

    @asynccontextmanager
    async def db(self) -> AsyncIterator[AsyncSession]:
        """A session that commits when the block ends, as a request does."""
        async with session_scope(self.app.state.session_factory) as session:
            yield session

    async def user_id(self) -> uuid.UUID:
        async with self.db() as db:
            user = (await db.execute(select(User).where(User.username == "admin"))).scalar_one()
            return user.id

    async def connect(
        self, *containers: Container, tasks: dict[str, int] | None = None
    ) -> uuid.UUID:
        """Add ``containers`` to the fake task app, give ``tasks`` open tasks, connect and sync."""
        backend = self.world.tasks["default"]
        backend.containers.extend(containers)
        for remote_id, count in (tasks or {}).items():
            for n in range(count):
                await backend.create_task(TaskDraft(remote_id, f"{remote_id} task {n}"))
        ids = await connect_all(self.api)
        self.connection_id = ids["vikunja"]
        return uuid.UUID(ids["vikunja"])

    def connection_uuid(self) -> uuid.UUID:
        return uuid.UUID(self.connection_id)

    async def sync(self) -> None:
        r = await self.api.post(f"{V1}/sync")
        assert r.status_code == 200, r.text

    async def rows(self) -> dict[str, ProjectLabelRow]:
        """The label rows by project name."""
        async with self.db() as db:
            found = (await db.execute(select(ProjectLabelRow))).scalars().all()
        return {r.name: r for r in found}

    async def history(self, name: str) -> list[ProjectLabelHistory]:
        """The history of a project, oldest first."""
        async with self.db() as db:
            row = (
                await db.execute(select(ProjectLabelRow).where(ProjectLabelRow.name == name))
            ).scalar_one()
            return list(
                (
                    await db.execute(
                        select(ProjectLabelHistory)
                        .where(ProjectLabelHistory.project_id == row.id)
                        .order_by(ProjectLabelHistory.from_at)
                    )
                ).scalars()
            )


async def legacy_goal(
    api: AsyncClient,
    *,
    period_type: str,
    period_start: date,
    title: str = "Old goal",
    status: str = "active",
    parent_id: uuid.UUID | None = None,
    criteria: str = "",
    description: str = "",
    username: str = "admin",
) -> uuid.UUID:
    """Insert a ``Goal`` row directly, for tests of old data (spec 006, T050).

    The write routes of month and week goals are gone; old rows still exist in real databases,
    so tests that need them insert them through the session.
    """
    app: Any = api.app  # type: ignore[attr-defined]
    async with session_scope(app.state.session_factory) as db:
        user = (await db.execute(select(User).where(User.username == username))).scalar_one()
        goal = Goal(
            user_id=user.id,
            parent_id=parent_id,
            period_type=period_type,
            period_start=period_start,
            title=title,
            description=description,
            criteria=criteria,
            status=status,
        )
        db.add(goal)
        await db.flush()
        return goal.id


@pytest.fixture
def env(api: AsyncClient, world: FakeWorld) -> ProjectsEnv:
    return ProjectsEnv(api, world)


@pytest.fixture
def weekly(env: ProjectsEnv) -> "Weekly":
    from tests.integration.weekly_helpers import Weekly

    return Weekly(env)


def make_snapshot(
    month: str,
    *,
    themes: list[dict[str, Any]] | None = None,
    outside_focus: list[dict[str, Any]] | None = None,
    categories: dict[str, int] | None = None,
    key_results: list[dict[str, Any]] | None = None,
    schema_version: int = 1,
    taken_at: str | None = None,
    **extra: object,
) -> dict[str, Any]:
    """Build a schema-version-one snapshot payload with useful defaults (R-15)."""
    payload: dict[str, Any] = {
        "schema_version": schema_version,
        "month": f"{month}-01" if len(month) == 7 else month,
        "taken_at": taken_at,
        "themes": themes or [],
        "outside_focus": outside_focus or [],
        "categories": categories
        or {"goal_aligned": 0, "maintenance": 0, "off_plan": 0, "hidden": 0},
        "key_results": key_results or [],
    }
    payload.update(extra)
    return payload


async def store_snapshot(
    db: AsyncSession,
    user_id: uuid.UUID,
    month: str,
    payload: dict[str, Any],
    *,
    version: int = 1,
) -> None:
    """Store one snapshot version directly, as feature 007 would (R-15)."""
    start = date.fromisoformat(f"{month}-01" if len(month) == 7 else month)
    header = (
        await db.execute(
            select(MonthlyReview).where(
                MonthlyReview.user_id == user_id, MonthlyReview.month == start
            )
        )
    ).scalar_one_or_none()
    now = datetime.now(UTC)
    if header is None:
        header = MonthlyReview(
            user_id=user_id,
            month=start,
            current_version=version,
            current_changed_at=now,
            created_at=now,
        )
        db.add(header)
        await db.flush()
    else:
        header.current_version = version
        header.current_changed_at = now
    db.add(
        MonthlyReviewSnapshot(
            review_id=header.id,
            version=version,
            schema_version=int(payload.get("schema_version", 1) or 1),
            payload=payload,
            values_written=[],
            created_at=now,
        )
    )
    await db.flush()


async def store_review_note(
    db: AsyncSession,
    user_id: uuid.UUID,
    year: int,
    *,
    goal_id: uuid.UUID | None,
    body: str,
) -> ReviewNote:
    """Store one review note directly for tests of the read model."""
    now = datetime.now(UTC)
    note = ReviewNote(
        user_id=user_id,
        year=year,
        goal_id=goal_id,
        body=body,
        created_at=now,
        updated_at=now,
    )
    db.add(note)
    await db.flush()
    return note
