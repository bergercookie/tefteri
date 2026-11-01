"""Goal hierarchy rules and computed progress."""

import uuid
from datetime import date

from tefteri.db.models.goal import Goal
from tefteri.db.models.task import Task
from tefteri.domain.periods import (
    PeriodType,
    child_fits,
    is_aligned,
    period_end,
    period_start,
)
from tefteri.services.goals import compute_progress


def goal(parent: Goal | None = None, status: str = "active") -> Goal:
    return Goal(
        id=uuid.uuid4(),
        parent_id=parent.id if parent else None,
        period_type="week",
        period_start=date(2026, 11, 2),
        title="g",
        status=status,
    )


def task(g: Goal, done: bool, state: str = "synced") -> Task:
    return Task(id=uuid.uuid4(), goal_id=g.id, status="done" if done else "open", sync_state=state)


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


def test_progress_is_computed_from_tasks_and_children() -> None:
    parent = goal()
    child = goal(parent)
    tasks = [task(child, True), task(child, False), task(parent, True)]
    result = compute_progress([parent, child], tasks)
    assert result[child.id] == 0.5
    assert result[parent.id] == (0.5 + 1.0) / 2  # child goal + one done task


def test_empty_goal_progress_follows_status_and_dropped_do_not_count() -> None:
    open_goal = goal()
    assert compute_progress([open_goal], [])[open_goal.id] == 0.0
    done = goal(status="done")
    assert compute_progress([done], [])[done.id] == 1.0
    parent = goal()
    dropped = goal(parent, status="dropped")
    live = goal(parent)
    result = compute_progress([parent, dropped, live], [task(live, True)])
    assert result[parent.id] == 1.0  # the dropped goal is ignored


def test_tasks_deleted_in_the_app_do_not_count() -> None:
    g = goal()
    result = compute_progress([g], [task(g, True), task(g, False, state="deleted_remotely")])
    assert result[g.id] == 1.0
