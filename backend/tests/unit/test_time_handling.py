"""Time zones, DST, all-day entries and overlap rules."""

from datetime import UTC, date, datetime, timedelta

from tefteri.domain.timeutil import all_day_range, day_bounds, overlaps


def test_day_bounds_use_the_users_zone() -> None:
    start, end = day_bounds(date(2026, 11, 2), "Europe/London")
    assert start == datetime(2026, 11, 2, 0, 0, tzinfo=UTC)
    start_ny, _ = day_bounds(date(2026, 11, 2), "America/New_York")
    assert start_ny.astimezone(UTC) == datetime(2026, 11, 2, 5, tzinfo=UTC)
    assert end - start == timedelta(hours=24)


def test_dst_days_are_23_and_25_hours_long() -> None:
    spring = day_bounds(date(2026, 3, 29), "Europe/London")
    autumn = day_bounds(date(2026, 10, 25), "Europe/London")
    assert spring[1].astimezone(UTC) - spring[0].astimezone(UTC) == timedelta(hours=23)
    assert autumn[1].astimezone(UTC) - autumn[0].astimezone(UTC) == timedelta(hours=25)


def test_overlap_rules() -> None:
    nine = datetime(2026, 11, 2, 9, tzinfo=UTC)
    ten = nine + timedelta(hours=1)
    assert overlaps(nine, ten, nine + timedelta(minutes=30), ten + timedelta(hours=1))
    assert not overlaps(nine, ten, ten, ten + timedelta(hours=1))  # touching
    assert overlaps(nine, ten, nine, ten)


def test_all_day_entry_covers_the_local_days_only() -> None:
    start, end = all_day_range(date(2026, 11, 2), date(2026, 11, 3), "Asia/Tokyo")
    day_before = day_bounds(date(2026, 11, 1), "Asia/Tokyo")
    next_day = day_bounds(date(2026, 11, 3), "Asia/Tokyo")
    assert overlaps(start, end, *day_bounds(date(2026, 11, 2), "Asia/Tokyo"))
    assert not overlaps(start, end, *day_before)
    assert not overlaps(start, end, *next_day)


def test_recurring_instances_are_separate_occurrences() -> None:
    # Adapters expand recurring events into single occurrences, so each is one range.
    weekly = [datetime(2026, 11, 2, 9, tzinfo=UTC) + timedelta(weeks=i) for i in range(3)]
    day = day_bounds(date(2026, 11, 9), "UTC")
    hits = [w for w in weekly if overlaps(w, w + timedelta(minutes=30), *day)]
    assert hits == [weekly[1]]
