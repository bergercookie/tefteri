"""The planned time of a task: block derivation, the 15-minute grid and the random pick."""

from datetime import UTC, date, datetime, timedelta
from random import Random
from zoneinfo import ZoneInfo

import pytest

from tefteri.domain.planning_time import (
    all_day_due,
    block_for,
    due_for_block_start,
    pick_random_start,
    snap_to_quarter,
)

ATHENS = "Europe/Athens"


def test_block_is_the_hour_before_the_due_time() -> None:
    due = datetime(2026, 11, 2, 10, tzinfo=UTC)
    block = block_for(due, "UTC")
    assert (block.start, block.end, block.clipped_start) == (due - timedelta(hours=1), due, False)


def test_due_in_the_first_hour_is_clipped_at_midnight() -> None:
    due = datetime(2026, 11, 2, 0, 30, tzinfo=UTC)
    block = block_for(due, "UTC")
    assert block.start == datetime(2026, 11, 2, tzinfo=UTC)
    assert block.end == due and block.clipped_start


def test_due_at_exactly_midnight_is_the_last_hour_of_the_day_before() -> None:
    due = datetime(2026, 11, 3, tzinfo=UTC)
    block = block_for(due, "UTC")
    assert block.start == datetime(2026, 11, 2, 23, tzinfo=UTC)
    assert not block.clipped_start


def test_clipping_uses_the_users_local_day() -> None:
    due = datetime(2026, 11, 2, 22, 30, tzinfo=UTC)  # 00:30 on 3 November in Athens (UTC+2)
    block = block_for(due, ATHENS)
    assert block.clipped_start
    assert block.start == datetime(2026, 11, 3, tzinfo=ZoneInfo(ATHENS))


@pytest.mark.parametrize(
    ("minute", "second", "expected_minute"),
    [(0, 0, 0), (7, 29, 0), (7, 31, 15), (8, 0, 15), (22, 30, 30), (52, 29, 45)],
)
def test_snap_to_quarter(minute: int, second: int, expected_minute: int) -> None:
    value = datetime(2026, 11, 2, 9, minute, second, tzinfo=UTC)
    assert snap_to_quarter(value) == datetime(2026, 11, 2, 9, expected_minute, tzinfo=UTC)


def test_snap_rolls_over_the_hour_and_keeps_the_zone() -> None:
    value = datetime(2026, 11, 2, 9, 53, tzinfo=ZoneInfo(ATHENS))
    snapped = snap_to_quarter(value)
    assert snapped == datetime(2026, 11, 2, 10, tzinfo=ZoneInfo(ATHENS))
    assert snapped.tzinfo == value.tzinfo


def test_due_is_one_hour_after_the_snapped_block_start() -> None:
    start = datetime(2026, 11, 2, 9, 7, tzinfo=UTC)
    assert due_for_block_start(start) == datetime(2026, 11, 2, 10, tzinfo=UTC)


def test_all_day_due_is_local_midnight() -> None:
    assert all_day_due(date(2026, 11, 4), ATHENS) == datetime(2026, 11, 3, 22, tzinfo=UTC)


def test_random_start_is_a_quarter_mark_inside_the_window() -> None:
    rng = Random(42)  # noqa: S311
    seen = set()
    for _ in range(500):
        start = pick_random_start(date(2026, 11, 4), ATHENS, rng)
        local = start.astimezone(ZoneInfo(ATHENS))
        assert local.date() == date(2026, 11, 4)
        assert local.minute % 15 == 0 and local.second == 0
        assert (8, 0) <= (local.hour, local.minute) <= (19, 45)  # FR-017: start in 08:00-20:00
        seen.add((local.hour, local.minute))
    assert (8, 0) in seen and (19, 45) in seen  # both ends of the window are reachable


def test_random_start_is_exact_with_a_fixed_seed() -> None:
    first = pick_random_start(date(2026, 11, 4), "UTC", Random(7))  # noqa: S311
    again = pick_random_start(date(2026, 11, 4), "UTC", Random(7))  # noqa: S311
    assert first == again


def test_random_start_on_a_daylight_saving_day_keeps_local_times() -> None:
    day = date(2026, 3, 29)  # clocks go forward in Athens that night
    start = pick_random_start(day, ATHENS, Random(1))  # noqa: S311
    local = start.astimezone(ZoneInfo(ATHENS))
    assert local.date() == day and 8 <= local.hour <= 19
