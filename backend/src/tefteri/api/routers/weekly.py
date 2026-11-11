"""Weekly planning: commit milestone projects, give tasks a day, review the week (spec 004)."""

import uuid
from datetime import date, datetime, timedelta
from typing import Literal
from zoneinfo import ZoneInfo

from fastapi import APIRouter, Request
from pydantic import BaseModel, ConfigDict, Field

from tefteri.api.deps import CurrentUser, Db
from tefteri.api.schemas import UtcDatetime
from tefteri.db.models.connection import Connection
from tefteri.db.models.weekly import WeeklyPlan
from tefteri.services.errors import NotFound
from tefteri.services.weekly import (
    MILESTONE_CAP,
    Answer,
    Candidate,
    CloseInfo,
    LookBack,
    PlanFacts,
    ProjectView,
    TaskView,
    ThemeTag,
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


class ThemeOut(BaseModel):
    """A theme project: the id of its label row (as in the project API) and its name."""

    id: uuid.UUID
    name: str

    @classmethod
    def of(cls, theme: ThemeTag | None) -> "ThemeOut | None":
        """Build from the theme that an entry stored, or ``None`` for no theme."""
        return cls(id=theme.id, name=theme.name) if theme else None


class ProjectOut(BaseModel):
    """A milestone of the plan."""

    id: uuid.UUID
    container_id: uuid.UUID | None
    milestone_id: uuid.UUID | None = None
    """``None`` for an entry from before milestones."""
    name: str
    done_state: str | None = None
    milestone_state: str | None = None
    """``active``, ``parked``, ``closed`` or ``done``; ``None`` for an old entry."""
    theme: ThemeOut | None = None
    """The theme when it was committed. ``None`` means no theme."""
    outside_focus: bool = False
    """Computed on read from the monthly focus. Always false without focus data."""
    rollover_count: int = 0
    needs_rescope: bool = False
    """The last two rollovers were not marked as expected: shrink, split or close it."""
    orphaned: bool = False
    notice: str | None = None
    """``relabelled`` when the project got another label after it was committed."""
    color: str | None = None
    """The color of the project in the task app, as ``#rrggbb``."""
    created_here: bool
    url: str | None
    open_tasks: int
    done_tasks: int
    scheduled_tasks: int
    parked_tasks: int
    tasks: list[WeeklyTaskOut]
    """The open tasks, "not this week" ones too (they have ``parked`` set)."""
    committed_tasks: list[WeeklyTaskOut]
    """The tasks planned at the commit, with their state now. Empty before the commit."""


class PlanOut(BaseModel):
    """The plan of one week."""

    id: uuid.UUID
    status: str
    committed_at: UtcDatetime | None
    retro_skipped: bool
    milestone_count: int
    milestone_cap: int = MILESTONE_CAP
    over_cap: bool
    """More milestones than the cap. It is a warning, never a refusal."""
    month: date
    """The first day of the month of the Monday of the week (the month of its focus)."""
    focus_known: bool
    """Monthly focus data exists. Without it nothing is outside focus."""
    projects: list[ProjectOut]

    @classmethod
    def of(cls, plan: WeeklyPlan, facts: PlanFacts, views: list[ProjectView]) -> "PlanOut":
        """Build from the plan, its cap facts and its milestones."""
        return cls(
            id=plan.id,
            status=plan.status,
            committed_at=plan.committed_at,
            retro_skipped=plan.retro_skipped,
            milestone_count=facts.milestone_count,
            over_cap=facts.over_cap,
            month=facts.month,
            focus_known=facts.focus_known,
            projects=[_project_out(v) for v in views],
        )


class CloseOut(BaseModel):
    """Whether the tasks of a milestone can go back to its theme."""

    available: bool
    reason: str | None
    """``no_theme``, ``theme_unusable``, ``not_supported`` or ``None``."""
    open_tasks: int
    theme_name: str | None

    @classmethod
    def of(cls, info: CloseInfo | None) -> "CloseOut | None":
        """Build from the service value."""
        if info is None:
            return None
        return cls(
            available=info.available,
            reason=info.reason,
            open_tasks=info.open_tasks,
            theme_name=info.theme_name,
        )


class LookBackProjectOut(BaseModel):
    """How a milestone of the earlier week went."""

    id: uuid.UUID
    milestone_id: uuid.UUID | None
    name: str
    done_state: str | None
    theme: ThemeOut | None
    milestone_state: str | None
    color: str | None = None
    committed: int
    done: int
    completed: bool
    outcome: str | None
    decision: str | None
    """``recommit``, ``park``, ``close``, ``decide_later`` or ``None``. An old ``carry`` shows
    as ``recommit`` and an old ``backlog`` as ``park``."""
    expected_rollover: bool | None
    legacy: bool
    """The entry is from before milestones, or has an old choice."""
    rollover_count: int
    needs_rescope: bool
    outside_focus: bool
    close: CloseOut | None
    leftover: list[WeeklyTaskOut]


class PaceOut(BaseModel):
    """Completed committed tasks of one local day."""

    day: date
    done: int


class SummaryOut(BaseModel):
    """The numbers of the review. Time spent is never measured."""

    committed_tasks: int
    done_tasks: int
    milestones_committed: int
    milestones_done: int
    pace: list[PaceOut]
    focus_share: float | None
    """``None`` without focus data or without a completed committed task."""
    note: str | None
    """A short text instead of ratios when nothing was committed."""


class LookBackOut(BaseModel):
    """The earlier week that the user looks back at."""

    plan_id: uuid.UUID
    week_start: date
    reviewed: bool
    reflection: str
    summary: SummaryOut
    projects: list[LookBackProjectOut]


class ExtraDoneOut(BaseModel):
    """A task that was completed during the week and was not in the committed plan."""

    id: uuid.UUID
    title: str
    completed_day: date
    """The day it was completed, in the time zone of the user."""
    project: str | None = None
    project_color: str | None = None
    url: str | None = None


class WeeklyStateOut(BaseModel):
    """Everything the planning page shows for one week."""

    week_start: date
    week_end: date
    plan: PlanOut | None
    look_back: LookBackOut | None
    done_outside_plan: list[ExtraDoneOut] = Field(default_factory=list)
    """Tasks completed during the week that the committed plan did not promise (oldest first)."""


class CandidateOut(BaseModel):
    """A project the user can commit."""

    container_id: uuid.UUID
    connection_id: uuid.UUID
    connection_name: str
    name: str
    path: str
    kind: str
    """``milestone``, or ``unsorted`` for a project with no label: picking it labels it."""
    milestone_id: uuid.UUID | None
    done_state: str | None
    state: str
    """``active`` or ``parked``."""
    theme: ThemeOut | None
    """``None`` is the group "No theme"."""
    in_focus: bool | None
    """``None`` when no focus data exists."""
    rollover_count: int
    needs_rescope: bool
    decision_open: bool
    """The last review left the milestone with "decide later"."""
    open_tasks: int
    carried_tasks: int
    """Open committed tasks of a milestone that the last review recommitted."""
    selected: bool
    unsorted: bool = False

    @classmethod
    def of(cls, c: Candidate) -> "CandidateOut":
        """Build from a candidate."""
        return cls(
            container_id=c.container.id,
            connection_id=c.connection.id,
            connection_name=c.connection.display_name,
            name=c.container.name,
            path=c.path,
            kind="unsorted" if c.unsorted else "milestone",
            milestone_id=c.milestone.id if c.milestone else None,
            done_state=c.milestone.done_state if c.milestone else None,
            state=c.state.value,
            theme=ThemeOut(id=c.theme.id, name=c.theme.name) if c.theme else None,
            in_focus=c.in_focus,
            rollover_count=c.rollover_count,
            needs_rescope=c.needs_rescope,
            decision_open=c.decision_open,
            open_tasks=c.open_tasks,
            carried_tasks=c.carried_tasks,
            selected=c.selected,
            unsorted=c.unsorted,
        )


class ThemeGroupOut(BaseModel):
    """A theme for the picker headers."""

    id: uuid.UUID
    container_id: uuid.UUID
    """The parent for ``POST /weekly/{day}/milestones``."""
    connection_id: uuid.UUID
    name: str
    in_focus: bool | None
    milestones: int
    open_milestones: int


class ThemesOut(BaseModel):
    """The themes of the picker."""

    focus_known: bool
    themes: list[ThemeGroupOut]
    unsorted_count: int
    """Live projects that still have no label."""


class ProjectIn(BaseModel):
    """The milestone to add."""

    container_id: uuid.UUID


class MilestoneIn(BaseModel):
    """A new milestone under a theme."""

    parent_id: uuid.UUID
    """The container id of the theme."""
    name: str = Field(min_length=1, max_length=255)
    done_state: str = Field(default="", max_length=2000)
    """One sentence that says when it is finished. It must not be blank."""


class TaskIn(BaseModel):
    """A new task under a milestone."""

    title: str = Field(min_length=1, max_length=500)


class AnswerIn(BaseModel):
    """The decision about one milestone of the earlier week."""

    model_config = ConfigDict(extra="forbid")

    plan_project_id: uuid.UUID
    decision: Literal["recommit", "park", "close", "decide_later"] | None = None
    """No decision means ``decide_later``. A finished milestone needs none."""
    expected: bool = False
    """The marker of the rollover event, used with ``recommit`` only."""
    mark_done: bool = False
    """Mark the milestone done by hand (nothing is moved or deleted)."""
    archive: bool = False


class ReviewIn(BaseModel):
    """The review."""

    projects: list[AnswerIn] = Field(default_factory=list)
    reflection: str = ""


class HistoryProjectOut(BaseModel):
    """A milestone of a reviewed week."""

    name: str
    done: bool
    decision: str | None = None
    """Under the new names: an old ``carry`` shows as ``recommit``, ``backlog`` as ``park``."""
    legacy: bool = False
    milestone_id: uuid.UUID | None = None
    theme_name: str | None = None
    done_on: date | None = None
    rollover_count: int = 0


class HistoryEntryOut(BaseModel):
    """One reviewed week."""

    plan_id: uuid.UUID
    week_start: date
    committed_projects: int
    """Milestones for a new week, projects for an old one."""
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


class NudgeOut(BaseModel):
    """A milestone that should be shrunk, split or closed."""

    milestone_id: uuid.UUID
    name: str


class ReviewOut(HistoryOut):
    """The history after a review, with what the review changed besides the decisions."""

    notices: list[str] = Field(default_factory=list)
    nudges: list[NudgeOut] = Field(default_factory=list)


def _task_base_url(connection: Connection | None) -> str | None:
    """The address of the task app, when it has pages for projects and tasks."""
    if connection is not None and connection.provider == "vikunja":
        base = str(connection.settings.get("base_url", "")).rstrip("/")
        return base or None
    return None


def _base_url(view: ProjectView) -> str | None:
    return _task_base_url(view.connection)


def _project_out(v: ProjectView) -> ProjectOut:
    base = _base_url(v)
    return ProjectOut(
        id=v.row.id,
        container_id=v.row.container_id,
        milestone_id=v.row.milestone_id,
        name=v.container.name if v.container else v.row.name,
        done_state=v.milestone.done_state if v.milestone else None,
        milestone_state=v.milestone.state if v.milestone else None,
        theme=ThemeOut.of(v.theme),
        outside_focus=v.outside_focus,
        rollover_count=v.rollover_count,
        needs_rescope=v.needs_rescope,
        orphaned=v.orphaned,
        notice=v.notice,
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
    s = back.summary
    return LookBackOut(
        plan_id=back.plan.id,
        week_start=back.plan.week_start,
        reviewed=back.plan.reviewed_at is not None,
        reflection=back.plan.reflection,
        summary=SummaryOut(
            committed_tasks=s.committed_tasks,
            done_tasks=s.done_tasks,
            milestones_committed=s.milestones_committed,
            milestones_done=s.milestones_done,
            pace=[PaceOut(day=d, done=n) for d, n in s.pace],
            focus_share=s.focus_share,
            note=s.note,
        ),
        projects=[
            LookBackProjectOut(
                id=p.row.id,
                milestone_id=p.row.milestone_id,
                name=p.row.name,
                done_state=p.milestone.done_state if p.milestone else None,
                theme=ThemeOut.of(p.theme),
                milestone_state=p.milestone.state if p.milestone else None,
                color=p.color,
                committed=p.committed,
                done=p.done,
                completed=p.completed,
                outcome=p.row.outcome,
                decision=p.decision.value if p.decision else None,
                expected_rollover=p.row.expected_rollover,
                legacy=p.legacy,
                rollover_count=p.rollover_count,
                needs_rescope=p.needs_rescope,
                outside_focus=p.outside_focus,
                close=CloseOut.of(p.close),
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
        plan_out = PlanOut.of(plan, await service.plan_facts(db, user_id, plan, views), views)
    back = await service.look_back(db, user_id, week, tz)
    extra = await service.done_outside_plan(db, user_id, plan, tz) if plan is not None else []
    bases: dict[uuid.UUID, str | None] = {}
    for e in extra:
        if e.task.connection_id not in bases:
            bases[e.task.connection_id] = _task_base_url(
                await db.get(Connection, e.task.connection_id)
            )
    return WeeklyStateOut(
        week_start=week,
        week_end=week + timedelta(days=7),
        plan=plan_out,
        look_back=_look_back_out(back) if back else None,
        done_outside_plan=[
            ExtraDoneOut(
                id=e.task.id,
                title=e.task.title,
                completed_day=e.completed_day,
                project=e.project,
                project_color=e.color,
                url=(
                    f"{bases[e.task.connection_id]}/tasks/{e.task.remote_id}"
                    if bases.get(e.task.connection_id)
                    else None
                ),
            )
            for e in extra
        ],
    )


async def _draft(request: Request, db: Db, user_id: uuid.UUID, week: date) -> WeeklyPlan:
    plan = await _service(request).find(db, user_id, week)
    if plan is None:
        raise NotFound
    return plan


async def _history(request: Request, db: Db, user_id: uuid.UUID) -> HistoryOut:
    entries = []
    for h in await _service(request).history(db, user_id):
        rows = h.projects
        entries.append(
            HistoryEntryOut(
                plan_id=h.plan.id,
                week_start=h.plan.week_start,
                committed_projects=len(rows),
                done_projects=sum(1 for r in rows if r.row.outcome == "done"),
                committed_tasks=sum(r.row.reviewed_committed or 0 for r in rows),
                done_tasks=sum(r.row.reviewed_done or 0 for r in rows),
                reflection=h.plan.reflection,
                projects=[
                    HistoryProjectOut(
                        name=r.row.name,
                        done=r.row.outcome == "done",
                        decision=r.decision.value if r.decision else None,
                        legacy=r.legacy,
                        milestone_id=r.row.milestone_id,
                        theme_name=r.row.theme_name,
                        done_on=r.milestone.done_on if r.milestone else None,
                        rollover_count=r.milestone.rollover_count if r.milestone else 0,
                    )
                    for r in rows
                ],
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


@router.get("/history")
async def history(request: Request, db: Db, user: CurrentUser) -> HistoryOut:
    """List the reviewed weeks: milestones committed to versus milestones done.

    A decision shows under the new names, also for an old week (``carry`` as ``recommit``,
    ``backlog`` as ``park``).
    """
    return await _history(request, db, user.id)


@router.post("/reviews/{plan_id}")
async def review(
    plan_id: uuid.UUID, body: ReviewIn, request: Request, db: Db, user: CurrentUser
) -> ReviewOut:
    """Store the review of a week and return the history, with that week in it.

    Each unfinished milestone gets a decision (no answer means ``decide_later``). The answer
    lists ``notices`` and, for a recommit that now needs re-scoping, ``nudges``.
    """
    result = await _service(request).review(
        db,
        user.id,
        plan_id,
        user.timezone,
        [
            Answer(a.plan_project_id, a.decision, a.expected, a.mark_done, a.archive)
            for a in body.projects
        ],
        body.reflection,
        _now(request),
    )
    base = await _history(request, db, user.id)
    return ReviewOut(
        entries=base.entries,
        totals=base.totals,
        notices=result.notices,
        nudges=[NudgeOut(milestone_id=n.milestone_id, name=n.name) for n in result.nudges],
    )


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
    """List the projects the user may commit: milestones and unsorted leaf projects.

    Themes, maintenance, ignored and orphaned projects are never listed. A project that is
    already in the plan has ``selected`` set.
    """
    found = await _service(request).candidates(db, user.id, normalize_week(day))
    return [CandidateOut.of(c) for c in found]


@router.get("/{day}/themes")
async def themes(day: date, request: Request, db: Db, user: CurrentUser) -> ThemesOut:
    """List the live themes for the picker headers, focus themes first when focus data exists."""
    found = await _service(request).themes(db, user.id, normalize_week(day))
    return ThemesOut(
        focus_known=found.focus_known,
        themes=[
            ThemeGroupOut(
                id=t.row.id,
                container_id=t.container.id,
                connection_id=t.connection.id,
                name=t.row.name,
                in_focus=t.in_focus,
                milestones=t.milestones,
                open_milestones=t.open_milestones,
            )
            for t in found.themes
        ],
        unsorted_count=found.unsorted_count,
    )


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
    await service.refresh(db, user.id, week, plans, user.timezone)
    return await _state(request, db, user.id, user.timezone, week)


@router.post("/{day}/projects", status_code=201)
async def add_project(
    day: date, body: ProjectIn, request: Request, db: Db, user: CurrentUser
) -> WeeklyStateOut:
    """Add a milestone to the week. There is no limit: more than three only warns.

    A project with no label is labelled milestone first. 422 ``not_a_milestone`` for a theme
    or a project with subprojects, 422 ``not_eligible`` for a project that may not be planned.
    """
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


@router.post("/{day}/milestones", status_code=201)
async def create_milestone(
    day: date, body: MilestoneIn, request: Request, db: Db, user: CurrentUser
) -> WeeklyStateOut:
    """Create a milestone under a theme in the task app, label it and add it to the week.

    422 ``done_state_required`` for a blank done-state, before the task app is called. Nothing
    is recorded when the task app fails (409 ``not_supported`` or 502).
    """
    week = normalize_week(day)
    service = _service(request)
    plan = await service.start(db, user.id, week)
    await service.create_milestone(db, user.id, plan, body.parent_id, body.name, body.done_state)
    return await _state(request, db, user.id, user.timezone, week)


@router.post("/{day}/projects/{plan_project_id}/tasks", status_code=201)
async def add_task(
    day: date,
    plan_project_id: uuid.UUID,
    body: TaskIn,
    request: Request,
    db: Db,
    user: CurrentUser,
) -> WeeklyStateOut:
    """Create a task under a milestone of the plan in the task app.

    The task is not committed until it has a day. A committed plan refuses it (422).
    """
    week = normalize_week(day)
    await _service(request).add_task(
        db, user.id, await _draft(request, db, user.id, week), plan_project_id, body.title
    )
    return await _state(request, db, user.id, user.timezone, week)


class ParkedIn(BaseModel):
    """Set a task aside, or put it back."""

    parked: bool


@router.put("/{day}/tasks/{task_id}/parked")
async def park_task(
    day: date, task_id: uuid.UUID, body: ParkedIn, request: Request, db: Db, user: CurrentUser
) -> WeeklyStateOut:
    """Set a task aside for this plan ("not this week"), or put it back. The task app stays as is."""
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
    """Commit the plan: the tasks planned for the week are what the review measures.

    A plan with no milestone can be committed.
    """
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
