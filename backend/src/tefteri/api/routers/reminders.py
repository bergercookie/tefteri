"""The reminders that the app shows as notifications."""

from datetime import datetime
from typing import Annotated

from fastapi import APIRouter, Query, Request
from pydantic import BaseModel

from tefteri.api.deps import CurrentUser, Db
from tefteri.api.schemas import UtcDatetime
from tefteri.services.reminders import MAX_HOURS, Reminder, ReminderService

router = APIRouter(prefix="/reminders", tags=["reminders"])
_service = ReminderService()


class ReminderOut(BaseModel):
    """One notification to show."""

    id: str
    """Stays the same for the same task, event or review. Show each id once."""
    kind: str
    """``task``, ``event``, ``weekly_review``, ``monthly_review`` or ``annual_review``."""
    title: str
    body: str
    fire_at: UtcDatetime
    link: str
    """The path in the app that a tap opens, for example ``/week/plan?date=2030-03-11``."""

    @classmethod
    def of(cls, r: Reminder) -> "ReminderOut":
        """Build from a reminder."""
        return cls(id=r.id, kind=r.kind, title=r.title, body=r.body, fire_at=r.fire_at, link=r.link)


class RemindersOut(BaseModel):
    """The reminders of a stretch of time."""

    reminders: list[ReminderOut]


@router.get("")
async def upcoming_reminders(
    request: Request,
    db: Db,
    user: CurrentUser,
    start: Annotated[datetime | None, Query(alias="from")] = None,
    hours: Annotated[int, Query(ge=1, le=MAX_HOURS)] = 48,
) -> RemindersOut:
    """Return the reminders that fire from ``from`` (default: now) for ``hours`` hours.

    A task or an event that is in this list is not done, not deleted and not a copy of another
    event in a second calendar. A review that is done is not in the list.
    """
    begin = start if start is not None else request.app.state.clock()
    found = await _service.upcoming(db, user.id, start=begin, hours=hours)
    return RemindersOut(reminders=[ReminderOut.of(r) for r in found])
