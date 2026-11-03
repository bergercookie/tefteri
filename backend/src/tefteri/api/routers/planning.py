"""Goals, plans and the weekly, monthly and annual views."""

import uuid
from datetime import date
from typing import Annotated, Literal

from fastapi import APIRouter, Query, Request
from pydantic import BaseModel, Field
from sqlalchemy import select

from tefteri.api.deps import CurrentUser, Db
from tefteri.api.schemas import EntryOut, TaskOut, aware
from tefteri.db.models.calendar_entry import CalendarEntry
from tefteri.db.models.goal import Goal, Plan
from tefteri.db.models.task import Task
from tefteri.domain.enums import Context
from tefteri.domain.periods import PeriodType, period_end, period_start
from tefteri.domain.timeutil import day_bounds, overlaps
from tefteri.services.context import ContextFilter, load_maps
from tefteri.services.goals import ChildGoal, ChildTask, GoalService

router = APIRouter(tags=["planning"])


def _goals(request: Request) -> GoalService:
    service: GoalService = request.app.state.goal_service
    return service


class GoalOut(BaseModel):
    """A goal with its computed progress."""

    id: uuid.UUID
    parent_id: uuid.UUID | None
    period_type: str
    period_start: date
    title: str
    description: str
    context: str
    status: str
    progress: float

    @classmethod
    def of(cls, g: Goal, progress: dict[uuid.UUID, float]) -> "GoalOut":
        """Build from the ORM row and the computed progress map."""
        return cls(
            id=g.id,
            parent_id=g.parent_id,
            period_type=g.period_type,
            period_start=g.period_start,
            title=g.title,
            description=g.description,
            context=g.context,
            status=g.status,
            progress=round(progress.get(g.id, 0.0), 4),
        )


class GoalIn(BaseModel):
    """Data to create a goal."""

    parent_id: uuid.UUID | None = None
    period_type: PeriodType
    period_start: date
    title: str = Field(min_length=1, max_length=500)
    description: str = ""
    context: Context = Context.LIFE


class GoalPatch(BaseModel):
    """Partial goal update."""

    title: str | None = Field(default=None, min_length=1, max_length=500)
    description: str | None = None
    status: Literal["active", "done", "dropped"] | None = None
    context: Context | None = None


class ChildGoalIn(BaseModel):
    """A smaller goal in a breakdown."""

    title: str = Field(min_length=1, max_length=500)
    period_type: PeriodType
    period_start: date


class ChildTaskIn(BaseModel):
    """A task in a breakdown."""

    connection_id: uuid.UUID
    container_id: uuid.UUID | None = None
    title: str = Field(min_length=1, max_length=500)


class BreakdownIn(BaseModel):
    """Smaller goals and tasks to create under a goal."""

    goals: list[ChildGoalIn] = Field(default_factory=list)
    tasks: list[ChildTaskIn] = Field(default_factory=list)


class BreakdownOut(BaseModel):
    """What a breakdown created."""

    goals: list[GoalOut]
    tasks: list[TaskOut]


class PlanIn(BaseModel):
    """Data to create a plan."""

    period_type: PeriodType
    period_start: date
    title: str = Field(min_length=1, max_length=500)
    summary: str = ""


class PlanOut(BaseModel):
    """A plan and the goals of its period."""

    id: uuid.UUID
    period_type: str
    period_start: date
    title: str
    summary: str
    goals: list[GoalOut]


class PeriodView(BaseModel):
    """Aggregated data for a weekly, monthly or annual view."""

    period_type: str
    start: date
    end: date
    goals: list[GoalOut]
    tasks: list[TaskOut]
    entries: list[EntryOut]


def _matches(wanted: ContextFilter, goal: Goal) -> bool:
    return wanted is ContextFilter.ALL or goal.context == wanted.value


@router.get("/goals")
async def list_goals(
    request: Request,
    db: Db,
    user: CurrentUser,
    period_type: PeriodType | None = None,
    period_start_: Annotated[date | None, Query(alias="period_start")] = None,
    parent_id: uuid.UUID | None = None,
    context: ContextFilter = ContextFilter.ALL,
) -> list[GoalOut]:
    """List goals, optionally for one period or under one parent."""
    service = _goals(request)
    progress = await service.progress(db, user.id)
    return [
        GoalOut.of(g, progress)
        for g in await service.all(db, user.id)
        if (period_type is None or g.period_type == period_type.value)
        and (period_start_ is None or g.period_start == period_start_)
        and (parent_id is None or g.parent_id == parent_id)
        and _matches(context, g)
    ]


@router.post("/goals", status_code=201)
async def create_goal(body: GoalIn, request: Request, db: Db, user: CurrentUser) -> GoalOut:
    """Create a goal; its period must lie inside its parent's period."""
    service = _goals(request)
    goal = await service.create(db, user.id, **body.model_dump())
    return GoalOut.of(goal, await service.progress(db, user.id))


@router.patch("/goals/{goal_id}")
async def update_goal(
    goal_id: uuid.UUID, body: GoalPatch, request: Request, db: Db, user: CurrentUser
) -> GoalOut:
    """Change a goal."""
    service = _goals(request)
    goal = await service.update(
        db, await service.get(db, user.id, goal_id), **body.model_dump(exclude_unset=True)
    )
    return GoalOut.of(goal, await service.progress(db, user.id))


@router.delete("/goals/{goal_id}", status_code=204)
async def delete_goal(
    goal_id: uuid.UUID,
    request: Request,
    db: Db,
    user: CurrentUser,
    linked_tasks: Literal["keep", "delete"],
) -> None:
    """Delete a goal and its smaller goals. ``linked_tasks`` says what happens to their tasks."""
    service = _goals(request)
    await service.delete(db, user.id, await service.get(db, user.id, goal_id), linked_tasks)


@router.post("/goals/{goal_id}/breakdown", status_code=201)
async def breakdown_goal(
    goal_id: uuid.UUID, body: BreakdownIn, request: Request, db: Db, user: CurrentUser
) -> BreakdownOut:
    """Create smaller goals and tasks under a goal."""
    service = _goals(request)
    goal = await service.get(db, user.id, goal_id)
    goals, tasks = await service.breakdown(
        db,
        user.id,
        goal,
        [ChildGoal(g.title, g.period_type, g.period_start) for g in body.goals],
        [ChildTask(t.connection_id, t.title, t.container_id) for t in body.tasks],
    )
    progress = await service.progress(db, user.id)
    maps = await load_maps(db, user.id)
    return BreakdownOut(
        goals=[GoalOut.of(g, progress) for g in goals], tasks=[TaskOut.of(t, maps) for t in tasks]
    )


async def _plan_out(request: Request, db: Db, user_id: uuid.UUID, plan: Plan) -> PlanOut:
    service = _goals(request)
    progress = await service.progress(db, user_id)
    goals = [
        GoalOut.of(g, progress)
        for g in await service.all(db, user_id)
        if g.period_type == plan.period_type and g.period_start == plan.period_start
    ]
    return PlanOut(
        id=plan.id,
        period_type=plan.period_type,
        period_start=plan.period_start,
        title=plan.title,
        summary=plan.summary,
        goals=goals,
    )


@router.get("/plans")
async def list_plans(request: Request, db: Db, user: CurrentUser) -> list[PlanOut]:
    """List plans, newest period first (plans are kept after their period ends)."""
    return [
        await _plan_out(request, db, user.id, p) for p in await _goals(request).plans(db, user.id)
    ]


@router.post("/plans", status_code=201)
async def create_plan(body: PlanIn, request: Request, db: Db, user: CurrentUser) -> PlanOut:
    """Create a plan for a period."""
    plan = await _goals(request).create_plan(db, user.id, **body.model_dump())
    return await _plan_out(request, db, user.id, plan)


@router.get("/plans/{plan_id}")
async def get_plan(plan_id: uuid.UUID, request: Request, db: Db, user: CurrentUser) -> PlanOut:
    """Return one plan with its goals."""
    return await _plan_out(request, db, user.id, await _goals(request).plan(db, user.id, plan_id))


async def _period_view(
    request: Request,
    db: Db,
    user_id: uuid.UUID,
    tz: str,
    kind: PeriodType,
    start: date,
    context: ContextFilter,
) -> PeriodView:
    end = period_end(kind, start)
    low = day_bounds(start, tz)[0]
    high = day_bounds(end, tz)[0]
    service = _goals(request)
    progress = await service.progress(db, user_id)
    maps = await load_maps(db, user_id)
    goals = [
        GoalOut.of(g, progress)
        for g in await service.all(db, user_id)
        if g.period_type == kind.value and g.period_start == start and _matches(context, g)
    ]
    tasks = []
    for t in (await db.execute(select(Task).where(Task.user_id == user_id))).scalars():
        when = t.due_at
        if t.sync_state == "deleted_remotely" or when is None or not low <= aware(when) < high:
            continue
        if maps.matches(context, t.context, t.container_id, t.connection_id):
            tasks.append(TaskOut.of(t, maps))
    entries: list[EntryOut] = []
    if kind is not PeriodType.YEAR:
        for e in (
            await db.execute(select(CalendarEntry).where(CalendarEntry.user_id == user_id))
        ).scalars():
            if (
                e.sync_state != "deleted_remotely"
                and overlaps(aware(e.start), aware(e.end), low, high)
                and maps.matches(context, e.context, e.container_id, e.connection_id)
            ):
                entries.append(EntryOut.of(e, maps))
    return PeriodView(
        period_type=kind.value,
        start=start,
        end=end,
        goals=goals,
        tasks=tasks,
        entries=sorted(entries, key=lambda e: e.start),
    )


@router.get("/views/week/{day}")
async def week_view(
    day: date,
    request: Request,
    db: Db,
    user: CurrentUser,
    context: ContextFilter = ContextFilter.ALL,
) -> PeriodView:
    """Return the goals, tasks and entries of the Monday-to-Sunday week that contains ``day``."""
    return await _period_view(
        request,
        db,
        user.id,
        user.timezone,
        PeriodType.WEEK,
        period_start(PeriodType.WEEK, day),
        context,
    )


@router.get("/views/month/{day}")
async def month_view(
    day: date,
    request: Request,
    db: Db,
    user: CurrentUser,
    context: ContextFilter = ContextFilter.ALL,
) -> PeriodView:
    """Return the goals, tasks and entries of the month that contains ``day``."""
    return await _period_view(
        request,
        db,
        user.id,
        user.timezone,
        PeriodType.MONTH,
        period_start(PeriodType.MONTH, day),
        context,
    )


@router.get("/views/year/{year}")
async def year_view(
    year: int,
    request: Request,
    db: Db,
    user: CurrentUser,
    context: ContextFilter = ContextFilter.ALL,
) -> PeriodView:
    """Return the goals and tasks of a year (no entries)."""
    return await _period_view(
        request, db, user.id, user.timezone, PeriodType.YEAR, date(year, 1, 1), context
    )
