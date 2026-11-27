"""Reminders: tasks, calendar events and the weekly, monthly and annual reviews."""

import uuid
from datetime import UTC, date, datetime, timedelta
from typing import Any

from sqlalchemy import select

from tefteri.db.models.calendar_entry import CalendarEntry
from tefteri.db.models.monthly import MonthlyReview
from tefteri.db.models.review_note import ReviewNote
from tefteri.db.models.task import Task
from tefteri.db.models.user import User
from tefteri.db.models.weekly import WeeklyPlan
from tefteri.domain.entities import Container
from tests.conftest import V1
from tests.integration.conftest import ProjectsEnv

SUNDAY = date(2030, 3, 10)  # a Sunday


def _at(day: date, hour: int, minute: int = 0) -> datetime:
    return datetime(day.year, day.month, day.day, hour, minute, tzinfo=UTC)


async def _get(env: ProjectsEnv, start: datetime, hours: int = 24) -> list[dict[str, Any]]:
    r = await env.api.get(f"{V1}/reminders", params={"from": start.isoformat(), "hours": hours})
    assert r.status_code == 200, r.text
    found: list[dict[str, Any]] = r.json()["reminders"]
    return found


async def _task(env: ProjectsEnv, title: str, due: datetime | None, **extra: Any) -> None:
    async with env.db() as db:
        db.add(
            Task(
                user_id=await env.user_id(),
                connection_id=env.connection_uuid(),
                container_id=None,
                remote_id=title,
                title=title,
                due_at=due,
                **extra,
            )
        )


async def _event(
    env: ProjectsEnv, title: str, start: datetime, uid: str = "", **extra: Any
) -> None:
    async with env.db() as db:
        db.add(
            CalendarEntry(
                user_id=await env.user_id(),
                connection_id=env.connection_uuid(),
                container_id=None,
                remote_id=f"{title}-{uuid.uuid4()}",
                title=title,
                start=start,
                end=start + timedelta(hours=1),
                uid=uid,
                **extra,
            )
        )


async def _connected(env: ProjectsEnv) -> None:
    await env.connect(Container("p2", "Home"))


async def _settings(env: ProjectsEnv, **body: Any) -> dict[str, Any]:
    r = await env.api.patch(f"{V1}/me/settings", json=body)
    assert r.status_code == 200, r.text
    out: dict[str, Any] = r.json()
    return out


async def test_both_reminder_times_are_15_minutes_until_the_user_changes_them(
    env: ProjectsEnv,
) -> None:
    got = (await env.api.get(f"{V1}/me/settings")).json()
    assert got["default_reminder_minutes"] == 15 and got["event_reminder_minutes"] == 15
    changed = await _settings(env, event_reminder_minutes=45)
    assert changed["event_reminder_minutes"] == 45 and changed["default_reminder_minutes"] == 15
    bad = await env.api.patch(f"{V1}/me/settings", json={"event_reminder_minutes": -1})
    assert bad.status_code == 422


async def test_a_task_with_a_due_time_is_reminded_before_it_is_due_without_a_reminder_in_the_app(
    env: ProjectsEnv,
) -> None:
    await _connected(env)
    await _task(env, "Call Sam", _at(SUNDAY, 14, 30))
    found = await _get(env, _at(SUNDAY, 0))
    (reminder,) = [r for r in found if r["kind"] == "task"]
    assert reminder["title"] == "Call Sam"
    assert reminder["fire_at"].startswith("2030-03-10T14:15:00")  # 15 minutes before
    assert reminder["body"] == "Due at 14:30"
    # A phone writes the time in its own zone, from the raw time and the words around it.
    assert reminder["at"].startswith("2030-03-10T14:30:00")
    assert (reminder["verb"], reminder["detail"]) == ("Due", None)
    # The link opens the task itself, not only its day.
    assert reminder["link"].startswith("/?date=2030-03-10&task=")
    assert reminder["link"].removeprefix("/?date=2030-03-10&task=") in reminder["id"]
    await _settings(env, default_reminder_minutes=60)
    (later,) = [r for r in await _get(env, _at(SUNDAY, 0)) if r["kind"] == "task"]
    assert later["fire_at"].startswith("2030-03-10T13:30:00")
    assert later["id"] == reminder["id"]  # the same task keeps its id


async def test_a_task_planned_for_a_time_is_reminded_before_its_block_starts(
    env: ProjectsEnv,
) -> None:
    await _connected(env)
    # The planner gives a task a block. The task is due when the block ends.
    await _task(
        env,
        "Planned",
        _at(SUNDAY, 15),
        scheduled_start=_at(SUNDAY, 14),
        scheduled_end=_at(SUNDAY, 15),
    )
    (reminder,) = [r for r in await _get(env, _at(SUNDAY, 0)) if r["kind"] == "task"]
    assert reminder["fire_at"].startswith("2030-03-10T13:45:00")  # not 14:45
    assert reminder["body"] == "Starts at 14:00"


async def test_a_done_task_a_day_only_task_and_a_task_that_is_gone_get_no_reminder(
    env: ProjectsEnv,
) -> None:
    await _connected(env)
    due = _at(SUNDAY, 14, 30)
    await _task(env, "Done", due, status="done")
    await _task(env, "Only a day", due, all_day=True)
    await _task(env, "Gone", due, sync_state="deleted_remotely")
    await _task(env, "No date", None)
    await _task(env, "Too late", _at(SUNDAY + timedelta(days=5), 9))
    assert [r for r in await _get(env, _at(SUNDAY, 0)) if r["kind"] == "task"] == []


async def test_an_event_is_reminded_before_it_starts_and_the_time_can_change(
    env: ProjectsEnv,
) -> None:
    await _connected(env)
    await _event(env, "Standup", _at(SUNDAY, 9), location="Room 4")
    (reminder,) = [r for r in await _get(env, _at(SUNDAY, 0)) if r["kind"] == "event"]
    assert reminder["fire_at"].startswith("2030-03-10T08:45:00")
    assert reminder["body"] == "Starts at 09:00 · Room 4"
    assert reminder["link"].startswith("/?date=2030-03-10&event=")
    assert reminder["at"].startswith("2030-03-10T09:00:00")
    assert (reminder["verb"], reminder["detail"]) == ("Starts", "Room 4")
    await _settings(env, event_reminder_minutes=30)
    (later,) = [r for r in await _get(env, _at(SUNDAY, 0)) if r["kind"] == "event"]
    assert later["fire_at"].startswith("2030-03-10T08:30:00")


async def test_an_event_in_two_calendars_is_one_reminder(env: ProjectsEnv) -> None:
    await _connected(env)
    await _event(env, "Planning", _at(SUNDAY, 10), uid="abc@example.com")
    await _event(env, "Planning", _at(SUNDAY, 10), uid="abc@example.com")
    await _event(env, "Lunch", _at(SUNDAY, 12))  # no UID: the same title and time is one event
    await _event(env, "Lunch", _at(SUNDAY, 12))
    await _event(env, "Weekly", _at(SUNDAY, 15), uid="rep@example.com")  # a repeating event:
    await _event(env, "Weekly", _at(SUNDAY + timedelta(days=1), 15), uid="rep@example.com")
    events = [r for r in await _get(env, _at(SUNDAY, 0), 48) if r["kind"] == "event"]
    assert [e["title"] for e in events] == ["Planning", "Lunch", "Weekly", "Weekly"]
    assert len({e["id"] for e in events}) == 4


async def test_an_all_day_event_a_deleted_event_and_a_past_event_get_no_reminder(
    env: ProjectsEnv,
) -> None:
    await _connected(env)
    await _event(env, "Holiday", _at(SUNDAY, 0), all_day=True)
    await _event(env, "Cancelled", _at(SUNDAY, 9), sync_state="deleted_remotely")
    await _event(env, "Earlier", _at(SUNDAY, 1))
    assert [r for r in await _get(env, _at(SUNDAY, 6)) if r["kind"] == "event"] == []


async def test_the_weekly_review_is_on_sunday_at_noon_until_it_is_done(env: ProjectsEnv) -> None:
    got = [r for r in await _get(env, _at(SUNDAY, 0)) if r["kind"] == "weekly_review"]
    (reminder,) = got
    assert reminder["fire_at"].startswith("2030-03-10T12:00:00")
    assert reminder["id"] == "weekly_review:2030-03-04"
    assert reminder["link"] == "/week/plan?date=2030-03-11"
    # No other day has one.
    assert [r for r in await _get(env, _at(SUNDAY - timedelta(days=3), 0), 48)] == []


async def test_a_weekly_review_that_is_done_gets_no_reminder(env: ProjectsEnv) -> None:
    user = await env.user_id()
    monday = SUNDAY - timedelta(days=6)
    async with env.db() as db:
        db.add(
            WeeklyPlan(
                user_id=user,
                week_start=monday,
                status="committed",
                reviewed_at=_at(SUNDAY, 8),
            )
        )
    assert await _get(env, _at(SUNDAY, 0)) == []


async def test_a_committed_plan_for_the_next_week_also_ends_the_weekly_reminder(
    env: ProjectsEnv,
) -> None:
    user = await env.user_id()
    async with env.db() as db:
        db.add(WeeklyPlan(user_id=user, week_start=SUNDAY + timedelta(days=1), status="draft"))
    assert len(await _get(env, _at(SUNDAY, 0))) == 1  # a draft is not done
    async with env.db() as db:
        plan = (await db.execute(select(WeeklyPlan))).scalar_one()
        plan.status = "committed"
    assert await _get(env, _at(SUNDAY, 0)) == []


async def test_the_monthly_review_is_on_the_last_day_of_the_month_until_it_is_done(
    env: ProjectsEnv,
) -> None:
    last = date(2030, 4, 30)  # a Tuesday
    (reminder,) = await _get(env, _at(last, 0))
    assert reminder["kind"] == "monthly_review"
    assert reminder["fire_at"].startswith("2030-04-30T12:00:00")
    assert reminder["link"] == "/month/review?date=2030-04-01"
    assert [r for r in await _get(env, _at(date(2030, 4, 29), 0))] == []
    # February of a leap year ends on the 29th.
    leap = await _get(env, _at(date(2032, 2, 28), 12), 48)
    assert [r["fire_at"][:10] for r in leap if r["kind"] == "monthly_review"] == ["2032-02-29"]
    async with env.db() as db:
        db.add(
            MonthlyReview(
                user_id=await env.user_id(),
                month=date(2030, 4, 1),
                current_version=1,
                current_changed_at=_at(last, 9),
            )
        )
    assert await _get(env, _at(last, 0)) == []


async def test_the_annual_review_is_on_26_december_and_at_the_end_of_the_year(
    env: ProjectsEnv,
) -> None:
    found = [
        (r["id"], r["fire_at"][:16])
        for r in await _get(env, _at(date(2030, 12, 25), 0), 24 * 7)
        if r["kind"] == "annual_review"
    ]
    assert found == [
        ("annual_review:2030:26", "2030-12-26T12:00"),
        ("annual_review:2030:31", "2030-12-31T15:00"),
    ]
    async with env.db() as db:
        db.add(ReviewNote(user_id=await env.user_id(), year=2030, body="A good year."))
    assert [
        r
        for r in await _get(env, _at(date(2030, 12, 25), 0), 24 * 7)
        if r["kind"] == "annual_review"
    ] == []
    # Another year is not affected.
    assert len(await _get(env, _at(date(2031, 12, 26), 0))) >= 1


async def test_the_reviews_use_the_time_zone_of_the_user(env: ProjectsEnv) -> None:
    async with env.db() as db:
        user = (await db.execute(select(User).where(User.username == "admin"))).scalar_one()
        user.timezone = "Europe/Athens"  # UTC+2 in March
    (reminder,) = [r for r in await _get(env, _at(SUNDAY, 0)) if r["kind"] == "weekly_review"]
    assert reminder["fire_at"].startswith("2030-03-10T10:00:00")  # midday in Athens


async def test_the_list_needs_a_signed_in_user(env: ProjectsEnv) -> None:
    r = await env.api.get(f"{V1}/reminders", headers={"Authorization": "Bearer nope"})
    assert r.status_code == 401
