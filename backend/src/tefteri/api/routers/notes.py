"""Note endpoints: list, daily note, and custom and process notes linked to tasks."""

import uuid
from datetime import date
from typing import Annotated, Literal

from fastapi import APIRouter, Query, Request
from pydantic import BaseModel, Field
from sqlalchemy import select

from tefteri.api.deps import CurrentUser, Db
from tefteri.api.schemas import NoteOut
from tefteri.db.models.note import Note
from tefteri.domain.enums import Context
from tefteri.services.context import ContextFilter, load_maps
from tefteri.services.notes import NoteService
from tefteri.services.tasks import TaskService

router = APIRouter(prefix="/notes", tags=["notes"])


def _notes(request: Request) -> NoteService:
    service: NoteService = request.app.state.note_service
    return service


def _tasks(request: Request) -> TaskService:
    service: TaskService = request.app.state.task_service
    return service


class NoteIn(BaseModel):
    """Data to create a documentation (``custom``) or process note."""

    title: str = Field(min_length=1, max_length=500)
    body: str = ""
    kind: Literal["custom", "process"] = "custom"
    context: Context | None = None
    connection_id: uuid.UUID | None = None
    task_ids: list[uuid.UUID] = Field(default_factory=list)


class NotePatchIn(BaseModel):
    """Partial note update. ``context: null`` clears the note's own context."""

    title: str | None = Field(default=None, min_length=1, max_length=500)
    body: str | None = None
    context: Context | None = None


class NoteDetailOut(NoteOut):
    """A note with the ids of the tasks it is linked to."""

    task_ids: list[uuid.UUID]


class AppendIn(BaseModel):
    """Text to append to a daily note, with an optional task to link."""

    text: str = Field(min_length=1)
    task_id: uuid.UUID | None = None


@router.get("")
async def list_notes(
    db: Db,
    user: CurrentUser,
    context: ContextFilter = ContextFilter.ALL,
    kind: str | None = None,
    date_: Annotated[date | None, Query(alias="date")] = None,
) -> list[NoteOut]:
    """List the user's notes from the cache."""
    query = select(Note).where(Note.user_id == user.id)
    if kind:
        query = query.where(Note.kind == kind)
    if date_:
        query = query.where(Note.note_date == date_)
    maps = await load_maps(db, user.id)
    return [
        NoteOut.of(n, maps)
        for n in (await db.execute(query)).scalars()
        if maps.matches(context, n.context, None, n.connection_id)
    ]


@router.get("/daily/{day}")
async def daily_note(day: date, request: Request, db: Db, user: CurrentUser) -> NoteOut:
    """Return the daily note for a date, creating it in the note app when missing."""
    note = await _notes(request).daily(db, user.id, day)
    return NoteOut.of(note, await load_maps(db, user.id))


@router.post("/daily/{day}/append")
async def append_daily(
    day: date, body: AppendIn, request: Request, db: Db, user: CurrentUser
) -> NoteOut:
    """Add text to the daily note and optionally link the note to a task."""
    note = await _notes(request).append_daily(db, user.id, day, body.text, body.task_id)
    return NoteOut.of(note, await load_maps(db, user.id))


async def _detail(request: Request, db: Db, user_id: uuid.UUID, note: Note) -> NoteDetailOut:
    tasks = await _notes(request).linked_tasks(db, user_id, note)
    base = NoteOut.of(note, await load_maps(db, user_id))
    return NoteDetailOut(**base.model_dump(), task_ids=[t.id for t in tasks])


@router.post("", status_code=201)
async def create_note(body: NoteIn, request: Request, db: Db, user: CurrentUser) -> NoteDetailOut:
    """Create a documentation or process note in the note app and link it to tasks."""
    tasks = [await _tasks(request).get(db, user.id, t) for t in body.task_ids]
    note = await _notes(request).create(
        db,
        user.id,
        title=body.title,
        body=body.body,
        kind=body.kind,
        context=body.context,
        connection_id=body.connection_id,
        tasks=tasks,
    )
    return await _detail(request, db, user.id, note)


@router.get("/{note_id}")
async def get_note(
    note_id: uuid.UUID, request: Request, db: Db, user: CurrentUser
) -> NoteDetailOut:
    """Return one note with its linked tasks."""
    return await _detail(request, db, user.id, await _notes(request).get(db, user.id, note_id))


@router.patch("/{note_id}")
async def update_note(
    note_id: uuid.UUID, body: NotePatchIn, request: Request, db: Db, user: CurrentUser
) -> NoteDetailOut:
    """Change a note's title or body in the note app, or its context in tefteri."""
    service = _notes(request)
    note = await service.get(db, user.id, note_id)
    note = await service.update(db, user.id, note, **body.model_dump(exclude_unset=True))
    return await _detail(request, db, user.id, note)


@router.delete("/{note_id}", status_code=204)
async def delete_note(note_id: uuid.UUID, request: Request, db: Db, user: CurrentUser) -> None:
    """Delete a note in the note app and in tefteri; its task links go with it."""
    service = _notes(request)
    await service.delete(db, user.id, await service.get(db, user.id, note_id))
