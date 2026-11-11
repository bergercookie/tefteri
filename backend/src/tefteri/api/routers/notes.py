"""Note endpoints: list, and the daily note."""

import uuid
from datetime import date
from typing import Annotated

from fastapi import APIRouter, Query, Request
from pydantic import BaseModel, Field
from sqlalchemy import select

from tefteri.api.deps import CurrentUser, Db
from tefteri.api.schemas import NoteOut
from tefteri.db.models.note import Note
from tefteri.services.notes import NoteService

router = APIRouter(prefix="/notes", tags=["notes"])


def _notes(request: Request) -> NoteService:
    service: NoteService = request.app.state.note_service
    return service


class AppendIn(BaseModel):
    """Text to append to a daily note, with an optional task to link."""

    text: str = Field(min_length=1)
    task_id: uuid.UUID | None = None


@router.get("")
async def list_notes(
    db: Db,
    user: CurrentUser,
    kind: str | None = None,
    date_: Annotated[date | None, Query(alias="date")] = None,
) -> list[NoteOut]:
    """List the notes that tefteri created or opened (the note app is not copied)."""
    query = select(Note).where(Note.user_id == user.id)
    if kind:
        query = query.where(Note.kind == kind)
    if date_:
        query = query.where(Note.note_date == date_)
    return [NoteOut.of(n) for n in (await db.execute(query)).scalars()]


@router.get("/daily/{day}")
async def daily_note(day: date, request: Request, db: Db, user: CurrentUser) -> NoteOut:
    """Return the daily note for a date, creating it in the note app when missing."""
    note = await _notes(request).daily(db, user.id, day)
    return NoteOut.of(note)


@router.post("/daily/{day}/append")
async def append_daily(
    day: date, body: AppendIn, request: Request, db: Db, user: CurrentUser
) -> NoteOut:
    """Add text to the daily note and optionally link the note to a task."""
    note = await _notes(request).append_daily(db, user.id, day, body.text, body.task_id)
    return NoteOut.of(note)
