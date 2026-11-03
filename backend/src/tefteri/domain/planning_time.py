"""Planned time of a task: the calendar block, the 15-minute grid and the random pick.

The planned time of a task is its due date (constitution Principle VII). The calendar block is
*derived* from it and is never stored in a task application: it starts one hour before the due
time and ends at the due time.
"""

import math
from dataclasses import dataclass
from datetime import UTC, date, datetime, time, timedelta
from random import Random
from zoneinfo import ZoneInfo

from tefteri.domain.timeutil import day_bounds

BLOCK_LENGTH = timedelta(hours=1)
"""Length of the calendar block of a task."""

GRID_MINUTES = 15
"""Planned times snap to marks of this many minutes."""

RANDOM_FIRST_START = time(8, 0)
"""Earliest block start for a random pick."""

RANDOM_LAST_START = time(19, 45)
"""Latest block start for a random pick (spec FR-017: the start lies within 08:00 to 20:00)."""


@dataclass(frozen=True)
class TaskBlock:
    """The calendar block of a task with a timed due date."""

    start: datetime
    end: datetime
    clipped_start: bool
    """True when the block would start on the previous local day and is cut at 00:00."""


def block_for(due_at: datetime, tz_name: str) -> TaskBlock:
    """Return the block that ends at ``due_at``.

    The block belongs to the local day that holds its last second. A due time in the first hour
    of that day gives a block that is cut at 00:00 (``clipped_start``). A due time of exactly
    00:00 gives the last hour of the day before.
    """
    start = due_at - BLOCK_LENGTH
    anchor = (due_at - timedelta(seconds=1)).astimezone(ZoneInfo(tz_name)).date()
    day_start = day_bounds(anchor, tz_name)[0]
    if start < day_start:
        return TaskBlock(day_start, due_at, clipped_start=True)
    return TaskBlock(start, due_at, clipped_start=False)


def snap_to_quarter(value: datetime) -> datetime:
    """Round ``value`` to the nearest 15-minute mark (halves round up)."""
    step = GRID_MINUTES * 60
    snapped = math.floor(value.timestamp() / step + 0.5) * step
    return datetime.fromtimestamp(snapped, tz=value.tzinfo or UTC)


def due_for_block_start(start: datetime) -> datetime:
    """Return the due time of a task whose block starts at ``start`` (snapped to the grid)."""
    return snap_to_quarter(start) + BLOCK_LENGTH


def all_day_due(day: date, tz_name: str) -> datetime:
    """Return the due value for a date-only task: 00:00 local time on ``day``."""
    return day_bounds(day, tz_name)[0]


def pick_random_start(day: date, tz_name: str, rng: Random) -> datetime:
    """Pick a random block start on ``day``, on a 15-minute mark from 08:00 to 19:45 local time.

    The block then ends between 09:00 and 20:45.
    """
    first = RANDOM_FIRST_START.hour * 60 + RANDOM_FIRST_START.minute
    last = RANDOM_LAST_START.hour * 60 + RANDOM_LAST_START.minute
    minutes = rng.choice(range(first, last + 1, GRID_MINUTES))
    return datetime.combine(day, time(minutes // 60, minutes % 60), tzinfo=ZoneInfo(tz_name))
