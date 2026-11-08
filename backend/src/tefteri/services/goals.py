"""Goals and plans: hierarchy rules, breakdown, computed progress, deletion."""

import uuid
from dataclasses import dataclass
from datetime import date
from typing import Literal

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from tefteri.db.models.goal import Goal, Plan
from tefteri.db.models.task import Task
from tefteri.domain.periods import PeriodType, child_fits, is_aligned
from tefteri.services.errors import Invalid, NotFound
from tefteri.services.tasks import TaskService


@dataclass(frozen=True)
class ChildGoal:
    """A smaller goal to create under a goal."""

    title: str
    period_type: PeriodType
    period_start: date


@dataclass(frozen=True)
class ChildTask:
    """A task to create for a goal."""

    connection_id: uuid.UUID
    title: str
    container_id: uuid.UUID | None = None


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
    """Create, change, break down and delete goals; manage plans."""

    def __init__(self, tasks: TaskService) -> None:
        """Use ``tasks`` to create and delete the tasks of goals."""
        self._tasks = tasks

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

    async def create(
        self,
        db: AsyncSession,
        user_id: uuid.UUID,
        *,
        period_type: PeriodType,
        period_start: date,
        title: str,
        description: str = "",
        criteria: str = "",
        parent_id: uuid.UUID | None = None,
    ) -> Goal:
        """Create a goal after checking the period and its place under the parent."""
        if not is_aligned(period_type, period_start):
            raise Invalid(f"a {period_type.value} period must start on its first day")
        if parent_id is not None:
            parent = await self.get(db, user_id, parent_id)
            if not child_fits(
                PeriodType(parent.period_type), parent.period_start, period_type, period_start
            ):
                raise Invalid("the period of a smaller goal must lie inside its parent's period")
        goal = Goal(
            user_id=user_id,
            parent_id=parent_id,
            period_type=period_type.value,
            period_start=period_start,
            title=title,
            description=description,
            criteria=criteria,
        )
        db.add(goal)
        await db.flush()
        return goal

    async def update(
        self,
        db: AsyncSession,
        goal: Goal,
        *,
        title: str | None = None,
        description: str | None = None,
        criteria: str | None = None,
        status: Literal["active", "done", "dropped"] | None = None,
    ) -> Goal:
        """Change a goal's text, status or criteria."""
        if title is not None:
            goal.title = title
        if description is not None:
            goal.description = description
        if criteria is not None:
            goal.criteria = criteria
        if status is not None:
            goal.status = status
        await db.flush()
        return goal

    async def create_many(
        self,
        db: AsyncSession,
        user_id: uuid.UUID,
        *,
        period_type: PeriodType,
        period_start: date,
        titles: list[str],
        parent_id: uuid.UUID | None = None,
    ) -> list[Goal]:
        """Create one goal per title, all in the same period. All or none are created."""
        return [
            await self.create(
                db,
                user_id,
                period_type=period_type,
                period_start=period_start,
                title=title,
                parent_id=parent_id,
            )
            for title in titles
        ]

    async def breakdown(
        self,
        db: AsyncSession,
        user_id: uuid.UUID,
        goal: Goal,
        goals: list[ChildGoal],
        tasks: list[ChildTask],
    ) -> tuple[list[Goal], list[Task]]:
        """Create smaller goals and tasks under ``goal``."""
        created_goals = [
            await self.create(
                db,
                user_id,
                period_type=g.period_type,
                period_start=g.period_start,
                title=g.title,
                parent_id=goal.id,
            )
            for g in goals
        ]
        created_tasks = [
            await self._tasks.create(
                db,
                user_id,
                connection_id=t.connection_id,
                container_id=t.container_id,
                title=t.title,
                goal_id=goal.id,
            )
            for t in tasks
        ]
        return created_goals, created_tasks

    async def delete(
        self,
        db: AsyncSession,
        user_id: uuid.UUID,
        goal: Goal,
        linked_tasks: Literal["keep", "delete"],
    ) -> None:
        """Delete a goal and its smaller goals. Linked tasks are kept (unlinked) or deleted."""
        everything = await self.all(db, user_id)
        ids = {goal.id}
        grew = True
        while grew:
            grew = False
            for g in everything:
                if g.parent_id in ids and g.id not in ids:
                    ids.add(g.id)
                    grew = True
        tasks = [
            t
            for t in (await db.execute(select(Task).where(Task.user_id == user_id))).scalars()
            if t.goal_id in ids
        ]
        for task in tasks:
            if linked_tasks == "delete":
                await self._tasks.delete(db, user_id, task)
            else:
                task.goal_id = None
        await db.flush()
        # The database cascades the delete to the smaller goals (ON DELETE CASCADE).
        await db.delete(goal)
        await db.flush()
        db.expire_all()

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
