"""Aggregated planning views."""

from datetime import date
from zoneinfo import ZoneInfo

from fastapi import APIRouter, Request
from sqlalchemy import select

from tefteri.api.deps import CurrentUser, Db
from tefteri.api.schemas import DayView, EntryOut, NoteOut, TaskOut, aware
from tefteri.db.models.calendar_entry import CalendarEntry
from tefteri.db.models.note import Note
from tefteri.db.models.task import Task
from tefteri.domain.timeutil import day_bounds, overlaps

router = APIRouter(prefix="/views", tags=["views"])


@router.get("/day/{day}")
async def day_view(
    day: date,
    request: Request,
    db: Db,
    user: CurrentUser,
) -> DayView:
    """Return the day's entries, tasks (scheduled or due that day) and daily note.

    The day is the user's local day (their time zone), so daylight-saving days are correct.
    """
    start, end = day_bounds(day, user.timezone)
    ZoneInfo(user.timezone)
    entries = [
        EntryOut.of(e)
        for e in (
            await db.execute(select(CalendarEntry).where(CalendarEntry.user_id == user.id))
        ).scalars()
        if e.sync_state != "deleted_remotely" and overlaps(aware(e.start), aware(e.end), start, end)
    ]
    tasks = []
    for t in (await db.execute(select(Task).where(Task.user_id == user.id))).scalars():
        if t.sync_state == "deleted_remotely":
            continue
        when = t.due_at
        if when is None or not (start <= aware(when) < end):
            continue
        tasks.append(TaskOut.of(t))
    note_row = (
        (
            await db.execute(
                select(Note).where(
                    Note.user_id == user.id, Note.note_date == day, Note.kind == "daily"
                )
            )
        )
        .scalars()
        .first()
    )
    note = NoteOut.of(note_row) if note_row else None
    return DayView(
        date=day.isoformat(), entries=sorted(entries, key=lambda e: e.start), tasks=tasks, note=note
    )
