"""Statistics of completed tasks by work category (spec 005)."""

import uuid
from datetime import date, datetime
from zoneinfo import ZoneInfo

from fastapi import APIRouter, Request
from pydantic import BaseModel
from sqlalchemy import select

from tefteri.api.deps import CurrentUser, Db
from tefteri.api.schemas import UtcDatetime
from tefteri.api.task_links import task_base_url, task_url
from tefteri.db.models.connection import Connection
from tefteri.domain.enums import CategoryReason, WorkCategory
from tefteri.domain.week_progress import WeekProgress
from tefteri.domain.work_categories import CategoryCounts
from tefteri.services.errors import Invalid
from tefteri.services.statistics import (
    DEFAULT_LIMIT,
    StatisticsService,
    StatTask,
    parse_category,
    parse_period,
)

router = APIRouter(prefix="/statistics", tags=["statistics"])


def _service(request: Request) -> StatisticsService:
    service: StatisticsService = request.app.state.statistics_service
    return service


class CountsOut(BaseModel):
    """Completed tasks per work category. The hidden count is not part of them."""

    goal_aligned: int
    maintenance: int
    off_plan: int

    @classmethod
    def of(cls, counts: CategoryCounts) -> "CountsOut":
        """Build from domain counts."""
        return cls(
            goal_aligned=counts.goal_aligned,
            maintenance=counts.maintenance,
            off_plan=counts.off_plan,
        )


class PartOut(BaseModel):
    """One day or one month of a period."""

    start: date
    end: date
    counts: CountsOut
    hidden: int


class EmptyOut(BaseModel):
    """Why a period has no number, and the action that helps."""

    reason: str
    """``no_tasks`` or ``no_labels``."""
    action: str
    """``plan_week`` or ``label_projects``."""


class SyncOut(BaseModel):
    """When the task apps were last synced."""

    last_synced_at: UtcDatetime | None
    outcome: str | None
    """``ok``, ``auth_expired``, ``unreachable``, ``error`` or ``None`` (never synced)."""


class ProgressOut(BaseModel):
    """How far the committed plan of a week has come."""

    committed: int
    done: int
    done_before: int
    done_undated: int
    done_after: int
    done_by_day: list[int]
    days_elapsed: int
    days_left: int
    cadence: float | None
    needed_per_day: float | None
    on_track: bool
    remaining_by_day: list[int | None]
    ideal_by_day: list[float]
    scope: int

    @classmethod
    def of(cls, p: WeekProgress) -> "ProgressOut":
        """Build from the domain progress."""
        return cls(
            committed=p.committed,
            done=p.done,
            done_before=p.done_before,
            done_undated=p.done_undated,
            done_after=p.done_after,
            done_by_day=list(p.done_by_day),
            days_elapsed=p.days_elapsed,
            days_left=p.days_left,
            cadence=p.cadence,
            needed_per_day=p.needed_per_day,
            on_track=p.on_track,
            remaining_by_day=list(p.remaining_by_day),
            ideal_by_day=[round(v, 2) for v in p.ideal_by_day],
            scope=p.scope,
        )


class StatisticsOut(BaseModel):
    """The counts of one period."""

    period: str
    start: date
    end: date
    """The first day after the period."""
    available: bool
    unavailable_reason: str | None
    counts: CountsOut
    total: int
    percentages: CountsOut
    hidden: int
    unsorted: int
    part_kind: str
    """``day`` (week, month) or ``month`` (year)."""
    parts: list[PartOut]
    empty: EmptyOut | None
    sync: SyncOut
    progress: ProgressOut | None


class ProjectOut(BaseModel):
    """The project a task was in when it was completed."""

    id: uuid.UUID | None
    name: str | None
    color: str | None
    orphaned: bool


class StatTaskOut(BaseModel):
    """A completed task with its stored category."""

    id: uuid.UUID
    title: str
    completed_at: UtcDatetime
    completed_day: date
    category: WorkCategory
    reason: CategoryReason
    unsorted: bool
    project: ProjectOut
    url: str | None


class StatTasksOut(BaseModel):
    """One page of completed tasks."""

    period: str
    start: date
    end: date
    category: WorkCategory | None
    order: str
    total: int
    items: list[StatTaskOut]
    next_cursor: str | None


def _today(request: Request, tz: str) -> date:
    now: datetime = request.app.state.clock()
    return now.astimezone(ZoneInfo(tz)).date()


@router.get("")
async def statistics(
    request: Request,
    db: Db,
    user: CurrentUser,
    period: str = "week",
    day: date | None = None,
) -> StatisticsOut:
    """Return the counts of the week, month or year that holds ``day`` (default: today).

    Every number is read from the stored categories. A week and a month are the sum of their
    days, a year is the sum of its months, so the parts always add up to the counts. The hidden
    count (tasks in ignored projects) is not part of ``total`` or of the percentages.
    """
    kind = parse_period(period)
    today = _today(request, user.timezone)
    s = await _service(request).summary(db, user.id, user.timezone, kind, day or today, today)
    return StatisticsOut(
        period=s.period.value,
        start=s.start,
        end=s.end,
        available=s.available,
        unavailable_reason=s.unavailable_reason,
        counts=CountsOut.of(s.counts),
        total=s.counts.total,
        percentages=CountsOut(
            goal_aligned=s.percentages.goal_aligned,
            maintenance=s.percentages.maintenance,
            off_plan=s.percentages.off_plan,
        ),
        hidden=s.counts.hidden,
        unsorted=s.unsorted,
        part_kind=s.part_kind,
        parts=[
            PartOut(start=p.start, end=p.end, counts=CountsOut.of(p.counts), hidden=p.counts.hidden)
            for p in s.parts
        ],
        empty=EmptyOut(reason=s.empty.reason, action=s.empty.action) if s.empty else None,
        sync=SyncOut(last_synced_at=s.sync.last_synced_at, outcome=s.sync.outcome),
        progress=ProgressOut.of(s.progress) if s.progress else None,
    )


def _item(t: StatTask, bases: dict[uuid.UUID, str | None]) -> StatTaskOut:
    return StatTaskOut(
        id=t.id,
        title=t.title,
        completed_at=t.completed_at,
        completed_day=t.completed_day,
        category=t.category,
        reason=t.reason,
        unsorted=t.unsorted,
        project=ProjectOut(
            id=t.project_id, name=t.project_name, color=t.project_color, orphaned=t.orphaned
        ),
        url=task_url(bases.get(t.connection_id), t.remote_id),
    )


@router.get("/tasks")
async def statistics_tasks(
    request: Request,
    db: Db,
    user: CurrentUser,
    period: str = "week",
    day: date | None = None,
    category: str | None = None,
    order: str = "newest",
    limit: int = DEFAULT_LIMIT,
    cursor: str | None = None,
) -> StatTasksOut:
    """Return the completed tasks behind a count, one page at a time.

    ``total`` is the number of tasks for the filter, not of the page, and it has no cap. Follow
    ``next_cursor`` until it is ``null`` to reach every task. ``category`` omitted lists the three
    work categories; ``hidden`` lists the tasks of ignored projects.
    """
    kind = parse_period(period)
    cat = parse_category(category)
    if order not in ("newest", "project"):
        raise Invalid("order must be newest or project")
    today = _today(request, user.timezone)
    start, end, page = await _service(request).tasks(
        db,
        user.id,
        period=kind,
        day=day or today,
        category=cat,
        order=order,
        limit=limit,
        cursor=cursor,
    )
    ids = {t.connection_id for t in page.items}
    bases: dict[uuid.UUID, str | None] = {}
    if ids:
        for connection in (
            await db.execute(select(Connection).where(Connection.id.in_(ids)))
        ).scalars():
            bases[connection.id] = task_base_url(connection)
    return StatTasksOut(
        period=kind.value,
        start=start,
        end=end,
        category=cat,
        order=order,
        total=page.total,
        items=[_item(t, bases) for t in page.items],
        next_cursor=page.next_cursor,
    )
