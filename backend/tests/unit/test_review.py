"""Review computation: planned versus completed and carried-over items."""

import uuid
from datetime import UTC, date, datetime

from tefteri.db.models.goal import Goal
from tefteri.db.models.task import Task
from tefteri.domain.periods import PeriodType
from tefteri.services.reviews import compute_review

NOV = date(2026, 11, 1)


def goal(
    title: str,
    *,
    parent: Goal | None = None,
    period_type: str = "month",
    start: date = NOV,
    status: str = "active",
) -> Goal:
    return Goal(
        id=uuid.uuid4(),
        parent_id=parent.id if parent else None,
        period_type=period_type,
        period_start=start,
        title=title,
        status=status,
    )


def task(
    title: str,
    *,
    g: Goal | None = None,
    done: bool = False,
    due: datetime | None = None,
    state: str = "synced",
) -> Task:
    return Task(
        id=uuid.uuid4(),
        title=title,
        goal_id=g.id if g else None,
        status="done" if done else "open",
        due_at=due,
        scheduled_start=None,
        sync_state=state,
    )


def review(goals: list[Goal], tasks: list[Task], tz: str = "UTC"):  # type: ignore[no-untyped-def]
    return compute_review(PeriodType.MONTH, NOV, goals, tasks, tz)


def test_planned_versus_completed_and_carried_over() -> None:
    run = goal("Run 100 km")
    read = goal("Read 2 books", status="done")
    shoes = task("Buy shoes", g=run, done=True)
    km = task("Run 25 km", g=run)
    result = review([run, read], [shoes, km])
    assert result.planned_count == 4
    assert result.completed_count == 2
    assert set(result.carried_over) == {str(run.id), str(km.id)}
    by_title = {i.title: i for i in result.items}
    assert by_title["Read 2 books"].completed and not by_title["Run 100 km"].completed


def test_goal_with_full_progress_counts_as_completed() -> None:
    run = goal("Run 100 km")
    result = review([run], [task("a", g=run, done=True), task("b", g=run, done=True)])
    assert result.completed_count == result.planned_count == 3
    assert result.carried_over == []


def test_tasks_of_smaller_goals_and_tasks_due_in_the_period_count() -> None:
    month = goal("Month")
    week = goal("Week", parent=month, period_type="week", start=date(2026, 11, 2))
    of_week = task("Of the week", g=week)
    due_inside = task("Due in Nov", due=datetime(2026, 11, 30, 12, tzinfo=UTC), done=True)
    due_after = task("Due in Dec", due=datetime(2026, 12, 1, 12, tzinfo=UTC))
    result = review([month, week], [of_week, due_inside, due_after])
    titles = {i.title for i in result.items}
    assert titles == {"Month", "Of the week", "Due in Nov"}  # the week goal is not a month goal


def test_period_edges_use_the_users_time_zone() -> None:
    # 23:30 UTC on 31 Oct is already 1 Nov in Athens (UTC+2).
    edge = task("Edge", due=datetime(2026, 10, 31, 23, 30, tzinfo=UTC))
    assert review([], [edge], "Europe/Athens").planned_count == 1
    assert review([], [edge], "UTC").planned_count == 0


def test_dropped_goals_and_deleted_tasks_do_not_count() -> None:
    dropped = goal("Dropped", status="dropped")
    run = goal("Run")
    gone = task("Gone", g=run, state="deleted_remotely")
    of_dropped = task("Of dropped", g=dropped)
    result = review([dropped, run], [gone, of_dropped])
    assert [i.title for i in result.items] == ["Run"]


def test_other_periods_are_ignored() -> None:
    october = goal("October", start=date(2026, 10, 1))
    year = goal("Year", period_type="year", start=date(2026, 1, 1))
    assert review([october, year], []).planned_count == 0


def test_empty_period() -> None:
    result = review([], [])
    assert (result.planned_count, result.completed_count, result.items) == (0, 0, [])
