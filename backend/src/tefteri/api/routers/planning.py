"""Plans, the legacy goal history and the weekly, monthly and annual views."""

import uuid
from datetime import date
from typing import Annotated

from fastapi import APIRouter, Query, Request
from pydantic import BaseModel, Field
from sqlalchemy import select

from tefteri.api.deps import CurrentUser, Db
from tefteri.api.lookups import container_colors, read_only_containers
from tefteri.api.schemas import EntryOut, TaskOut, aware
from tefteri.db.models.calendar_entry import CalendarEntry
from tefteri.db.models.connection import SourceContainer
from tefteri.db.models.goal import Plan
from tefteri.db.models.task import Task
from tefteri.domain.periods import PeriodType, period_end, period_start
from tefteri.domain.timeutil import day_bounds, overlaps
from tefteri.services.goals import GoalService

router = APIRouter(tags=["planning"])


def _goals(request: Request) -> GoalService:
    service: GoalService = request.app.state.goal_service
    return service


class GoalTitle(BaseModel):
    """The title of a goal that a task of a view points to (FR-025)."""

    title: str
    annual: bool
    """True for a goal of an annual plan; false for a legacy month or week goal."""


class LegacyGoalOut(BaseModel):
    """A legacy goal of the read-only history (FR-022, FR-023)."""

    id: uuid.UUID
    parent_id: uuid.UUID | None
    period_type: str
    period_start: date
    title: str
    description: str
    criteria: str
    status: str
    linked_tasks: int


class PlanIn(BaseModel):
    """Data to create a plan."""

    period_type: PeriodType
    period_start: date
    title: str = Field(min_length=1, max_length=500)
    summary: str = ""


class PlanOut(BaseModel):
    """A plan of one period. Goals are no longer part of it (spec 006)."""

    id: uuid.UUID
    period_type: str
    period_start: date
    title: str
    summary: str


class PeriodView(BaseModel):
    """Aggregated data for a weekly, monthly or annual view."""

    period_type: str
    start: date
    end: date
    tasks: list[TaskOut]
    entries: list[EntryOut]
    goal_titles: dict[uuid.UUID, GoalTitle]
    """The goals that tasks of the view point to, by id (FR-025)."""


@router.get("/goals/history")
async def legacy_goals(
    request: Request,
    db: Db,
    user: CurrentUser,
    period_type: PeriodType | None = None,
    period_start_: Annotated[date | None, Query(alias="period_start")] = None,
) -> list[LegacyGoalOut]:
    """List the legacy goals, read only (FR-022, FR-023).

    These are all month and week goals and the year goals that are retired or were marked
    complete before annual planning, with their parent and the number of linked tasks. No route
    writes them.
    """
    rows = await _goals(request).history(
        db,
        user.id,
        period_type=period_type.value if period_type else None,
        period_start=period_start_,
    )
    return [
        LegacyGoalOut(
            id=r.goal.id,
            parent_id=r.goal.parent_id,
            period_type=r.goal.period_type,
            period_start=r.goal.period_start,
            title=r.goal.title,
            description=r.goal.description,
            criteria=r.goal.criteria,
            status=r.goal.status,
            linked_tasks=r.linked_tasks,
        )
        for r in rows
    ]


def _plan_out(plan: Plan) -> PlanOut:
    return PlanOut(
        id=plan.id,
        period_type=plan.period_type,
        period_start=plan.period_start,
        title=plan.title,
        summary=plan.summary,
    )


@router.get("/plans")
async def list_plans(request: Request, db: Db, user: CurrentUser) -> list[PlanOut]:
    """List plans, newest period first (plans are kept after their period ends)."""
    return [_plan_out(p) for p in await _goals(request).plans(db, user.id)]


@router.post("/plans", status_code=201)
async def create_plan(body: PlanIn, request: Request, db: Db, user: CurrentUser) -> PlanOut:
    """Create a plan for a period."""
    plan = await _goals(request).create_plan(db, user.id, **body.model_dump())
    return _plan_out(plan)


@router.get("/plans/{plan_id}")
async def get_plan(plan_id: uuid.UUID, request: Request, db: Db, user: CurrentUser) -> PlanOut:
    """Return one plan."""
    return _plan_out(await _goals(request).plan(db, user.id, plan_id))


async def _period_view(
    request: Request,
    db: Db,
    user_id: uuid.UUID,
    tz: str,
    kind: PeriodType,
    start: date,
) -> PeriodView:
    end = period_end(kind, start)
    low = day_bounds(start, tz)[0]
    high = day_bounds(end, tz)[0]
    projects = {
        c.id: c.name
        for c in (
            await db.execute(select(SourceContainer).where(SourceContainer.user_id == user_id))
        ).scalars()
    }
    colors = await container_colors(db, user_id)
    locked = await read_only_containers(db, user_id)
    tasks: list[TaskOut] = []
    goal_ids: list[uuid.UUID] = []
    for t in (await db.execute(select(Task).where(Task.user_id == user_id))).scalars():
        when = t.due_at
        if t.sync_state == "deleted_remotely" or when is None or not low <= aware(when) < high:
            continue
        project = projects.get(t.container_id) if t.container_id else None
        if t.goal_id is not None:
            goal_ids.append(t.goal_id)
        tasks.append(
            TaskOut.of(
                t,
                project=project,
                project_color=colors.get(t.container_id) if t.container_id else None,
            )
        )
    entries: list[EntryOut] = []
    if kind is not PeriodType.YEAR:
        for e in (
            await db.execute(select(CalendarEntry).where(CalendarEntry.user_id == user_id))
        ).scalars():
            if e.sync_state != "deleted_remotely" and overlaps(
                aware(e.start), aware(e.end), low, high
            ):
                entries.append(EntryOut.of(e, colors, locked))
    titles = await request.app.state.annual_service.goal_titles_for(db, user_id, goal_ids)
    return PeriodView(
        period_type=kind.value,
        start=start,
        end=end,
        tasks=tasks,
        entries=sorted(entries, key=lambda e: e.start),
        goal_titles={
            goal_id: GoalTitle(title=title, annual=annual)
            for goal_id, (title, annual) in titles.items()
        },
    )


@router.get("/views/week/{day}")
async def week_view(
    day: date,
    request: Request,
    db: Db,
    user: CurrentUser,
) -> PeriodView:
    """Return the tasks and entries of the Monday-to-Sunday week that contains ``day``."""
    return await _period_view(
        request,
        db,
        user.id,
        user.timezone,
        PeriodType.WEEK,
        period_start(PeriodType.WEEK, day),
    )


@router.get("/views/month/{day}")
async def month_view(
    day: date,
    request: Request,
    db: Db,
    user: CurrentUser,
) -> PeriodView:
    """Return the tasks and entries of the month that contains ``day``."""
    return await _period_view(
        request,
        db,
        user.id,
        user.timezone,
        PeriodType.MONTH,
        period_start(PeriodType.MONTH, day),
    )


@router.get("/views/year/{year}")
async def year_view(
    year: int,
    request: Request,
    db: Db,
    user: CurrentUser,
) -> PeriodView:
    """Return the tasks of a year (no entries). The annual plan is ``GET /annual/{year}``."""
    return await _period_view(
        request, db, user.id, user.timezone, PeriodType.YEAR, date(year, 1, 1)
    )
