"""Goals and plans after spec 006: computed progress, plans and the read-only legacy history.

Goals exist only for a planning year now (``services.annual_plan``). Month and week goals, and
year goals that are retired or were marked complete, stay as read-only history (FR-022, FR-023):
this module reads them and never writes them.
"""

import uuid
from dataclasses import dataclass
from datetime import date

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from tefteri.db.models.goal import Goal, Plan
from tefteri.db.models.task import Task
from tefteri.domain.periods import PeriodType, is_aligned
from tefteri.services.errors import Invalid, NotFound


@dataclass(frozen=True)
class LegacyGoal:
    """One row of ``GET /goals/history``: an old goal and the number of tasks linked to it."""

    goal: Goal
    linked_tasks: int


def compute_progress(goals: list[Goal], tasks: list[Task]) -> dict[uuid.UUID, float]:
    """Return progress (0..1) for every goal, computed from smaller goals and linked tasks.

    Each linked task counts 1 if done, else 0. Each smaller goal counts its own progress.
    Dropped goals and tasks deleted in the app do not count. A goal with nothing under it is
    1.0 when its status is ``done``, else 0.0.
    """
    children: dict[uuid.UUID, list[Goal]] = {}
    for g in goals:
        if g.parent_id is not None and g.status != "dropped":
            children.setdefault(g.parent_id, []).append(g)
    linked: dict[uuid.UUID, list[Task]] = {}
    for t in tasks:
        if t.goal_id is not None and t.sync_state != "deleted_remotely":
            linked.setdefault(t.goal_id, []).append(t)
    by_id = {g.id: g for g in goals}
    cache: dict[uuid.UUID, float] = {}

    def of(goal_id: uuid.UUID) -> float:
        if goal_id in cache:
            return cache[goal_id]
        parts = [of(c.id) for c in children.get(goal_id, [])]
        parts += [1.0 if t.status == "done" else 0.0 for t in linked.get(goal_id, [])]
        value = (
            sum(parts) / len(parts) if parts else (1.0 if by_id[goal_id].status == "done" else 0.0)
        )
        cache[goal_id] = value
        return value

    return {g.id: of(g.id) for g in goals}


class GoalService:
    """Read goals and their progress, the legacy history, and manage plans."""

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

    async def progress(self, db: AsyncSession, user_id: uuid.UUID) -> dict[uuid.UUID, float]:
        """Return the computed progress of all the user's goals."""
        tasks = list((await db.execute(select(Task).where(Task.user_id == user_id))).scalars())
        return compute_progress(await self.all(db, user_id), tasks)

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
            counts = {goal_id: count for goal_id, count in rows.tuples()}
        return [LegacyGoal(g, counts.get(g.id, 0)) for g in goals]

    async def create_plan(
        self,
        db: AsyncSession,
        user_id: uuid.UUID,
        *,
        period_type: PeriodType,
        period_start: date,
        title: str,
        summary: str = "",
    ) -> Plan:
        """Create a plan for one period."""
        if not is_aligned(period_type, period_start):
            raise Invalid(f"a {period_type.value} period must start on its first day")
        plan = Plan(
            user_id=user_id,
            period_type=period_type.value,
            period_start=period_start,
            title=title,
            summary=summary,
        )
        db.add(plan)
        await db.flush()
        return plan

    async def plans(self, db: AsyncSession, user_id: uuid.UUID) -> list[Plan]:
        """Return all of the user's plans, newest period first."""
        rows = await db.execute(
            select(Plan).where(Plan.user_id == user_id).order_by(Plan.period_start.desc())
        )
        return list(rows.scalars())

    async def plan(self, db: AsyncSession, user_id: uuid.UUID, plan_id: uuid.UUID) -> Plan:
        """Return one plan or raise ``NotFound``."""
        plan = (
            await db.execute(select(Plan).where(Plan.id == plan_id, Plan.user_id == user_id))
        ).scalar_one_or_none()
        if plan is None:
            raise NotFound
        return plan
