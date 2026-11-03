"""The task filters of the planner: today, tomorrow, this week, all, no due date and overdue.

All rules use the user's local time. The due date is the planned time of a task, so these
rules read only ``due_at`` and ``all_day``. A date-only task is due on its local date and is
overdue only after that date has passed. A timed task is overdue after its due time.
"""

from datetime import UTC, date, datetime, timedelta
from enum import StrEnum
from zoneinfo import ZoneInfo

from sqlalchemy import ColumnElement, and_, false, or_, true

from tefteri.db.models.task import Task
from tefteri.domain.timeutil import day_bounds


class DueFilter(StrEnum):
    """The filters offered at the top of the task view."""

    TODAY = "today"
    TOMORROW = "tomorrow"
    WEEK = "week"
    ALL = "all"
    NONE = "none"
    OVERDUE = "overdue"


def week_bounds(today: date) -> tuple[date, date]:
    """Return the Monday and the Sunday of the week that holds ``today``."""
    monday = today - timedelta(days=today.weekday())
    return monday, monday + timedelta(days=6)


def due_date_of(due_at: datetime, tz_name: str) -> date:
    """Return the local date a task is due on."""
    return due_at.astimezone(ZoneInfo(tz_name)).date()


def matches(
    due_filter: DueFilter,
    due_at: datetime | None,
    all_day: bool,
    now: datetime,
    tz_name: str,
) -> bool:
    """Return whether a task with this planned time belongs to ``due_filter`` at ``now``."""
    if due_filter is DueFilter.ALL:
        return True
    if due_filter is DueFilter.NONE:
        return due_at is None
    if due_at is None:
        return False
    today = now.astimezone(ZoneInfo(tz_name)).date()
    day = due_date_of(due_at, tz_name)
    if due_filter is DueFilter.TODAY:
        return day == today
    if due_filter is DueFilter.TOMORROW:
        return day == today + timedelta(days=1)
    if due_filter is DueFilter.WEEK:
        first, last = week_bounds(today)
        return first <= day <= last
    # OVERDUE
    if all_day:
        return day < today
    return due_at < now


def counts(
    tasks: list[tuple[datetime | None, bool]], now: datetime, tz_name: str
) -> dict[str, int]:
    """Count ``(due_at, all_day)`` pairs of open tasks for each filter."""
    return {
        f.value: sum(1 for due_at, all_day in tasks if matches(f, due_at, all_day, now, tz_name))
        for f in DueFilter
    }


def sql_condition(due_filter: DueFilter, now: datetime, tz_name: str) -> ColumnElement[bool]:
    """Return the same rule as :func:`matches` as a SQL condition on ``Task``.

    A date-only task is stored at 00:00 local time of its date and a timed task lies inside its
    local day, so a local day is the UTC range ``[start, end)`` of that day. The list endpoint
    uses this to avoid loading every task; the counts use :func:`matches`, and a test keeps
    both in step.
    """
    if due_filter is DueFilter.ALL:
        return true()
    if due_filter is DueFilter.NONE:
        return Task.due_at.is_(None)
    today = now.astimezone(ZoneInfo(tz_name)).date()
    # Bind UTC values only: SQLite drops the zone of an aware datetime without converting it.
    today_start = day_bounds(today, tz_name)[0].astimezone(UTC)
    if due_filter is DueFilter.OVERDUE:
        return or_(
            and_(Task.all_day.is_(False), Task.due_at < now.astimezone(UTC)),
            and_(Task.all_day.is_(True), Task.due_at < today_start),
        )
    if due_filter is DueFilter.TODAY:
        first, last = today, today
    elif due_filter is DueFilter.TOMORROW:
        first = last = today + timedelta(days=1)
    elif due_filter is DueFilter.WEEK:
        first, last = week_bounds(today)
    else:
        return false()
    return and_(
        Task.due_at >= day_bounds(first, tz_name)[0].astimezone(UTC),
        Task.due_at < day_bounds(last + timedelta(days=1), tz_name)[0].astimezone(UTC),
    )
