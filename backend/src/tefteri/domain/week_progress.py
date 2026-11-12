"""How far the committed plan of one week has come (spec 005, research R-12).

A port of the client class ``week_progress.dart``: plain arithmetic over the tasks a week was
committed to. The numbers are the same as the client had; the server now owns them.
"""

from collections.abc import Iterable
from dataclasses import dataclass
from datetime import date, timedelta


@dataclass(frozen=True)
class CommittedTask:
    """A task the week was committed to."""

    done: bool
    completed_day: date | None = None
    """The local day it was completed, or ``None`` when open or when the day is not known."""


@dataclass(frozen=True)
class WeekProgress:
    """Progress of the tasks a week was committed to, as of one day."""

    monday: date
    committed: int
    done_by_day: tuple[int, ...]
    """Tasks completed on each day of the week, Monday first."""
    done_before: int
    """Committed tasks that were already done before the week began."""
    done_undated: int
    """Done tasks whose completion day is not known."""
    done_after: int
    """Done tasks completed after the week ended."""
    days_elapsed: int
    """Days of the week that have begun, counting today: 0 to 7."""
    days_left: int
    """Days still to come, counting today; 0 once the week is over."""

    @property
    def done_in_week(self) -> int:
        """Tasks completed during the week."""
        return sum(self.done_by_day)

    @property
    def done(self) -> int:
        """Committed tasks that are done now, whenever they were completed."""
        return self.done_in_week + self.done_before + self.done_undated + self.done_after

    @property
    def left(self) -> int:
        """Committed tasks still open."""
        return self.committed - self.done

    @property
    def fraction(self) -> float:
        """Fraction done, 0 to 1 (1 for a plan without tasks)."""
        return 1.0 if self.committed == 0 else self.done / self.committed

    @property
    def cadence(self) -> float | None:
        """Tasks completed per day so far, or ``None`` before the week has begun."""
        return None if self.days_elapsed == 0 else self.done_in_week / self.days_elapsed

    @property
    def needed_per_day(self) -> float | None:
        """Tasks per day the rest of the week needs, or ``None`` when nothing is left or over."""
        if self.left == 0 or self.days_left == 0:
            return None
        return self.left / self.days_left

    @property
    def on_track(self) -> bool:
        """True when the work needed per day is no more than the cadence."""
        if self.left == 0:
            return True
        cadence, need = self.cadence, self.needed_per_day
        if cadence is None or need is None:
            return False
        return cadence >= need

    @property
    def scope(self) -> int:
        """Tasks to burn at the start of the week."""
        return self.committed - self.done_before - self.done_undated

    @property
    def remaining_by_day(self) -> tuple[int | None, ...]:
        """Open tasks at the end of each day, or ``None`` for days that have not begun."""
        left = self.scope
        out: list[int | None] = []
        for i in range(7):
            if i < self.days_elapsed:
                left -= self.done_by_day[i]
                out.append(left)
            else:
                out.append(None)
        return tuple(out)

    @property
    def ideal_by_day(self) -> tuple[float, ...]:
        """The straight line from the scope to zero at Sunday night, at the end of each day."""
        return tuple(self.scope * (7 - i) / 7 for i in range(1, 8))


def week_progress(tasks: Iterable[CommittedTask], monday: date, today: date) -> WeekProgress:
    """Read the progress of the committed ``tasks`` of the week that starts on ``monday``."""
    end = monday + timedelta(days=7)
    by_day = [0] * 7
    before = undated = after = committed = 0
    for task in tasks:
        committed += 1
        if not task.done:
            continue
        day = task.completed_day
        if day is None:
            undated += 1
        elif day < monday:
            before += 1
        elif day >= end:
            after += 1
        else:
            by_day[(day - monday).days] += 1
    if today < monday:
        elapsed, left = 0, 7
    elif today < end:
        elapsed, left = (today - monday).days + 1, 7 - (today - monday).days
    else:
        elapsed, left = 7, 0
    return WeekProgress(
        monday=monday,
        committed=committed,
        done_by_day=tuple(by_day),
        done_before=before,
        done_undated=undated,
        done_after=after,
        days_elapsed=elapsed,
        days_left=left,
    )
