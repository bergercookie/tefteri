"""Planning periods (year, month, week) and the rules for nesting them."""

from datetime import date, timedelta
from enum import StrEnum


class PeriodType(StrEnum):
    """Length of a planning period."""

    YEAR = "year"
    MONTH = "month"
    WEEK = "week"


_RANK = {PeriodType.YEAR: 3, PeriodType.MONTH: 2, PeriodType.WEEK: 1}


def is_aligned(kind: PeriodType, start: date) -> bool:
    """Return whether ``start`` is the first day of a period: Jan 1, the 1st, or a Monday."""
    if kind is PeriodType.YEAR:
        return start.month == 1 and start.day == 1
    if kind is PeriodType.MONTH:
        return start.day == 1
    return start.weekday() == 0


def period_start(kind: PeriodType, day: date) -> date:
    """Return the start of the period of type ``kind`` that contains ``day``."""
    if kind is PeriodType.YEAR:
        return date(day.year, 1, 1)
    if kind is PeriodType.MONTH:
        return date(day.year, day.month, 1)
    return day - timedelta(days=day.weekday())


def period_end(kind: PeriodType, start: date) -> date:
    """Return the exclusive end of the period starting at ``start``."""
    if kind is PeriodType.YEAR:
        return date(start.year + 1, 1, 1)
    if kind is PeriodType.MONTH:
        return date(start.year + (start.month // 12), start.month % 12 + 1, 1)
    return start + timedelta(days=7)


def child_fits(
    parent_kind: PeriodType, parent_start: date, child_kind: PeriodType, child_start: date
) -> bool:
    """Return whether a child period lies inside its parent.

    The parent must be longer than the child. A week belongs to the month that contains its
    Monday (and to the year of that Monday).
    """
    if _RANK[parent_kind] <= _RANK[child_kind]:
        return False
    end = period_end(parent_kind, parent_start)
    return parent_start <= child_start < end
