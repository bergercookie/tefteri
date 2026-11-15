"""Goals after spec 006: the read-only legacy history.

Goals exist only for a planning year now (``services.annual_plan``). Month and week goals, and
year goals that are retired or were marked complete, stay as read-only history (FR-022, FR-023):
this module reads them and never writes them.
"""

import uuid
from dataclasses import dataclass
from datetime import date

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from tefteri.db.models.goal import Goal
from tefteri.db.models.task import Task
from tefteri.services.errors import NotFound


@dataclass(frozen=True)
class LegacyGoal:
    """One row of ``GET /goals/history``: an old goal and the number of tasks linked to it."""

    goal: Goal
    linked_tasks: int


class GoalService:
    """Read goals and the legacy history. Annual planning owns every write (spec 006)."""

    async def get(self, db: AsyncSession, user_id: uuid.UUID, goal_id: uuid.UUID) -> Goal:
        """Return one of the user's goals or raise ``NotFound``."""
        goal = (
            await db.execute(select(Goal).where(Goal.id == goal_id, Goal.user_id == user_id))
        ).scalar_one_or_none()
        if goal is None:
            raise NotFound
        return goal

    async def all(self, db: AsyncSession, user_id: uuid.UUID) -> list[Goal]:
        """Return every goal of the user."""
        return list((await db.execute(select(Goal).where(Goal.user_id == user_id))).scalars())

    async def history(
        self,
        db: AsyncSession,
        user_id: uuid.UUID,
        *,
        period_type: str | None = None,
        period_start: date | None = None,
    ) -> list[LegacyGoal]:
        """Return the legacy goals, oldest period first (FR-022, FR-023). Read only.

        The legacy goals are every month and week goal and the year goals that are retired or
        were marked complete before annual planning. Each row carries the count of linked tasks.
        """
        query = select(Goal).where(
            Goal.user_id == user_id,
            (Goal.period_type != "year") | Goal.status.in_(("retired", "done")),
        )
        if period_type is not None:
            query = query.where(Goal.period_type == period_type)
        if period_start is not None:
            query = query.where(Goal.period_start == period_start)
        goals = list(
            (
                await db.execute(query.order_by(Goal.period_start, Goal.period_type, Goal.title))
            ).scalars()
        )
        counts: dict[uuid.UUID, int] = {}
        if goals:
            rows = await db.execute(
                select(Task.goal_id, func.count())
                .where(
                    Task.user_id == user_id,
                    Task.goal_id.in_([g.id for g in goals]),
                    Task.sync_state != "deleted_remotely",
                )
                .group_by(Task.goal_id)
            )
            counts = {goal_id: count for goal_id, count in rows.tuples() if goal_id is not None}
        return [LegacyGoal(g, counts.get(g.id, 0)) for g in goals]
