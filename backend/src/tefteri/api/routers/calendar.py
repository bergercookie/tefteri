"""Calendar endpoints: the combined view and entry CRUD."""

import uuid
from datetime import UTC, datetime
from typing import Annotated

from fastapi import APIRouter, Query, Request
from pydantic import BaseModel, Field
from sqlalchemy import select

from tefteri.api.deps import CurrentUser, Db
from tefteri.api.schemas import CalendarItemOut, EntryOut, aware
from tefteri.db.models.calendar_entry import CalendarEntry
from tefteri.db.models.task import Task
from tefteri.domain.enums import Context
from tefteri.domain.timeutil import overlaps
from tefteri.services.calendar import CalendarService
from tefteri.services.context import ContextFilter, load_maps
from tefteri.services.tasks import UNSET

router = APIRouter(tags=["calendar"])


def _calendar(request: Request) -> CalendarService:
    service: CalendarService = request.app.state.calendar_service
    return service


class EntryIn(BaseModel):
    """Data to create a calendar entry."""

    connection_id: uuid.UUID
    container_id: uuid.UUID | None = None
    title: str = Field(min_length=1, max_length=500)
    start: datetime
    end: datetime
    all_day: bool = False
    location: str = ""


class EntryPatch(BaseModel):
    """Partial entry update; send ``context: null`` to remove the label."""

    title: str | None = Field(default=None, min_length=1, max_length=500)
    start: datetime | None = None
    end: datetime | None = None
    location: str | None = None
    context: Context | None = None


@router.get("/calendar")
async def list_calendar(
    db: Db,
    user: CurrentUser,
    from_: Annotated[datetime | None, Query(alias="from")] = None,
    to: datetime | None = None,
    context: ContextFilter = ContextFilter.ALL,
) -> list[CalendarItemOut]:
    """Return calendar entries and tasks with a due date (``type`` says which) in a window.

    A timed task is the block that ends at its due time; a date-only task is ``all_day``.
    """
    maps = await load_maps(db, user.id)
    items: list[CalendarItemOut] = []
    entries = (
        await db.execute(select(CalendarEntry).where(CalendarEntry.user_id == user.id))
    ).scalars()
    for e in entries:
        if e.sync_state == "deleted_remotely":
            continue
        if not maps.matches(context, e.context, e.container_id, e.connection_id):
            continue
        items.append(CalendarItemOut.of_entry(e, maps))
    tasks = (
        await db.execute(select(Task).where(Task.user_id == user.id, Task.due_at.is_not(None)))
    ).scalars()
    for t in tasks:
        if t.sync_state == "deleted_remotely":
            continue
        if not maps.matches(context, t.context, t.container_id, t.connection_id):
            continue
        items.append(CalendarItemOut.of_task(t, maps, user.timezone))
    if from_ or to:
        low = aware(from_) if from_ else datetime.min.replace(tzinfo=UTC)
        high = aware(to) if to else datetime.max.replace(tzinfo=UTC)
        items = [i for i in items if overlaps(aware(i.start), aware(i.end), low, high)]
    return sorted(items, key=lambda i: aware(i.start))


@router.post("/calendar/entries", status_code=201)
async def create_entry(body: EntryIn, request: Request, db: Db, user: CurrentUser) -> EntryOut:
    """Create an event in the connected calendar."""
    entry = await _calendar(request).create(db, user.id, **body.model_dump())
    return EntryOut.of(entry, await load_maps(db, user.id))


@router.patch("/calendar/entries/{entry_id}")
async def update_entry(
    entry_id: uuid.UUID, body: EntryPatch, request: Request, db: Db, user: CurrentUser
) -> EntryOut:
    """Change an event in the calendar app (and its label in tefteri)."""
    service = _calendar(request)
    entry = await service.get(db, user.id, entry_id)
    fields = body.model_dump(exclude_unset=True)
    context: object = fields.pop("context") if "context" in fields else UNSET
    await service.update(db, user.id, entry, context=context, **fields)
    return EntryOut.of(entry, await load_maps(db, user.id))


@router.delete("/calendar/entries/{entry_id}", status_code=204)
async def delete_entry(entry_id: uuid.UUID, request: Request, db: Db, user: CurrentUser) -> None:
    """Delete an event in the calendar app."""
    service = _calendar(request)
    await service.delete(db, user.id, await service.get(db, user.id, entry_id))
