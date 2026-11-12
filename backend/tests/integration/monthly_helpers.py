"""Shared fixtures for the monthly-focus integration tests."""

from datetime import UTC, date, datetime
from typing import Any

from sqlalchemy import select

from tefteri.db.models.milestone import Milestone
from tefteri.db.models.project_label import ProjectLabel as ProjectLabelRow
from tefteri.domain.entities import Container
from tefteri.domain.enums import ProjectLabel
from tests.integration.conftest import ProjectsEnv
from tests.integration.weekly_helpers import Weekly

MONTH = date(2030, 3, 1)
TODAY = datetime(2030, 3, 15, 12, tzinfo=UTC)


async def setup_month(env: ProjectsEnv, *containers: Container) -> dict[str, ProjectLabelRow]:
    """Create and classify project fixtures for a March 2030 test."""
    env.app.state.clock = lambda: TODAY
    await env.connect(*containers)
    await Weekly(env).label(
        **{
            container.name: "theme"
            for container in containers
            if container.parent_id is None and container.name != "Unsorted"
        }
    )
    return await env.rows()


async def label(env: ProjectsEnv, name: str, kind: ProjectLabel | None) -> None:
    """Change one project's classification through the feature 003 service."""
    row = (await env.rows())[name]
    from tefteri.services.classification import Change

    async with env.db() as db:
        await env.classification.save(db, await env.user_id(), [Change(row.id, kind)])


async def done_milestone(
    env: ProjectsEnv,
    project_name: str,
    *,
    done_on: date,
    theme_name: str | None,
    state: str = "done",
) -> Milestone:
    """Insert a milestone result using feature 004's stored theme-at-done facts."""
    rows = await env.rows()
    project = rows[project_name]
    theme = rows[theme_name] if theme_name else None
    milestone = Milestone(
        user_id=await env.user_id(),
        project_id=project.id,
        state=state,
        done_on=done_on if state == "done" else None,
        done_by="user" if state == "done" else None,
        done_theme_id=theme.id if state == "done" and theme else None,
        done_theme_name=theme.name if state == "done" and theme else None,
    )
    async with env.db() as db:
        db.add(milestone)
        await db.flush()
    return milestone


async def load_milestones(env: ProjectsEnv) -> list[Milestone]:
    """Return all milestone fixtures."""
    async with env.db() as db:
        return list((await db.execute(select(Milestone))).scalars())


def project_ids(rows: dict[str, ProjectLabelRow], *names: str) -> list[Any]:
    """Return label ids in the requested order."""
    return [rows[name].id for name in names]
