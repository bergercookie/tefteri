"""Pure domain tests for the monthly focus and milestone-counting rules."""

from dataclasses import FrozenInstanceError
from datetime import date, datetime
from zoneinfo import ZoneInfo

import pytest

from tefteri.domain.enums import CountNote, MonthState, TargetMarker
from tefteri.domain.monthly import (
    DoneMilestone,
    EntryWindow,
    InvalidTarget,
    OutsideItem,
    ThemeResult,
    classify_done,
    count_note,
    local_day,
    month_bounds,
    month_state,
    parse_target,
    planning_year_of,
    result_marker,
)


@pytest.mark.parametrize(
    ("raw", "expected"),
    [(None, None), ("", None), ("  ", None), (0, 0), ("0", 0), (3, 3)],
)
def test_parse_target_accepts_empty_or_nonnegative_whole_values(
    raw: object, expected: int | None
) -> None:
    assert parse_target(raw) == expected


@pytest.mark.parametrize("raw", [-1, 3.5, 3.0, "abc", True, float("nan")])
def test_parse_target_rejects_invalid_values(raw: object) -> None:
    with pytest.raises(InvalidTarget):
        parse_target(raw)


@pytest.mark.parametrize(
    ("target", "done", "marker"),
    [
        (None, 0, TargetMarker.NO_TARGET),
        (0, 0, TargetMarker.MET),
        (3, 2, TargetMarker.MISSED),
        (3, 3, TargetMarker.MET),
        (3, 4, TargetMarker.BEATEN),
        (None, 5, TargetMarker.NO_TARGET),
    ],
)
def test_result_marker_distinguishes_no_target_from_zero(
    target: int | None, done: int, marker: TargetMarker
) -> None:
    assert result_marker(target, done) is marker


@pytest.mark.parametrize(
    ("count", "note"),
    [
        (0, CountNote.EMPTY),
        (1, CountNote.BELOW),
        (2, CountNote.BELOW),
        (3, None),
        (4, None),
        (5, None),
        (6, CountNote.ABOVE),
    ],
)
def test_count_note_is_guidance_only(count: int, note: CountNote | None) -> None:
    assert count_note(count) is note


def test_month_bounds_state_and_planning_year() -> None:
    assert month_bounds(date(2030, 2, 1)) == (date(2030, 2, 1), date(2030, 3, 1))
    today = date(2030, 2, 15)
    assert month_state(date(2030, 1, 1), today) is MonthState.PAST
    assert month_state(date(2030, 2, 1), today) is MonthState.CURRENT
    assert month_state(date(2030, 3, 1), today) is MonthState.FUTURE
    assert planning_year_of(date(2030, 12, 1)) == 2030
    assert planning_year_of(date(2031, 1, 1)) == 2031


def test_month_dates_are_local_dates_in_the_users_time_zone() -> None:
    # 00:30 in UTC+2 is already the first local day of March.
    instant = datetime(2030, 3, 1, 0, 30, tzinfo=ZoneInfo("Etc/GMT-2"))
    day_before = local_day(instant, ZoneInfo("Etc/GMT+2"))
    assert day_before == date(2030, 2, 28)
    local = local_day(instant, ZoneInfo("Etc/GMT-2"))
    assert local == date(2030, 3, 1)
    assert month_state(local, date(2030, 3, 1)) is MonthState.CURRENT


def test_classify_done_counts_at_the_theme_and_within_the_entry_window() -> None:
    entries = (
        EntryWindow("theme-a", "Stored A", 2, date(2030, 3, 1)),
        EntryWindow("theme-b", "Stored B", None, date(2030, 3, 1)),
    )
    done = (
        DoneMilestone("m1", "Ship one", date(2030, 3, 8), "theme-a"),
        DoneMilestone("m2", "Ship two", date(2030, 3, 31), "theme-a"),
        DoneMilestone("m3", "Moved from A to B", date(2030, 3, 12), "theme-b"),
    )
    themes, outside = classify_done(date(2030, 3, 1), entries, done)
    assert themes == (
        ThemeResult(
            project_id="theme-a",
            name="Stored A",
            target=2,
            counts_from=date(2030, 3, 1),
            left_on=None,
            milestones=(done[0], done[1]),
            earlier_not_counted=(),
            marker=TargetMarker.MET,
        ),
        ThemeResult(
            project_id="theme-b",
            name="Stored B",
            target=None,
            counts_from=date(2030, 3, 1),
            left_on=None,
            milestones=(done[2],),
            earlier_not_counted=(),
            marker=TargetMarker.NO_TARGET,
        ),
    )
    assert outside == ()


def test_classify_done_separates_earlier_outside_and_other_month_items() -> None:
    entries = (EntryWindow("theme-a", "A", None, date(2030, 3, 5), date(2030, 3, 20)),)
    done = (
        DoneMilestone("early", "Before count window", date(2030, 3, 2), "theme-a"),
        DoneMilestone("after", "After leaving", date(2030, 3, 21), "theme-a"),
        DoneMilestone("not-focused", "Other theme", date(2030, 3, 10), "theme-c"),
        DoneMilestone("no-theme", "No theme", date(2030, 3, 10), None),
        DoneMilestone("other-month", "Outside month", date(2030, 4, 1), "theme-a"),
    )
    themes, outside = classify_done(date(2030, 3, 1), entries, done)
    (theme,) = themes
    assert theme.milestones == ()
    assert theme.earlier_not_counted == (done[0],)
    assert outside == (
        OutsideItem(done[1], "theme-a", "A"),
        OutsideItem(done[2], "theme-c", None),
        OutsideItem(done[3], None, None),
    )


def test_month_filter_uses_local_done_dates_and_frozen_input_values() -> None:
    milestone = DoneMilestone("m", "Finished", date(2030, 3, 31), "theme-a")
    entry = EntryWindow("theme-a", "A", 0, date(2030, 3, 1))
    result = classify_done(date(2030, 3, 1), (entry,), (milestone,))[0][0]
    assert result.marker is TargetMarker.BEATEN
    with pytest.raises(FrozenInstanceError):
        milestone.name = "Changed"  # type: ignore[misc]
