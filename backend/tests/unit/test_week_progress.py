"""The progress of a committed week: a port of the cases of ``week_progress_test.dart``."""

from datetime import date

import pytest

from tefteri.domain.week_progress import CommittedTask, week_progress

MONDAY = date(2026, 11, 2)


def task(doneOn: str | None = None, done: bool = False) -> CommittedTask:  # noqa: N803
    return CommittedTask(done or doneOn is not None, date.fromisoformat(doneOn) if doneOn else None)


# 10 tasks: 2 done on Monday, 1 on Tuesday, 1 on Wednesday, 6 open.
TASKS = [
    task("2026-11-02"),
    task("2026-11-02"),
    task("2026-11-03"),
    task("2026-11-04"),
    *[task() for _ in range(6)],
]


def test_counts_done_per_day_what_is_left_and_the_cadence() -> None:
    p = week_progress(TASKS, MONDAY, date(2026, 11, 4))
    assert p.committed == 10
    assert p.done_by_day == (2, 1, 1, 0, 0, 0, 0)
    assert p.done_in_week == 4
    assert p.done == 4
    assert p.left == 6
    assert p.days_elapsed == 3
    assert p.cadence == pytest.approx(4 / 3)
    assert p.days_left == 5  # Wednesday to Sunday, today included
    assert p.needed_per_day == pytest.approx(6 / 5)
    assert p.on_track is True
    assert p.fraction == pytest.approx(0.4)


def test_burns_down_from_the_scope_and_stops_at_today() -> None:
    p = week_progress(TASKS, MONDAY, date(2026, 11, 4))
    assert p.remaining_by_day == (8, 7, 6, None, None, None, None)
    assert p.ideal_by_day[0] == pytest.approx(10 * 6 / 7)
    assert p.ideal_by_day[-1] == 0
    assert len(p.ideal_by_day) == 7
    assert p.scope == 10


def test_is_behind_when_the_cadence_is_below_what_is_needed() -> None:
    p = week_progress(TASKS, MONDAY, date(2026, 11, 8))
    assert p.days_left == 1  # only Sunday
    assert p.needed_per_day == 6
    assert p.cadence == pytest.approx(4 / 7)
    assert p.on_track is False


def test_tasks_done_before_the_week_or_without_a_day_are_not_burned() -> None:
    p = week_progress(
        [task("2026-10-30"), task(done=True), task("2026-11-03"), task()],
        MONDAY,
        date(2026, 11, 3),
    )
    assert p.done == 3
    assert p.done_in_week == 1
    assert p.done_before == 1 and p.done_undated == 1
    assert p.scope == 2
    assert p.remaining_by_day[:2] == (2, 1)


def test_a_task_done_after_the_week_counts_as_done_but_not_in_the_week() -> None:
    p = week_progress([task("2026-11-12"), task()], MONDAY, date(2026, 11, 20))
    assert p.done_after == 1 and p.done_in_week == 0 and p.done == 1 and p.left == 1


def test_a_week_that_has_not_begun_has_no_cadence_and_a_past_week_has_no_days_left() -> None:
    future = week_progress(TASKS, MONDAY, date(2026, 10, 28))
    assert future.cadence is None
    assert future.days_left == 7 and future.days_elapsed == 0
    assert all(v is None for v in future.remaining_by_day)
    assert future.on_track is False
    past = week_progress(TASKS, MONDAY, date(2026, 11, 20))
    assert past.days_left == 0
    assert past.needed_per_day is None
    assert sum(v is not None for v in past.remaining_by_day) == 7


def test_a_plan_with_no_task_has_fraction_one_and_is_on_track() -> None:
    p = week_progress([], MONDAY, date(2026, 11, 4))
    assert p.fraction == 1 and p.committed == 0 and p.left == 0
    assert p.needed_per_day is None and p.on_track is True


def test_the_last_day_of_the_week_is_day_seven() -> None:
    p = week_progress(TASKS, MONDAY, date(2026, 11, 8))
    assert p.days_elapsed == 7
    p = week_progress(TASKS, MONDAY, date(2026, 11, 9))
    assert p.days_elapsed == 7 and p.days_left == 0
