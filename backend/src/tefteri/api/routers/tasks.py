"""Task endpoints (CRUD, complete, schedule)."""

import uuid
from datetime import date as date_type
from datetime import datetime
from typing import Annotated, Any

from fastapi import APIRouter, Query, Request
from pydantic import BaseModel, ConfigDict, Field, model_validator
from sqlalchemy import select

from tefteri.api.deps import CurrentUser, Db
from tefteri.api.lookups import container_colors
from tefteri.api.schemas import EntryOut, TaskOut, aware
from tefteri.db.models.connection import Connection, SourceContainer
from tefteri.db.models.task import Task
from tefteri.services import task_filters
from tefteri.services.goals import GoalService
from tefteri.services.task_filters import DueFilter
from tefteri.services.tasks import UNSET, TaskService

router = APIRouter(prefix="/tasks", tags=["tasks"])


def _opt_aware(value: datetime | None) -> datetime | None:
    return aware(value) if value is not None else None


def _tasks(request: Request) -> TaskService:
    service: TaskService = request.app.state.task_service
    return service


def _goals(request: Request) -> GoalService:
    service: GoalService = request.app.state.goal_service
    return service


async def _out(db: Db, user_id: uuid.UUID, task: Task) -> TaskOut:
    """Return one task with its project name and the link that opens it in its app."""
    project: str | None = None
    container: SourceContainer | None = None
    if task.container_id is not None:
        container = await db.get(SourceContainer, task.container_id)
        project = container.name if container else None
    url: str | None = None
    connection = await db.get(Connection, task.connection_id)
    if connection is not None and connection.provider == "vikunja":
        base = str(connection.settings.get("base_url", "")).rstrip("/")
        if base:
            url = f"{base}/tasks/{task.remote_id}"
    color = container.color if task.container_id is not None and container else None
    return TaskOut.of(task, project=project, url=url, project_color=color)


class TaskIn(BaseModel):
    """Data to create a task."""

    connection_id: uuid.UUID
    container_id: uuid.UUID | None = None
    title: str = Field(min_length=1, max_length=500)
    description: str = ""
    due_at: datetime | None = None
    goal_id: uuid.UUID | None = None
    labels: list[Annotated[str, Field(max_length=100)]] = Field(default_factory=list, max_length=20)
    """Names of labels for the task. A label that does not exist is created in the task app."""


class TaskPatch(BaseModel):
    """Partial task update."""

    title: str | None = Field(default=None, min_length=1, max_length=500)
    description: str | None = None
    due_at: datetime | None = None
    goal_id: uuid.UUID | None = None


class ScheduleIn(BaseModel):
    """Where to plan a task: a block start, or a date only. Send exactly one."""

    model_config = ConfigDict(extra="forbid")

    start: datetime | None = None
    date: date_type | None = None

    @model_validator(mode="after")
    def _exactly_one(self) -> "ScheduleIn":
        if (self.start is None) == (self.date is None):
            raise ValueError("send exactly one of start or date")
        return self


class ScheduleOut(BaseModel):
    """The task after scheduling, with the calendar entries it overlaps."""

    task: TaskOut
    overlaps: list[EntryOut]


def _now(request: Request) -> datetime:
    clock = request.app.state.clock
    now: datetime = clock()
    return now


def _clean_labels(names: list[str]) -> tuple[str, ...]:
    """Trim the names, drop the empty ones and the repeats (case does not count)."""
    seen: dict[str, str] = {}
    for name in names:
        clean = name.strip()
        if clean:
            seen.setdefault(clean.casefold(), clean)
    return tuple(seen.values())


@router.get("")
async def list_tasks(
    request: Request,
    db: Db,
    user: CurrentUser,
    status: str | None = None,
    from_: Annotated[datetime | None, Query(alias="from")] = None,
    to: datetime | None = None,
    unscheduled: bool = False,
    goal_id: uuid.UUID | None = None,
    due: Annotated[
        DueFilter | None,
        Query(description="Filter open tasks by due date in the user's time zone."),
    ] = None,
    q: Annotated[
        str | None,
        Query(description="Title search over all open tasks. When set, ``due`` is ignored."),
    ] = None,
) -> list[TaskOut]:
    """List the user's tasks from the cache.

    ``due`` and ``q`` are the filters of the planner. They list open tasks unless ``status``
    says otherwise. A non-empty ``q`` matches titles case-insensitively across all open tasks
    and ignores ``due``.
    """
    searching = bool(q and q.strip())
    if (due is not None or searching) and not status:
        status = "open"
    query = select(Task).where(Task.user_id == user.id)
    if status:
        query = query.where(Task.status == status)
    if goal_id:
        query = query.where(Task.goal_id == goal_id)
    now = _now(request)
    if due is not None and not searching:
        # The same rule as ``task_filters.matches``, done in the database (kept in step by tests).
        query = query.where(task_filters.sql_condition(due, now, user.timezone))
    needle = (q or "").strip().casefold()
    colors = await container_colors(db, user.id)
    out = []
    for t in (await db.execute(query)).scalars():
        if unscheduled and t.due_at is not None:
            continue
        if searching and needle not in t.title.casefold():
            continue
        when = t.due_at
        if from_ and (when is None or aware(when) < aware(from_)):
            continue
        if to and (when is None or aware(when) >= aware(to)):
            continue
        out.append(
            TaskOut.of(t, project_color=colors.get(t.container_id) if t.container_id else None)
        )
    return out


@router.get("/counts")
async def task_counts(
    request: Request,
    db: Db,
    user: CurrentUser,
) -> dict[str, int]:
    """Count the user's open tasks for each planner filter (the badges of the filter chips)."""
    rows = (
        await db.execute(select(Task).where(Task.user_id == user.id, Task.status == "open"))
    ).scalars()
    pairs = [(_opt_aware(t.due_at), t.all_day) for t in rows]
    return task_filters.counts(pairs, _now(request), user.timezone)


@router.post("", status_code=201)
async def create_task(body: TaskIn, request: Request, db: Db, user: CurrentUser) -> TaskOut:
    """Create a task in the connected task app."""
    task = await _tasks(request).create(
        db,
        user.id,
        connection_id=body.connection_id,
        container_id=body.container_id,
        title=body.title,
        description=body.description,
        due_at=body.due_at,
        goal_id=body.goal_id,
        labels=_clean_labels(body.labels),
    )
    return await _out(db, user.id, task)


@router.get("/{task_id}")
async def get_task(task_id: uuid.UUID, request: Request, db: Db, user: CurrentUser) -> TaskOut:
    """Return one task."""
    task = await _tasks(request).get(db, user.id, task_id)
    return await _out(db, user.id, task)


@router.patch("/{task_id}")
async def update_task(
    task_id: uuid.UUID, body: TaskPatch, request: Request, db: Db, user: CurrentUser
) -> TaskOut:
    """Change a task in the app (and its label in tefteri)."""
    service = _tasks(request)
    task = await service.get(db, user.id, task_id)
    fields: dict[str, Any] = body.model_dump(exclude_unset=True)
    goal_id: object = fields.pop("goal_id") if "goal_id" in fields else UNSET
    if goal_id not in (UNSET, None):
        await _goals(request).get(db, user.id, uuid.UUID(str(goal_id)))  # must be the user's goal
    await service.update(db, user.id, task, goal_id=goal_id, **fields)
    return await _out(db, user.id, task)


@router.delete("/{task_id}", status_code=204)
async def delete_task(task_id: uuid.UUID, request: Request, db: Db, user: CurrentUser) -> None:
    """Delete a task in the app."""
    service = _tasks(request)
    await service.delete(db, user.id, await service.get(db, user.id, task_id))


@router.post("/{task_id}/complete")
async def complete_task(task_id: uuid.UUID, request: Request, db: Db, user: CurrentUser) -> TaskOut:
    """Mark a task done in the app."""
    service = _tasks(request)
    task = await service.complete(db, user.id, await service.get(db, user.id, task_id))
    return await _out(db, user.id, task)


@router.post("/{task_id}/reopen")
async def reopen_task(task_id: uuid.UUID, request: Request, db: Db, user: CurrentUser) -> TaskOut:
    """Mark a done task open again in the app."""
    service = _tasks(request)
    task = await service.reopen(db, user.id, await service.get(db, user.id, task_id))
    return await _out(db, user.id, task)


@router.put("/{task_id}/schedule")
async def schedule_task(
    task_id: uuid.UUID, body: ScheduleIn, request: Request, db: Db, user: CurrentUser
) -> ScheduleOut:
    """Write the task's due date and time to the task app. No calendar event is created.

    ``start`` plans a one-hour block that starts there (the due time is one hour later).
    ``date`` plans a date only (all-day, or a random time if the user's setting is on).
    """
    service = _tasks(request)
    task = await service.get(db, user.id, task_id)
    if body.start is not None:
        task, found = await service.schedule_at(db, user.id, task, body.start)
    else:
        assert body.date is not None  # noqa: S101 - checked by the model validator
        task, found = await service.schedule_date(db, user.id, task, body.date)
    return ScheduleOut(task=TaskOut.of(task), overlaps=[EntryOut.of(e) for e in found])


@router.delete("/{task_id}/schedule")
async def unschedule_task(
    task_id: uuid.UUID, request: Request, db: Db, user: CurrentUser
) -> TaskOut:
    """Clear the task's due date and time in the task app."""
    service = _tasks(request)
    task = await service.get(db, user.id, task_id)
    task = await service.unschedule(db, user.id, task)
    return await _out(db, user.id, task)
