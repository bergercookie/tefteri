"""The weekly commitment, as far as the work categories need to read it (spec 005, R-05).

``CommitmentProvider`` is the seam. The recorder reads the commitment of the week in which a task
was completed through it, so a unit test can prove that tefteri never guesses a category when the
weekly commitment cannot be read (FR-026). ``WeeklyCommitments`` reads the plans of feature 004.
"""

import uuid
from datetime import date
from typing import Protocol

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import aliased

from tefteri.db.models.connection import SourceContainer
from tefteri.db.models.milestone import Milestone
from tefteri.db.models.project_label import ProjectLabel
from tefteri.db.models.weekly import WeeklyPlan, WeeklyPlanProject


class CommitmentProvider(Protocol):
    """Tells which projects the user committed to in a week."""

    async def committed_projects(
        self, db: AsyncSession, user_id: uuid.UUID, week_start: date
    ) -> set[uuid.UUID] | None:
        """Return the ids of the label rows of the projects committed in the week of ``week_start``.

        The set is empty when the week has no committed plan: a draft commits nothing. ``None``
        means that the weekly commitment cannot be read. Then no category is recorded and the
        statistics say so, so that no number is guessed (FR-026).
        """
        ...


async def committed_tasks_by_week(
    provider: CommitmentProvider, db: AsyncSession, user_id: uuid.UUID
) -> dict[date, set[uuid.UUID]]:
    """Return the tasks that each committed plan named, by Monday, in one query.

    A provider that has no ``committed_tasks_by_week`` (a test double that only knows projects)
    names no task, and the rules fall back to the projects.
    """
    method = getattr(provider, "committed_tasks_by_week", None)
    if method is None:
        return {}
    found: dict[date, set[uuid.UUID]] = await method(db, user_id)
    return found


async def committed_task_ids(
    provider: CommitmentProvider, db: AsyncSession, user_id: uuid.UUID, week_start: date
) -> set[uuid.UUID]:
    """Return the tasks that the committed plan of the week named, or none if it cannot say.

    A provider that has no ``committed_tasks`` (a test double that only knows projects) names no
    task, and the rules fall back to the projects.
    """
    method = getattr(provider, "committed_tasks", None)
    if method is None:
        return set()
    found: set[uuid.UUID] = await method(db, user_id, week_start)
    return found


class WeeklyCommitments:
    """Read the commitment from the weekly plans of feature 004."""

    async def committed_tasks(
        self, db: AsyncSession, user_id: uuid.UUID, week_start: date
    ) -> set[uuid.UUID]:
        """Return the ids of the tasks that were planned when the week was committed.

        They stay in the set when the task moves to another project later, for example when its
        milestone is closed and the open tasks return to the theme.
        """
        return (await self._read(db, user_id, week_start)).get(week_start, set())

    async def committed_tasks_by_week(
        self, db: AsyncSession, user_id: uuid.UUID
    ) -> dict[date, set[uuid.UUID]]:
        """Return the committed tasks of every committed week, by Monday, in one query."""
        return await self._read(db, user_id, None)

    @staticmethod
    async def _read(
        db: AsyncSession, user_id: uuid.UUID, week_start: date | None
    ) -> dict[date, set[uuid.UUID]]:
        query = (
            select(WeeklyPlan.week_start, WeeklyPlanProject.committed_task_ids)
            .join(WeeklyPlan, WeeklyPlan.id == WeeklyPlanProject.plan_id)
            .where(WeeklyPlan.user_id == user_id, WeeklyPlan.status == "committed")
        )
        if week_start is not None:
            query = query.where(WeeklyPlan.week_start == week_start)
        found: dict[date, set[uuid.UUID]] = {}
        for week, ids in (await db.execute(query)).all():
            tasks = found.setdefault(week, set())
            for raw in ids or []:
                try:
                    tasks.add(uuid.UUID(raw))
                except ValueError:
                    continue
        return found

    async def committed_projects(
        self, db: AsyncSession, user_id: uuid.UUID, week_start: date
    ) -> set[uuid.UUID]:
        """Return the projects of the committed plan of the week.

        An entry points at its project through ``milestone_id`` (feature 004), or, for an entry
        from before that feature, through its container. A milestone that was parked, closed or
        done during the week is still in the set (spec 005, edge cases).
        """
        by_container = aliased(ProjectLabel)
        rows = (
            await db.execute(
                select(Milestone.project_id, by_container.id)
                .select_from(WeeklyPlanProject)
                .join(WeeklyPlan, WeeklyPlan.id == WeeklyPlanProject.plan_id)
                .outerjoin(Milestone, Milestone.id == WeeklyPlanProject.milestone_id)
                .outerjoin(SourceContainer, SourceContainer.id == WeeklyPlanProject.container_id)
                .outerjoin(
                    by_container,
                    (by_container.connection_id == SourceContainer.connection_id)
                    & (by_container.remote_id == SourceContainer.remote_id),
                )
                .where(
                    WeeklyPlan.user_id == user_id,
                    WeeklyPlan.week_start == week_start,
                    WeeklyPlan.status == "committed",
                )
            )
        ).all()
        found: set[uuid.UUID] = set()
        for milestone_project, container_project in rows:
            project = milestone_project or container_project
            if project is not None:
                found.add(project)
        return found
