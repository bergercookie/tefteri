"""Fixtures for the integration tests of project classification (spec 003)."""

import uuid
from collections.abc import AsyncIterator
from contextlib import asynccontextmanager
from typing import TYPE_CHECKING, Any

import pytest
from httpx import AsyncClient
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from tefteri.db.models.project_label import ProjectLabel as ProjectLabelRow
from tefteri.db.models.project_label import ProjectLabelHistory
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


@pytest.fixture
def env(api: AsyncClient, world: FakeWorld) -> ProjectsEnv:
    return ProjectsEnv(api, world)


@pytest.fixture
def weekly(env: ProjectsEnv) -> "Weekly":
    from tests.integration.weekly_helpers import Weekly

    return Weekly(env)
