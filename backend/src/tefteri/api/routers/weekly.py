"""Weekly planning sessions: choose projects, give tasks a day, look back a week later."""

import uuid
from datetime import date, datetime, timedelta
from zoneinfo import ZoneInfo

from fastapi import APIRouter, Request
from pydantic import BaseModel, Field

from tefteri.api.deps import CurrentUser, Db
from tefteri.api.schemas import UtcDatetime
from tefteri.db.models.weekly import WeeklyPlan
from tefteri.services.errors import NotFound
from tefteri.services.weekly import (
    MAX_PROJECTS,
    Answer,
    LookBack,
    ProjectView,
    TaskView,
    WeeklyService,
    normalize_week,
)

router = APIRouter(prefix="/weekly", tags=["weekly planning"])


def _service(request: Request) -> WeeklyService:
    service: WeeklyService = request.app.state.weekly_service
    return service


def _now(request: Request) -> datetime:
    now: datetime = request.app.state.clock()
    return now


class WeeklyTaskOut(BaseModel):
    """A task of a chosen project and its day."""

    id: uuid.UUID
    title: str
    due_day: date | None
    planned_day: date | None
    """The day in the planned week, or ``None`` when the task has no day in that week."""
    done: bool = False
    completed_day: date | None = None
    """The day the task was completed, or ``None`` when open or when the app does not say."""
    parked: bool = False
    """The user set the task aside for this plan."""
    url: str | None = None

    @classmethod
    def of(cls, v: TaskView, base: str | None) -> "WeeklyTaskOut":
        """Build from a task view; ``base`` is the address of the task app, if it has pages."""
        return cls(
            id=v.task.id,
            title=v.task.title,
            due_day=v.due_day,
            planned_day=v.planned_day,
            done=v.task.status == "done",
            completed_day=v.completed_day,
            parked=v.parked,
            url=f"{base}/tasks/{v.task.remote_id}" if base else None,
        )


class ProjectOut(BaseModel):
    """A project of the plan."""

    id: uuid.UUID
    container_id: uuid.UUID | None
    name: str
    color: str | None = None
    """The color of the project in the task app, as ``#rrggbb``."""
    created_here: bool
    url: str | None
    open_tasks: int
    done_tasks: int
    scheduled_tasks: int
    parked_tasks: int
    tasks: list[WeeklyTaskOut]
    """The open tasks, parked ones too (they have ``parked`` set)."""
    committed_tasks: list[WeeklyTaskOut]
    """The tasks planned at the commit, with their state now. Empty before the commit."""


class PlanOut(BaseModel):
    """The plan of one week."""

    id: uuid.UUID
    status: str
    committed_at: UtcDatetime | None
    retro_skipped: bool
    max_projects: int = MAX_PROJECTS
    projects: list[ProjectOut]


class LookBackProjectOut(BaseModel):
    """How a project of the earlier week went."""

    id: uuid.UUID
    name: str
    color: str | None = None
    committed: int
    done: int
    completed: bool
    outcome: str | None
    leftover_action: str | None
    leftover: list[WeeklyTaskOut]


class LookBackOut(BaseModel):
    """The earlier week that the user looks back at."""

    plan_id: uuid.UUID
    week_start: date
    reviewed: bool
    reflection: str
    projects: list[LookBackProjectOut]


class WeeklyStateOut(BaseModel):
    """Everything the planning page shows for one week."""

    week_start: date
    week_end: date
    plan: PlanOut | None
    look_back: LookBackOut | None


class CandidateOut(BaseModel):
    """A project the user can pick."""

    container_id: uuid.UUID
    connection_id: uuid.UUID
    connection_name: str
    name: str
    path: str
    open_tasks: int
    carried_tasks: int
    selected: bool


class ProjectIn(BaseModel):
    """The project to add."""

    container_id: uuid.UUID


class SubprojectIn(BaseModel):
    """A new project under an existing one."""

    parent_id: uuid.UUID
    name: str = Field(min_length=1, max_length=255)


class AnswerIn(BaseModel):
    """The decisions about one project of the earlier week."""

    plan_project_id: uuid.UUID
    finished_anyway: bool = False
    leftover: str = "backlog"
    archive: bool = False


class ReviewIn(BaseModel):
    """The look-back."""

    projects: list[AnswerIn] = Field(default_factory=list)
    reflection: str = ""


class HistoryProjectOut(BaseModel):
    """A project of a reviewed week."""

    name: str
    done: bool


class HistoryEntryOut(BaseModel):
    """One reviewed week."""

    plan_id: uuid.UUID
    week_start: date
    committed_projects: int
    done_projects: int
    committed_tasks: int
    done_tasks: int
    reflection: str
    projects: list[HistoryProjectOut]


class HistoryTotalsOut(BaseModel):
    """Sums over all reviewed weeks."""

    weeks: int
    committed_projects: int
    done_projects: int
    committed_tasks: int
    done_tasks: int


class HistoryOut(BaseModel):
    """The reviewed weeks, newest first, and their totals."""

    entries: list[HistoryEntryOut]
    totals: HistoryTotalsOut


def _base_url(view: ProjectView) -> str | None:
    c = view.connection
    if c is not None and c.provider == "vikunja":
        base = str(c.settings.get("base_url", "")).rstrip("/")
        return base or None
    return None


def _project_out(v: ProjectView) -> ProjectOut:
    base = _base_url(v)
    return ProjectOut(
        id=v.row.id,
        container_id=v.row.container_id,
        name=v.container.name if v.container else v.row.name,
        color=v.container.color if v.container else None,
        created_here=v.row.created_here,
        url=f"{base}/projects/{v.container.remote_id}" if base and v.container else None,
        open_tasks=sum(1 for t in v.open_tasks if not t.parked),
        done_tasks=v.done_tasks,
        scheduled_tasks=sum(1 for t in v.open_tasks if t.planned_day is not None and not t.parked),
        parked_tasks=sum(1 for t in v.open_tasks if t.parked),
        tasks=[WeeklyTaskOut.of(t, base) for t in v.open_tasks],
        committed_tasks=[WeeklyTaskOut.of(t, base) for t in v.committed],
    )


def _look_back_out(back: LookBack) -> LookBackOut:
    return LookBackOut(
        plan_id=back.plan.id,
        week_start=back.plan.week_start,
        reviewed=back.plan.reviewed_at is not None,
        reflection=back.plan.reflection,
        projects=[
            LookBackProjectOut(
                id=p.row.id,
                name=p.row.name,
                color=p.color,
                committed=p.committed,
                done=p.done,
                completed=p.completed,
                outcome=p.row.outcome,
                leftover_action=p.row.leftover_action,
                leftover=[WeeklyTaskOut.of(t, None) for t in p.leftover],
            )
            for p in back.projects
        ],
    )


async def _state(
    request: Request, db: Db, user_id: uuid.UUID, tz: str, week: date
) -> WeeklyStateOut:
    service = _service(request)
    plan = await service.find(db, user_id, week)
    plan_out = None
    if plan is not None:
        views = await service.project_views(db, user_id, plan, tz)
        plan_out = PlanOut(
            id=plan.id,
            status=plan.status,
            committed_at=plan.committed_at,
            retro_skipped=plan.retro_skipped,
            projects=[_project_out(v) for v in views],
        )
    back = await service.look_back(db, user_id, week, tz)
    return WeeklyStateOut(
        week_start=week,
        week_end=week + timedelta(days=7),
        plan=plan_out,
        look_back=_look_back_out(back) if back else None,
    )


async def _draft(request: Request, db: Db, user_id: uuid.UUID, week: date) -> WeeklyPlan:
    plan = await _service(request).find(db, user_id, week)
    if plan is None:
        raise NotFound
    return plan


@router.get("/history")
async def history(request: Request, db: Db, user: CurrentUser) -> HistoryOut:
    """List the reviewed weeks: projects committed to versus projects done."""
    entries = []
    for h in await _service(request).history(db, user.id):
        rows = h.projects
        entries.append(
            HistoryEntryOut(
                plan_id=h.plan.id,
                week_start=h.plan.week_start,
                committed_projects=len(rows),
                done_projects=sum(1 for r in rows if r.outcome == "done"),
                committed_tasks=sum(r.reviewed_committed or 0 for r in rows),
                done_tasks=sum(r.reviewed_done or 0 for r in rows),
                reflection=h.plan.reflection,
                projects=[HistoryProjectOut(name=r.name, done=r.outcome == "done") for r in rows],
            )
        )
    totals = HistoryTotalsOut(
        weeks=len(entries),
        committed_projects=sum(e.committed_projects for e in entries),
        done_projects=sum(e.done_projects for e in entries),
        committed_tasks=sum(e.committed_tasks for e in entries),
        done_tasks=sum(e.done_tasks for e in entries),
    )
    return HistoryOut(entries=entries, totals=totals)


@router.post("/reviews/{plan_id}")
async def review(
    plan_id: uuid.UUID, body: ReviewIn, request: Request, db: Db, user: CurrentUser
) -> HistoryOut:
    """Store the look-back at a week and return the history, with that week in it."""
    await _service(request).review(
        db,
        user.id,
        plan_id,
        user.timezone,
        [
            Answer(a.plan_project_id, a.finished_anyway, a.leftover, a.archive)
            for a in body.projects
        ],
        body.reflection,
        _now(request),
    )
    return await history(request, db, user)


@router.get("/{day}")
async def get_week(day: date, request: Request, db: Db, user: CurrentUser) -> WeeklyStateOut:
    """Return the plan of the week that holds ``day`` and the look-back at the week before."""
    return await _state(request, db, user.id, user.timezone, normalize_week(day))


@router.get("/{day}/candidates")
async def candidates(
    day: date,
    request: Request,
    db: Db,
    user: CurrentUser,
) -> list[CandidateOut]:
    """List the projects the user can pick, projects with carried-over tasks first."""
    found = await _service(request).candidates(db, user.id, normalize_week(day))
    return [
        CandidateOut(
            container_id=c.container.id,
            connection_id=c.connection.id,
            connection_name=c.connection.display_name,
            name=c.container.name,
            path=c.path,
            open_tasks=c.open_tasks,
            carried_tasks=c.carried_tasks,
            selected=c.selected,
        )
        for c in found
    ]


@router.post("/{day}/start")
async def start(day: date, request: Request, db: Db, user: CurrentUser) -> WeeklyStateOut:
    """Start the plan of the week (does nothing when it exists)."""
    week = normalize_week(day)
    await _service(request).start(db, user.id, week)
    return await _state(request, db, user.id, user.timezone, week)


@router.post("/{day}/refresh")
async def refresh(day: date, request: Request, db: Db, user: CurrentUser) -> WeeklyStateOut:
    """Read the tasks of the chosen projects again from the task app, then return the state."""
    week = normalize_week(day)
    service = _service(request)
    plans = [p for p in [await service.find(db, user.id, week)] if p is not None]
    back = await service.look_back(db, user.id, week, user.timezone)
    if back is not None and back.plan.reviewed_at is None:
        plans.append(back.plan)
    await service.refresh(db, user.id, week, plans)
    return await _state(request, db, user.id, user.timezone, week)


@router.post("/{day}/projects", status_code=201)
async def add_project(
    day: date, body: ProjectIn, request: Request, db: Db, user: CurrentUser
) -> WeeklyStateOut:
    """Add a project to the week (at most three)."""
    week = normalize_week(day)
    service = _service(request)
    plan = await service.start(db, user.id, week)
    await service.add_project(db, user.id, plan, body.container_id)
    return await _state(request, db, user.id, user.timezone, week)


@router.delete("/{day}/projects/{plan_project_id}")
async def remove_project(
    day: date, plan_project_id: uuid.UUID, request: Request, db: Db, user: CurrentUser
) -> WeeklyStateOut:
    """Take a project out of the week."""
    week = normalize_week(day)
    await _service(request).remove_project(
        db, await _draft(request, db, user.id, week), plan_project_id
    )
    return await _state(request, db, user.id, user.timezone, week)


@router.post("/{day}/subprojects", status_code=201)
async def create_subproject(
    day: date, body: SubprojectIn, request: Request, db: Db, user: CurrentUser
) -> WeeklyStateOut:
    """Create a project under an existing one in the task app and add it to the week."""
    week = normalize_week(day)
    service = _service(request)
    plan = await service.start(db, user.id, week)
    await service.create_subproject(db, user.id, plan, body.parent_id, body.name)
    return await _state(request, db, user.id, user.timezone, week)


class ParkedIn(BaseModel):
    """Set a task aside, or put it back."""

    parked: bool


@router.put("/{day}/tasks/{task_id}/parked")
async def park_task(
    day: date, task_id: uuid.UUID, body: ParkedIn, request: Request, db: Db, user: CurrentUser
) -> WeeklyStateOut:
    """Set a task aside for this plan, or put it back. The task app is not touched."""
    week = normalize_week(day)
    await _service(request).set_parked(
        db, user.id, await _draft(request, db, user.id, week), task_id, body.parked
    )
    return await _state(request, db, user.id, user.timezone, week)


@router.post("/{day}/spread")
async def spread(day: date, request: Request, db: Db, user: CurrentUser) -> WeeklyStateOut:
    """Give every task without a day in the week a day, keeping the days evenly loaded."""
    week = normalize_week(day)
    today = _now(request).astimezone(ZoneInfo(user.timezone)).date()
    await _service(request).spread(
        db, user.id, await _draft(request, db, user.id, week), user.timezone, today
    )
    return await _state(request, db, user.id, user.timezone, week)


@router.post("/{day}/commit")
async def commit(day: date, request: Request, db: Db, user: CurrentUser) -> WeeklyStateOut:
    """Commit the plan: the tasks planned for the week are what the look-back measures."""
    week = normalize_week(day)
    await _service(request).commit(
        db, user.id, await _draft(request, db, user.id, week), user.timezone, _now(request)
    )
    return await _state(request, db, user.id, user.timezone, week)


@router.post("/{day}/reopen")
async def reopen(day: date, request: Request, db: Db, user: CurrentUser) -> WeeklyStateOut:
    """Make a committed plan editable again."""
    week = normalize_week(day)
    await _service(request).reopen(db, await _draft(request, db, user.id, week))
    return await _state(request, db, user.id, user.timezone, week)


@router.post("/{day}/skip-look-back")
async def skip_look_back(day: date, request: Request, db: Db, user: CurrentUser) -> WeeklyStateOut:
    """Plan the week without looking back at the last one."""
    week = normalize_week(day)
    service = _service(request)
    await service.skip_look_back(db, await service.start(db, user.id, week))
    return await _state(request, db, user.id, user.timezone, week)
