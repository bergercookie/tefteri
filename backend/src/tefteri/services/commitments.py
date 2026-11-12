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


class WeeklyCommitments:
    """Read the commitment from the weekly plans of feature 004."""

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
