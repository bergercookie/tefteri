"""Unit tests of the annual review rules (spec 008, M1)."""

from datetime import UTC, date, datetime

from tefteri.domain.annual_review import (
    DeadlineLine,
    LastValue,
    MonthRange,
    SeriesPoint,
    contribution,
    coverage,
    deadline_line,
    distinct_milestones,
    key_result_outcome,
    last_value,
    link_months,
    month_statuses,
    movement,
    peak,
    series,
    theme_hint,
    year_split,
)
from tefteri.domain.enums import (
    DeadlineState,
    KeyResultOutcome,
    MonthStatus,
    ThemeHint,
)
from tefteri.domain.snapshot_view import (
    KeyResultEntry,
    MilestoneRef,
    OutsideEntry,
    SnapshotView,
    ThemeEntry,
    read_snapshot,
)
from tefteri.domain.work_categories import CategoryCounts

TODAY = date(2026, 11, 13)


def entry(
    value: float | None = 10,
    *,
    at: datetime | None = None,
    base: float | None = 5,
    target: float = 100,
) -> KeyResultEntry:
    return KeyResultEntry(
        key_result_id="kr",
        start_value=0,
        base_value=base,
        latest_value=value,
        latest_at=at or datetime(2025, 3, 8, 12, tzinfo=UTC),
        target=target,
        deadline=date(2025, 12, 31),
        retired=False,
        status="active",
        update_source="manual",
    )


def snapshot(
    month: str,
    *,
    kr: KeyResultEntry | None = None,
    categories: CategoryCounts | None = None,
    themes: list[ThemeEntry] | None = None,
    outside: list[OutsideEntry] | None = None,
) -> SnapshotView:
    return SnapshotView(
        month=month,
        version=1,
        taken_at=None,
        schema_version=1,
        themes=themes or [],
        outside_focus=outside or [],
        categories=categories,
        key_results={"kr": kr} if kr is not None else {},
    )


def test_last_value_is_the_last_snapshot_with_a_time_stamp() -> None:
    snapshots = [
        snapshot("2025-01", kr=entry(10, at=datetime(2025, 1, 8, 12, tzinfo=UTC))),
        snapshot("2025-03", kr=entry(40, at=datetime(2025, 3, 8, 12, tzinfo=UTC))),
        snapshot("2025-04", kr=entry(None, at=None)),
    ]
    last = last_value(snapshots, "kr")
    assert last == LastValue(40, "2025-03", datetime(2025, 3, 8, 12, tzinfo=UTC))


def test_the_start_value_is_never_a_last_value() -> None:
    assert last_value([snapshot("2025-01", kr=entry(None, at=None))], "kr") is None


def test_outcome_for_past_year() -> None:
    assert (
        key_result_outcome(
            year_state="past",
            key_result_status="active",
            goal_status="active",
            start_value=0,
            target=100,
            last=LastValue(100, "2025-10", datetime(2025, 10, 1, tzinfo=UTC)),
        )
        is KeyResultOutcome.HIT
    )
    assert (
        key_result_outcome(
            year_state="past",
            key_result_status="active",
            goal_status="active",
            start_value=0,
            target=100,
            last=LastValue(99, "2025-10", datetime(2025, 10, 1, tzinfo=UTC)),
        )
        is KeyResultOutcome.MISSED
    )


def test_outcome_for_a_lower_target_is_hit_at_or_below() -> None:
    assert (
        key_result_outcome(
            year_state="past",
            key_result_status="active",
            goal_status="active",
            start_value=100,
            target=20,
            last=LastValue(20, "2025-10", datetime(2025, 10, 1, tzinfo=UTC)),
        )
        is KeyResultOutcome.HIT
    )


def test_no_value_retired_and_in_progress() -> None:
    common = {
        "year_state": "past",
        "key_result_status": "active",
        "goal_status": "active",
        "start_value": 0,
        "target": 100,
        "last": None,
    }
    assert key_result_outcome(**common) is KeyResultOutcome.NO_VALUE
    assert (
        key_result_outcome(**{**common, "key_result_status": "retired"})
        is KeyResultOutcome.RETIRED
    )
    assert (
        key_result_outcome(**{**common, "goal_status": "retired"})
        is KeyResultOutcome.RETIRED
    )
    assert (
        key_result_outcome(
            **{
                **common,
                "year_state": "current",
                "last": LastValue(10, "2026-01", datetime.now(UTC)),
            }
        )
        is KeyResultOutcome.IN_PROGRESS
    )


def test_deadline_line() -> None:
    snapshots = [
        snapshot("2025-03", kr=entry(60, at=datetime(2025, 3, 8, 12, tzinfo=UTC))),
        snapshot("2025-09", kr=entry(120, at=datetime(2025, 9, 8, 12, tzinfo=UTC))),
        snapshot("2025-12", kr=entry(110, at=datetime(2025, 12, 8, 12, tzinfo=UTC))),
    ]
    line = deadline_line(
        snapshots,
        "kr",
        start_value=0,
        target=100,
        deadline=date(2025, 10, 31),
        year=2025,
        today=TODAY,
        tz=UTC,
    )
    assert line == DeadlineLine(DeadlineState.REACHED, 120, "2025-09")

    assert (
        deadline_line(
            snapshots,
            "kr",
            start_value=0,
            target=100,
            deadline=date(2025, 2, 28),
            year=2025,
            today=TODAY,
            tz=UTC,
        ).state
        is DeadlineState.NO_VALUE
    )
    assert (
        deadline_line(
            snapshots,
            "kr",
            start_value=0,
            target=100,
            deadline=date(2025, 12, 31),
            year=2025,
            today=TODAY,
            tz=UTC,
        ).state
        is DeadlineState.REACHED
    )


def test_deadline_after_the_year_end_is_open() -> None:
    assert (
        deadline_line(
            [],
            "kr",
            start_value=0,
            target=100,
            deadline=date(2026, 3, 1),
            year=2025,
            today=TODAY,
            tz=UTC,
        ).state
        is DeadlineState.OPEN
    )


def test_series_has_twelve_points_and_keeps_gaps() -> None:
    snapshots = [
        snapshot("2025-01", kr=entry(10)),
        snapshot("2025-03", kr=entry(None, at=None)),
    ]
    points = series(snapshots, "kr", year=2025, today=TODAY)
    assert len(points) == 12
    assert points[0] == SeriesPoint("2025-01", MonthStatus.STORED, 10)
    assert points[1].value is None
    assert points[2].not_stored is True
    assert points[2].status is MonthStatus.STORED
    assert all(point.status is MonthStatus.MISSING for point in points[3:])


def test_peak_keeps_the_best_value_and_hides_it_at_the_end() -> None:
    points = series(
        [
            snapshot("2025-01", kr=entry(10)),
            snapshot("2025-02", kr=entry(50)),
            snapshot("2025-03", kr=entry(30)),
        ],
        "kr",
        year=2025,
        today=TODAY,
    )
    found = peak(points, 0, 100)
    assert found is not None and (found.value, found.month) == (50, "2025-02")
    assert peak(points[:1], 0, 100) is None


def test_month_statuses_and_coverage() -> None:
    statuses = month_statuses(2025, ["2025-01", "2025-02"], TODAY)
    assert statuses[0] is MonthStatus.STORED
    assert statuses[1] is MonthStatus.STORED
    assert all(status is MonthStatus.MISSING for status in statuses[2:])
    assert coverage(statuses, year=2025, today=TODAY).expected == 12

    current = month_statuses(2026, ["2026-01"], TODAY)
    assert current[0] is MonthStatus.STORED
    assert current[1] is MonthStatus.MISSING
    assert current[10] is MonthStatus.OPEN
    assert current[11] is MonthStatus.FUTURE
    current_coverage = coverage(current, year=2026, today=TODAY)
    assert current_coverage.expected == 11
    assert current_coverage.stored == 1


def test_link_months_marks_a_partial_range() -> None:
    assert link_months(date(2025, 3, 15), date(2025, 7, 2), 2025) == [
        "2025-03",
        "2025-04",
        "2025-05",
        "2025-06",
        "2025-07",
    ]
    assert link_months(date(2024, 12, 1), None, 2025)[0] == "2025-01"


def test_movement_sign_and_hint() -> None:
    move = movement(
        start_value=0, target=100, first_base=10, last_value=20, months=3, complete=True
    )
    assert move is not None and move.fraction == 0.1
    away = movement(
        start_value=0, target=100, first_base=10, last_value=5, months=3, complete=True
    )
    assert away is not None and away.fraction < 0
    assert (
        theme_hint(shipped=3, target_sum=3, move=move, months_with_target=3)
        is ThemeHint.MUCH_SHIPPED_LITTLE_MOVEMENT
    )
    quarter = movement(
        start_value=0, target=100, first_base=10, last_value=35, months=3, complete=True
    )
    assert (
        theme_hint(shipped=0, target_sum=3, move=quarter, months_with_target=3)
        is ThemeHint.MOVEMENT_NOT_FROM_THEME
    )
    assert (
        theme_hint(shipped=3, target_sum=3, move=quarter, months_with_target=3) is None
    )
    assert theme_hint(shipped=3, target_sum=None, move=move, months_with_target=0) is None


def test_contribution_counts_only_milestones_inside_the_range() -> None:
    theme = ThemeEntry(
        project_id="p",
        name="Open source",
        target=3,
        done=2,
        status="in_focus",
        milestones=[
            MilestoneRef("m1", "before", date(2025, 2, 1)),
            MilestoneRef("m2", "inside", date(2025, 4, 1)),
        ],
    )
    snapshots = [
        snapshot("2025-02", kr=entry(10, base=10), themes=[theme]),
        snapshot("2025-04", kr=entry(20, base=15), themes=[theme]),
        snapshot(
            "2025-05",
            kr=entry(25, base=20),
            outside=[
                OutsideEntry("m3", "outside", date(2025, 5, 1), "p", "Open source"),
            ],
        ),
    ]
    ranges = [
        MonthRange(date(2025, 4, 1), date(2025, 5, 31), ["2025-04", "2025-05"]),
    ]
    found = contribution(
        project_id="p",
        name="Open source",
        ranges=ranges,
        snapshots=snapshots,
        key_result_id="kr",
        start_value=0,
        target=100,
    )
    assert found.shipped == 1
    assert found.shipped_outside_focus == 1
    assert found.target_sum == 3
    assert found.move is not None


def test_distinct_milestones_over_the_year() -> None:
    theme = ThemeEntry(
        project_id="p",
        name="Open source",
        target=None,
        done=1,
        status="in_focus",
        milestones=[MilestoneRef("m1", "one", date(2025, 1, 1))],
    )
    snapshots = [
        snapshot("2025-01", themes=[theme]),
        snapshot("2025-02", themes=[theme]),
    ]
    assert distinct_milestones(snapshots) == 1


def test_year_split_sums_stored_counts_and_hidden_stays_apart() -> None:
    snapshots = [
        snapshot("2025-01", categories=CategoryCounts(10, 5, 5, 2)),
        snapshot("2025-02", categories=CategoryCounts(20, 5, 5, 1)),
        snapshot("2025-03", categories=None),
    ]
    split = year_split(snapshots, year=2025, today=TODAY)
    assert split.months_covered == 2
    assert split.total == 50
    assert split.hidden == 3
    assert split.counts.total == 50
    assert sum(
        (
            split.percentages.goal_aligned,
            split.percentages.maintenance,
            split.percentages.off_plan,
        )
    ) == 100
    assert split.months[2].not_stored is True


def test_read_snapshot_is_tolerant() -> None:
    full = read_snapshot(
        {
            "schema_version": 1,
            "month": "2025-01-01",
            "taken_at": "2025-02-01T10:00:00Z",
            "themes": [
                {
                    "project_id": "p",
                    "name": "Theme",
                    "target": 2,
                    "done": 1,
                    "status": "in_focus",
                    "milestones": [
                        {"milestone_id": "m", "name": "M", "done_on": "2025-01-03"}
                    ],
                    "key_result_ids": ["kr"],
                }
            ],
            "outside_focus": [
                {
                    "milestone_id": "o",
                    "name": "Outside",
                    "done_on": "2025-01-04",
                    "theme_project_id": "p",
                    "theme_name": "Theme",
                }
            ],
            "categories": {
                "goal_aligned": 1,
                "maintenance": 2,
                "off_plan": 3,
                "hidden": 4,
            },
            "key_results": [
                {
                    "key_result_id": "kr",
                    "start_value": 0,
                    "base_value": 1,
                    "latest_value": 2,
                    "latest_at": "2025-01-03T12:00:00Z",
                    "target": 10,
                    "deadline": "2025-12-31",
                    "retired": False,
                    "status": "active",
                    "update_source": "manual",
                }
            ],
        }
    )
    assert full.month == "2025-01-01"
    assert full.themes[0].milestones[0].done_on == date(2025, 1, 3)
    assert full.categories == CategoryCounts(1, 2, 3, 4)
    assert full.key_results["kr"].latest_value == 2

    old = read_snapshot({"month": "2025-01-01", "schema_version": 99, "extra": True})
    assert old.themes == [] and old.categories is None and old.key_results == {}

    malformed = read_snapshot(
        {
            "categories": {"goal_aligned": "many", "maintenance": 1, "off_plan": 1, "hidden": 1},
            "key_results": [{"key_result_id": "kr", "latest_value": "high"}],
        }
    )
    assert malformed.categories is None
    assert malformed.key_results["kr"].latest_value is None
