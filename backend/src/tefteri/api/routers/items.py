"""Read endpoints for cached tasks, calendar entries and notes."""

import uuid
from datetime import datetime

from fastapi import APIRouter
from pydantic import BaseModel
from sqlalchemy import select

from tefteri.api.deps import CurrentUser, Db
from tefteri.db.models.calendar_entry import CalendarEntry
from tefteri.db.models.note import Note
from tefteri.db.models.task import Task

router = APIRouter(tags=["items"])


class TaskOut(BaseModel):
    """A cached task."""

    id: uuid.UUID
    connection_id: uuid.UUID
    title: str
    description: str
    status: str
    due_at: datetime | None
    scheduled_start: datetime | None
    scheduled_end: datetime | None
    context: str | None
    sync_state: str


class EntryOut(BaseModel):
    """A cached calendar entry."""

    id: uuid.UUID
    connection_id: uuid.UUID
    title: str
    start: datetime
    end: datetime
    all_day: bool
    location: str
    context: str | None
    sync_state: str


class NoteOut(BaseModel):
    """A cached note."""

    id: uuid.UUID
    connection_id: uuid.UUID
    kind: str
    title: str
    body: str
    context: str | None
    sync_state: str


@router.get("/tasks")
async def list_tasks(db: Db, user: CurrentUser) -> list[TaskOut]:
    """List the user's tasks from the cache."""
    rows = (await db.execute(select(Task).where(Task.user_id == user.id))).scalars()
    return [TaskOut.model_validate(r, from_attributes=True) for r in rows]


@router.get("/calendar")
async def list_calendar(db: Db, user: CurrentUser) -> list[EntryOut]:
    """List the user's calendar entries from the cache."""
    rows = (
        await db.execute(select(CalendarEntry).where(CalendarEntry.user_id == user.id))
    ).scalars()
    return [EntryOut.model_validate(r, from_attributes=True) for r in rows]


@router.get("/notes")
async def list_notes(db: Db, user: CurrentUser) -> list[NoteOut]:
    """List the user's notes from the cache."""
    rows = (await db.execute(select(Note).where(Note.user_id == user.id))).scalars()
    return [NoteOut.model_validate(r, from_attributes=True) for r in rows]
