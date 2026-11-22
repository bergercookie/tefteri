"""Reminders: what the app tells the user about, and when.

The server works this out and the phone only schedules it. A reminder is one of:

* a task with a time, ``default_reminder_minutes`` before it. A task that the user planned
  for a time of day counts from the start of its block (its due time is the end of the block);
  any other task counts from its due time. The task needs no reminder in the task app. A task
  that is done, a task that the task app deleted and a task with only a day (no time of day)
  get none;
* a calendar event with a start time, ``event_reminder_minutes`` before it starts. An event that
  is in more than one calendar is one reminder, not one for each calendar;
* the weekly review, on Sunday at 12:00, the monthly review, on the last day of the month at
  12:00, and the annual review, on 26 December at 12:00 and on 31 December at 15:00, all in the
  time zone of the user. A review that is done by then gets no reminder.

Every reminder has an id that stays the same for the same thing, so a phone can tell a reminder
it knows from a new one, and shows each one once.
"""

import calendar
import uuid
from dataclasses import dataclass
from datetime import UTC, date, datetime, time, timedelta
from zoneinfo import ZoneInfo

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from tefteri.db.models.calendar_entry import CalendarEntry
from tefteri.db.models.connection import SourceContainer
from tefteri.db.models.monthly import MonthlyReview
from tefteri.db.models.review_note import ReviewNote
from tefteri.db.models.task import Task
from tefteri.db.models.user import User
from tefteri.db.models.weekly import WeeklyPlan
from tefteri.domain.enums import SyncState
from tefteri.services.errors import NotFound

WEEKLY_REVIEW_AT = time(12, 0)
MONTHLY_REVIEW_AT = time(12, 0)
ANNUAL_REVIEW_DAYS = ((26, time(12, 0)), (31, time(15, 0)))
"""The days of December of the annual review reminders, and the time of each."""
MAX_HOURS = 24 * 7
"""The most hours ahead that one call looks."""


@dataclass(frozen=True)
class Reminder:
    """One notification that the app shows at ``fire_at``."""

    id: str
    kind: str  # task | event | weekly_review | monthly_review | annual_review
    title: str
    body: str
    fire_at: datetime
    """When to show it, as an aware UTC time."""
    link: str
    """The path in the app that a tap on the notification opens."""


def _utc(value: datetime) -> datetime:
    return value if value.tzinfo else value.replace(tzinfo=UTC)


def _clock(moment: datetime, zone: ZoneInfo) -> str:
    return moment.astimezone(zone).strftime("%H:%M")


def _at(day: date, at: time, zone: ZoneInfo) -> datetime:
    return datetime.combine(day, at, tzinfo=zone).astimezone(UTC)


def _minutes(minutes: int) -> str:
    if minutes == 0:
        return "now"
    if minutes % 1440 == 0:
        days = minutes // 1440
        return f"in {days} day" + ("" if days == 1 else "s")
    if minutes % 60 == 0:
        hours = minutes // 60
        return f"in {hours} hour" + ("" if hours == 1 else "s")
    return f"in {minutes} minutes"


class ReminderService:
    """Work out the reminders of a user for a stretch of time."""

    async def upcoming(
        self, db: AsyncSession, user_id: uuid.UUID, *, start: datetime, hours: int
    ) -> list[Reminder]:
        """Return the reminders that fire from ``start`` for ``hours`` hours, earliest first."""
        user = await db.get(User, user_id)
        if user is None:
            raise NotFound
        start = _utc(start)
        end = start + timedelta(hours=max(1, min(hours, MAX_HOURS)))
        zone = ZoneInfo(user.timezone)
        found = [
            *await self._tasks(db, user, zone, start, end),
            *await self._events(db, user, zone, start, end),
            *await self._reviews(db, user, zone, start, end),
        ]
        return sorted(found, key=lambda r: (r.fire_at, r.id))

    async def _tasks(
        self, db: AsyncSession, user: User, zone: ZoneInfo, start: datetime, end: datetime
    ) -> list[Reminder]:
        before = timedelta(minutes=user.default_reminder_minutes)
        names = {
            c.id: c.name
            for c in (
                await db.execute(select(SourceContainer).where(SourceContainer.user_id == user.id))
            ).scalars()
        }
        out: list[Reminder] = []
        for t in (
            await db.execute(
                select(Task).where(
                    Task.user_id == user.id,
                    Task.status != "done",
                    Task.sync_state != SyncState.DELETED_REMOTELY.value,
                    Task.due_at.is_not(None),
                    Task.all_day.is_(False),
                )
            )
        ).scalars():
            # A task planned for a time starts at the start of its block; its due time is the end.
            planned = t.scheduled_start is not None
            anchor = _utc(t.scheduled_start) if t.scheduled_start is not None else None
            if anchor is None:
                assert t.due_at is not None  # noqa: S101 - selected above
                anchor = _utc(t.due_at)
            fire = anchor - before
            if not start <= fire <= end:
                continue
            project = names.get(t.container_id) if t.container_id else None
            when = f"{'Starts' if planned else 'Due'} at {_clock(anchor, zone)}"
            out.append(
                Reminder(
                    id=f"task:{t.id}:{anchor.isoformat()}",
                    kind="task",
                    title=t.title,
                    body=f"{when} · {project}" if project else when,
                    fire_at=fire,
                    link=f"/?date={anchor.astimezone(zone).date().isoformat()}",
                )
            )
        return out

    async def _events(
        self, db: AsyncSession, user: User, zone: ZoneInfo, start: datetime, end: datetime
    ) -> list[Reminder]:
        before = timedelta(minutes=user.event_reminder_minutes)
        seen: set[str] = set()
        out: list[Reminder] = []
        rows = (
            await db.execute(
                select(CalendarEntry)
                .where(
                    CalendarEntry.user_id == user.id,
                    CalendarEntry.all_day.is_(False),
                    CalendarEntry.sync_state != SyncState.DELETED_REMOTELY.value,
                )
                .order_by(CalendarEntry.start, CalendarEntry.id)
            )
        ).scalars()
        for e in rows:
            begins = _utc(e.start)
            fire = begins - before
            if not start <= fire <= end:
                continue
            # An event that is in more than one calendar has the same UID in each. Without a UID,
            # the same title at the same time is taken to be the same event.
            identity = (
                e.uid or f"{e.title.casefold()}|{begins.isoformat()}|{_utc(e.end).isoformat()}"
            )
            key = f"{identity}|{begins.isoformat()}"
            if key in seen:
                continue
            seen.add(key)
            when = f"Starts at {_clock(begins, zone)}"
            out.append(
                Reminder(
                    id=f"event:{key}",
                    kind="event",
                    title=e.title,
                    body=f"{when} · {e.location}" if e.location else when,
                    fire_at=fire,
                    link=f"/?date={begins.astimezone(zone).date().isoformat()}",
                )
            )
        return out

    async def _reviews(
        self, db: AsyncSession, user: User, zone: ZoneInfo, start: datetime, end: datetime
    ) -> list[Reminder]:
        first = start.astimezone(zone).date() - timedelta(days=1)
        last = end.astimezone(zone).date() + timedelta(days=1)
        out: list[Reminder] = []
        day = first
        while day <= last:
            for reminder in await self._reviews_of(db, user, zone, day):
                if start <= reminder.fire_at <= end:
                    out.append(reminder)
            day += timedelta(days=1)
        return out

    async def _reviews_of(
        self, db: AsyncSession, user: User, zone: ZoneInfo, day: date
    ) -> list[Reminder]:
        out: list[Reminder] = []
        if day.weekday() == 6:  # Sunday
            monday = day - timedelta(days=6)
            if not await self._weekly_done(db, user.id, monday):
                out.append(
                    Reminder(
                        id=f"weekly_review:{monday.isoformat()}",
                        kind="weekly_review",
                        title="Time for your weekly review",
                        body="Look back at this week and plan the next one.",
                        fire_at=_at(day, WEEKLY_REVIEW_AT, zone),
                        link=f"/week/plan?date={(monday + timedelta(days=7)).isoformat()}",
                    )
                )
        if day.day == calendar.monthrange(day.year, day.month)[1]:
            first = day.replace(day=1)
            if not await self._monthly_done(db, user.id, first):
                out.append(
                    Reminder(
                        id=f"monthly_review:{first:%Y-%m}",
                        kind="monthly_review",
                        title="Time for your monthly review",
                        body=f"Review {first:%B %Y} and set up the next month.",
                        fire_at=_at(day, MONTHLY_REVIEW_AT, zone),
                        link=f"/month/review?date={first.isoformat()}",
                    )
                )
        if day.month == 12:
            for number, at in ANNUAL_REVIEW_DAYS:
                if day.day == number and not await self._annual_done(db, user.id, day.year):
                    out.append(
                        Reminder(
                            id=f"annual_review:{day.year}:{number}",
                            kind="annual_review",
                            title="Time for your annual review"
                            if number == 26
                            else f"Your {day.year} review is still open",
                            body=f"Look back at {day.year} before the year ends.",
                            fire_at=_at(day, at, zone),
                            link=f"/year/{day.year}",
                        )
                    )
        return out

    @staticmethod
    async def _weekly_done(db: AsyncSession, user_id: uuid.UUID, monday: date) -> bool:
        """The week was looked back on, or the user committed the plan of the week after it."""
        plans = {
            p.week_start: p
            for p in (
                await db.execute(
                    select(WeeklyPlan).where(
                        WeeklyPlan.user_id == user_id,
                        WeeklyPlan.week_start.in_([monday, monday + timedelta(days=7)]),
                    )
                )
            ).scalars()
        }
        this = plans.get(monday)
        following = plans.get(monday + timedelta(days=7))
        return (this is not None and this.reviewed_at is not None) or (
            following is not None and following.status == "committed"
        )

    @staticmethod
    async def _monthly_done(db: AsyncSession, user_id: uuid.UUID, first: date) -> bool:
        """The monthly review of the month was saved."""
        found = await db.scalar(
            select(MonthlyReview.id).where(
                MonthlyReview.user_id == user_id, MonthlyReview.month == first
            )
        )
        return found is not None

    @staticmethod
    async def _annual_done(db: AsyncSession, user_id: uuid.UUID, year: int) -> bool:
        """The user wrote a review note for the year: the one thing that an annual review saves."""
        found = await db.scalar(
            select(ReviewNote.id).where(ReviewNote.user_id == user_id, ReviewNote.year == year)
        )
        return found is not None
