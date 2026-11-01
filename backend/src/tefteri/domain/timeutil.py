"""Time helpers: a user's local day as a UTC range (DST aware), overlap tests, all-day handling."""

from datetime import date, datetime, time, timedelta
from zoneinfo import ZoneInfo


def day_bounds(day: date, tz_name: str) -> tuple[datetime, datetime]:
    """Return the ``[start, end)`` of the local calendar day in ``tz_name``, as aware datetimes.

    The range is 23 or 25 hours long on a daylight-saving change day.
    """
    tz = ZoneInfo(tz_name)
    start = datetime.combine(day, time.min, tzinfo=tz)
    end = datetime.combine(day + timedelta(days=1), time.min, tzinfo=tz)
    return start, end


def overlaps(a_start: datetime, a_end: datetime, b_start: datetime, b_end: datetime) -> bool:
    """Return whether two time ranges overlap (touching ranges do not)."""
    return a_start < b_end and b_start < a_end


def all_day_range(start: date, end_exclusive: date, tz_name: str) -> tuple[datetime, datetime]:
    """Return the aware range of an all-day entry covering local days ``[start, end_exclusive)``."""
    return day_bounds(start, tz_name)[0], day_bounds(end_exclusive, tz_name)[0]
