"""Task endpoints (CRUD, complete, schedule)."""

import uuid
from datetime import datetime
from typing import Annotated, Any

from fastapi import APIRouter, Query, Request
from pydantic import BaseModel, Field
from sqlalchemy import select

from tefteri.api.deps import CurrentUser, Db
from tefteri.api.schemas import EntryOut, NoteOut, TaskOut, aware
from tefteri.db.models.task import Task
from tefteri.domain.enums import Context
from tefteri.services.context import ContextFilter, load_maps
from tefteri.services.goals import GoalService
from tefteri.services.notes import NoteService
from tefteri.services.tasks import UNSET, TaskService

router = APIRouter(prefix="/tasks", tags=["tasks"])


def _tasks(request: Request) -> TaskService:
    service: TaskService = request.app.state.task_service
    return service


def _goals(request: Request) -> GoalService:
    service: GoalService = request.app.state.goal_service
    return service


def _notes(request: Request) -> NoteService:
    service: NoteService = request.app.state.note_service
    return service


class TaskIn(BaseModel):
    """Data to create a task."""

    connection_id: uuid.UUID
    container_id: uuid.UUID | None = None
    title: str = Field(min_length=1, max_length=500)
    description: str = ""
    due_at: datetime | None = None
    goal_id: uuid.UUID | None = None


class TaskPatch(BaseModel):
    """Partial task update; send ``context: null`` to remove the label."""

    title: str | None = Field(default=None, min_length=1, max_length=500)
    description: str | None = None
    due_at: datetime | None = None
    context: Context | None = None
    goal_id: uuid.UUID | None = None


class ScheduleIn(BaseModel):
    """Start (and optional end) of a task's time slot."""

    start: datetime
    end: datetime | None = None


class ScheduleOut(BaseModel):
    """The task after scheduling, with the calendar entries it overlaps."""

    task: TaskOut
    overlaps: list[EntryOut]


class TaskNoteIn(BaseModel):
    """Link an existing note, or create a new note, for a task."""

    note_id: uuid.UUID | None = None
    title: str | None = Field(default=None, min_length=1, max_length=500)
    body: str = ""


@router.get("")
async def list_tasks(
    db: Db,
    user: CurrentUser,
    context: ContextFilter = ContextFilter.ALL,
    status: str | None = None,
    from_: Annotated[datetime | None, Query(alias="from")] = None,
    to: datetime | None = None,
    unscheduled: bool = False,
    goal_id: uuid.UUID | None = None,
) -> list[TaskOut]:
    """List the user's tasks from the cache."""
    query = select(Task).where(Task.user_id == user.id)
    if status:
        query = query.where(Task.status == status)
    if goal_id:
        query = query.where(Task.goal_id == goal_id)
    maps = await load_maps(db, user.id)
    out = []
    for t in (await db.execute(query)).scalars():
        if unscheduled and t.scheduled_start is not None:
            continue
        if not maps.matches(context, t.context, t.container_id, t.connection_id):
            continue
        when = t.scheduled_start or t.due_at
        if from_ and (when is None or aware(when) < aware(from_)):
            continue
        if to and (when is None or aware(when) >= aware(to)):
            continue
        out.append(TaskOut.of(t, maps))
    return out


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
    )
    return TaskOut.of(task, await load_maps(db, user.id))


@router.get("/{task_id}")
async def get_task(task_id: uuid.UUID, request: Request, db: Db, user: CurrentUser) -> TaskOut:
    """Return one task."""
    task = await _tasks(request).get(db, user.id, task_id)
    return TaskOut.of(task, await load_maps(db, user.id))


@router.patch("/{task_id}")
async def update_task(
    task_id: uuid.UUID, body: TaskPatch, request: Request, db: Db, user: CurrentUser
) -> TaskOut:
    """Change a task in the app (and its label in tefteri)."""
    service = _tasks(request)
    task = await service.get(db, user.id, task_id)
    fields: dict[str, Any] = body.model_dump(exclude_unset=True)
    context: object = fields.pop("context") if "context" in fields else UNSET
    goal_id: object = fields.pop("goal_id") if "goal_id" in fields else UNSET
    if goal_id not in (UNSET, None):
        await _goals(request).get(db, user.id, uuid.UUID(str(goal_id)))  # must be the user's goal
    await service.update(db, user.id, task, context=context, goal_id=goal_id, **fields)
    return TaskOut.of(task, await load_maps(db, user.id))


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
    return TaskOut.of(task, await load_maps(db, user.id))


@router.put("/{task_id}/schedule")
async def schedule_task(
    task_id: uuid.UUID, body: ScheduleIn, request: Request, db: Db, user: CurrentUser
) -> ScheduleOut:
    """Write the task's date and time to the task app. No calendar event is created."""
    service = _tasks(request)
    task = await service.get(db, user.id, task_id)
    task, found = await service.set_schedule(db, user.id, task, body.start, body.end)
    maps = await load_maps(db, user.id)
    return ScheduleOut(task=TaskOut.of(task, maps), overlaps=[EntryOut.of(e, maps) for e in found])


@router.delete("/{task_id}/schedule")
async def unschedule_task(
    task_id: uuid.UUID, request: Request, db: Db, user: CurrentUser
) -> TaskOut:
    """Clear the task's date and time in the task app."""
    service = _tasks(request)
    task = await service.get(db, user.id, task_id)
    task, _ = await service.set_schedule(db, user.id, task, None, None)
    return TaskOut.of(task, await load_maps(db, user.id))


@router.post("/{task_id}/notes", status_code=201)
async def link_note(
    task_id: uuid.UUID, body: TaskNoteIn, request: Request, db: Db, user: CurrentUser
) -> NoteOut:
    """Link an existing note to the task, or create a note and link it."""
    task = await _tasks(request).get(db, user.id, task_id)
    notes = _notes(request)
    if body.note_id is not None:
        note = await notes.get(db, user.id, body.note_id)
        await notes.link(db, user.id, task, note)
    else:
        note = await notes.create_for_task(db, user.id, task, body.title or task.title, body.body)
    return NoteOut.of(note, await load_maps(db, user.id))
