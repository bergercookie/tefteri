"""Goal period rules."""

from datetime import date

from tefteri.domain.periods import (
    PeriodType,
    child_fits,
    is_aligned,
    period_end,
    period_start,
)


def test_period_alignment() -> None:
    assert is_aligned(PeriodType.YEAR, date(2026, 1, 1))
    assert not is_aligned(PeriodType.YEAR, date(2026, 2, 1))
    assert is_aligned(PeriodType.MONTH, date(2026, 11, 1))
    assert not is_aligned(PeriodType.MONTH, date(2026, 11, 2))
    assert is_aligned(PeriodType.WEEK, date(2026, 11, 2))  # a Monday
    assert not is_aligned(PeriodType.WEEK, date(2026, 11, 3))


def test_period_start_and_end() -> None:
    assert period_start(PeriodType.WEEK, date(2026, 11, 8)) == date(2026, 11, 2)
    assert period_start(PeriodType.MONTH, date(2026, 11, 20)) == date(2026, 11, 1)
    assert period_end(PeriodType.MONTH, date(2026, 12, 1)) == date(2027, 1, 1)
    assert period_end(PeriodType.YEAR, date(2026, 1, 1)) == date(2027, 1, 1)
    assert period_end(PeriodType.WEEK, date(2026, 11, 2)) == date(2026, 11, 9)


def test_child_period_must_lie_inside_parent() -> None:
    year, month, week = PeriodType.YEAR, PeriodType.MONTH, PeriodType.WEEK
    assert child_fits(year, date(2026, 1, 1), month, date(2026, 11, 1))
    assert not child_fits(year, date(2026, 1, 1), month, date(2027, 1, 1))
    assert child_fits(month, date(2026, 11, 1), week, date(2026, 11, 2))
    # a week belongs to the month that contains its Monday
    assert child_fits(month, date(2026, 10, 1), week, date(2026, 10, 26))
    assert not child_fits(month, date(2026, 11, 1), week, date(2026, 10, 26))


def test_parent_must_be_longer_than_child() -> None:
    assert not child_fits(PeriodType.MONTH, date(2026, 11, 1), PeriodType.MONTH, date(2026, 11, 1))
    assert not child_fits(PeriodType.WEEK, date(2026, 11, 2), PeriodType.YEAR, date(2026, 1, 1))
