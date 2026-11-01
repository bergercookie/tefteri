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
from tefteri.services.context import ContextFilter, load_maps

router = APIRouter(prefix="/views", tags=["views"])


@router.get("/day/{day}")
async def day_view(
    day: date,
    request: Request,
    db: Db,
    user: CurrentUser,
    context: ContextFilter = ContextFilter.ALL,
) -> DayView:
    """Return the day's entries, tasks (scheduled or due that day) and daily note.

    The day is the user's local day (their time zone), so daylight-saving days are correct.
    """
    start, end = day_bounds(day, user.timezone)
    ZoneInfo(user.timezone)
    maps = await load_maps(db, user.id)
    entries = [
        EntryOut.of(e, maps)
        for e in (
            await db.execute(select(CalendarEntry).where(CalendarEntry.user_id == user.id))
        ).scalars()
        if e.sync_state != "deleted_remotely"
        and overlaps(aware(e.start), aware(e.end), start, end)
        and maps.matches(context, e.context, e.container_id, e.connection_id)
    ]
    tasks = []
    for t in (await db.execute(select(Task).where(Task.user_id == user.id))).scalars():
        if t.sync_state == "deleted_remotely":
            continue
        when = t.scheduled_start or t.due_at
        if when is None or not (start <= aware(when) < end):
            continue
        if maps.matches(context, t.context, t.container_id, t.connection_id):
            tasks.append(TaskOut.of(t, maps))
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
    note = (
        NoteOut.of(note_row, maps)
        if note_row and maps.matches(context, note_row.context, None, note_row.connection_id)
        else None
    )
    return DayView(
        date=day.isoformat(), entries=sorted(entries, key=lambda e: e.start), tasks=tasks, note=note
    )
