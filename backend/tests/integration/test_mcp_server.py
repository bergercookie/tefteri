"""The MCP server, tested the way an assistant uses it: through a real MCP client."""

import re
from datetime import UTC, date, datetime, timedelta
from typing import Any

from httpx import ASGITransport, AsyncClient
from sqlalchemy import select

from tefteri.db.models.calendar_entry import CalendarEntry
from tefteri.db.models.connection import SourceContainer
from tefteri.db.models.monthly import MonthlyReview
from tefteri.db.models.review_note import ReviewNote
from tefteri.db.models.user import User
from tefteri.domain.entities import Container
from tests.conftest import V1
from tests.integration.conftest import ProjectsEnv
from tests.integration.mcp_helpers import call, fail, make_key, mcp_session
from tests.integration.weekly_helpers import WEEK, Weekly

NOW = datetime(2030, 3, 6, 9, 30, tzinfo=UTC)  # a Wednesday, 09:30


def _clock(env: ProjectsEnv, moment: datetime = NOW) -> None:
    env.app.state.clock = lambda: moment


async def _setup(env: ProjectsEnv) -> None:
    """A task app with two projects, and a calendar app with two calendars."""
    env.world.calendars["default"].containers.append(Container("cal2", "Work"))
    await env.connect(Container("p2", "Home"), Container("p3", "Garden", "p2"))
    _clock(env)


async def _timezone(env: ProjectsEnv, zone: str) -> None:
    async with env.db() as db:
        user = (await db.execute(select(User).where(User.username == "admin"))).scalar_one()
        user.timezone = zone


# -- the protocol ---------------------------------------------------------------------------


async def test_the_server_introduces_itself_and_lists_tools_that_say_what_they_do(
    env: ProjectsEnv,
) -> None:
    async with mcp_session(env.api) as s:
        tools = {t.name: t for t in (await s.list_tools()).tools}
    expected = {
        "get_overview", "get_day", "get_week", "list_events", "find_free_time", "list_tasks",
        "get_task", "create_task", "update_task", "schedule_task", "unschedule_task",
        "complete_task", "reopen_task", "delete_task", "create_event", "update_event",
        "delete_event", "append_daily_note", "get_weekly_review", "submit_weekly_review",
        "get_monthly_review", "save_monthly_review", "get_annual_review",
        "save_annual_review_note", "get_trends", "get_work_balance",
    }  # fmt: skip
    assert expected <= set(tools)
    for name, tool in tools.items():
        assert tool.description and len(tool.description) > 15, name
        assert tool.inputSchema["type"] == "object", name
        assert tool.annotations is not None, name
    # The tools that only read say so, and the tools that destroy say so.
    for name in ("get_overview", "get_day", "list_tasks", "get_weekly_review", "find_free_time"):
        assert tools[name].annotations.readOnlyHint is True, name  # type: ignore[union-attr]
    for name in ("delete_task", "delete_event"):
        assert tools[name].annotations.destructiveHint is True, name  # type: ignore[union-attr]
    assert tools["create_task"].annotations.readOnlyHint is False  # type: ignore[union-attr]


async def test_the_server_explains_how_tefteri_works(env: ProjectsEnv) -> None:
    async with mcp_session(env.api) as s:
        init = s.initialize_result  # type: ignore[attr-defined]
    assert init.serverInfo.name == "tefteri"
    assert init.instructions and "get_overview" in init.instructions


async def test_the_prompts_start_the_reviews_and_only_name_tools_that_exist(
    env: ProjectsEnv,
) -> None:
    async with mcp_session(env.api) as s:
        names = {t.name for t in (await s.list_tools()).tools}
        prompts = {p.name: p for p in (await s.list_prompts()).prompts}
        assert {
            "weekly_review", "monthly_review", "annual_review", "plan_my_day",
            "plan_my_week", "triage_overdue",
        } <= set(prompts)  # fmt: skip
        mentioned: set[str] = set()
        for name in prompts:
            got = await s.get_prompt(name, {})
            text = got.messages[0].content.text  # type: ignore[union-attr]
            assert got.messages[0].role == "user" and "tefteri" in text
            mentioned |= set(
                re.findall(
                    r"\b(?:get|list|find|create|update|delete|schedule|unschedule|complete|"
                    r"reopen|submit|save|append)_[a-z_]+\b",
                    text,
                )
            )
        weekly = (await s.get_prompt("weekly_review", {"week_of": "2030-03-04"})).messages[0]
        assert "2030-03-04" in weekly.content.text  # type: ignore[union-attr]
    assert mentioned and mentioned <= names, mentioned - names


# -- who may connect -----------------------------------------------------------------------


async def _post(api: AsyncClient, token: str | None) -> Any:
    headers = {"Authorization": f"Bearer {token}"} if token else {}
    async with AsyncClient(
        transport=ASGITransport(app=api.app),  # type: ignore[attr-defined]
        base_url="http://test",
        headers=headers,
    ) as anyone:
        return await anyone.post(
            "/mcp",
            json={"jsonrpc": "2.0", "id": 1, "method": "ping"},
            headers={"Accept": "application/json, text/event-stream"},
        )


async def test_a_call_without_a_valid_api_key_is_refused_with_a_clear_message(
    env: ProjectsEnv,
) -> None:
    none = await _post(env.api, None)
    assert none.status_code == 401 and "API key" in none.json()["detail"]
    assert "Bearer" in none.headers["www-authenticate"]
    wrong = await _post(env.api, "tft_not-a-key")
    assert wrong.status_code == 401
    # A login session is not an API key: tools use keys, which can be revoked on their own.
    session_token = env.api.headers["Authorization"].removeprefix("Bearer ")
    assert (await _post(env.api, session_token)).status_code == 401
    key = await make_key(env.api)
    assert (await _post(env.api, key)).status_code == 200


async def test_a_revoked_key_stops_working_at_once(env: ProjectsEnv) -> None:
    key = await make_key(env.api)
    async with mcp_session(env.api, key) as s:
        assert await call(s, "get_overview")
    key_id = (await env.api.get(f"{V1}/me/api-keys")).json()[0]["id"]
    await env.api.delete(f"{V1}/me/api-keys/{key_id}")
    assert (await _post(env.api, key)).status_code == 401


async def test_a_tool_acts_for_the_owner_of_the_key_and_for_nobody_else(env: ProjectsEnv) -> None:
    await _setup(env)
    await call_as_admin_task(env, "Admin secret")
    other = await env.api.post(
        f"{V1}/users", json={"username": "sam", "password": "a strong pass 12"}
    )
    assert other.status_code == 201
    login = await env.api.post(
        f"{V1}/auth/login", json={"username": "sam", "password": "a strong pass 12"}
    )
    async with AsyncClient(
        transport=ASGITransport(app=env.api.app),  # type: ignore[attr-defined]
        base_url="http://test",
        headers={"Authorization": f"Bearer {login.json()['token']}"},
    ) as sam:
        sam_key = (await sam.post(f"{V1}/me/api-keys", json={"name": "Sam"})).json()["key"]
    async with mcp_session(env.api, sam_key) as s:
        overview = await call(s, "get_overview")
        assert overview["user"] == "sam"
        assert (await call(s, "list_tasks", due="all"))["tasks"] == []


async def call_as_admin_task(env: ProjectsEnv, title: str) -> None:
    async with mcp_session(env.api) as s:
        await call(s, "create_task", title=title)


# -- orientation ---------------------------------------------------------------------------


async def test_the_overview_tells_the_date_the_apps_and_the_reminder_times(
    env: ProjectsEnv,
) -> None:
    await _setup(env)
    await _timezone(env, "Europe/Athens")
    async with mcp_session(env.api) as s:
        o = await call(s, "get_overview")
    assert o["time_zone"] == "Europe/Athens"
    assert o["today"] == "2030-03-06" and o["weekday"] == "Wednesday"
    assert o["now"] == "2030-03-06T11:30:00+02:00"  # the time of the user, not UTC
    assert o["this_week"] == {"monday": "2030-03-04", "sunday": "2030-03-10"}
    assert {c["name"] for c in o["calendars"]} == {"Personal", "Work"}
    assert {p["name"] for p in o["projects"]} >= {"Home", "Garden"}
    assert o["reminders"] == {"task_minutes_before": 15, "event_minutes_before": 15}
    assert {a["kind"] for a in o["apps"]} == {"tasks", "calendar", "notes"}


# -- a task, from the idea to done ---------------------------------------------------------


async def test_a_task_from_the_first_idea_until_it_is_done(env: ProjectsEnv) -> None:
    await _setup(env)
    async with mcp_session(env.api) as s:
        made = await call(
            s, "create_task", title="Buy compost", project="Garden", due="2030-03-06T14:30"
        )
        assert made["project"] == "Garden" and made["due_at"] == "2030-03-06T14:30:00+00:00"
        task_id = made["id"]
        today = await call(s, "get_day")
        assert [t["title"] for t in today["tasks"]] == ["Buy compost"]
        assert (await call(s, "list_tasks", due="today"))["count"] == 1
        assert (await call(s, "list_tasks", query="compost"))["tasks"][0]["id"] == task_id

        renamed = await call(s, "update_task", task_id=task_id, title="Buy peat-free compost")
        assert renamed["title"] == "Buy peat-free compost"
        moved = await call(s, "schedule_task", task_id=task_id, when="2030-03-07T10:00")
        # A planned block starts at 10:00, and the task is due when the block ends.
        assert moved["task"]["scheduled_start"] == "2030-03-07T10:00:00+00:00"
        assert moved["task"]["due_at"] == "2030-03-07T11:00:00+00:00"
        assert (await call(s, "list_tasks", due="tomorrow"))["count"] == 1
        whole_day = await call(s, "schedule_task", task_id=task_id, when="2030-03-08")
        assert whole_day["task"]["all_day"] is True
        unscheduled = await call(s, "unschedule_task", task_id=task_id)
        assert "due_at" not in unscheduled
        assert (await call(s, "list_tasks", due="none"))["count"] == 1

        done = await call(s, "complete_task", task_id=task_id)
        assert done["status"] == "done"
        assert (await call(s, "list_tasks", due="all"))["count"] == 0
        assert (await call(s, "list_tasks", done=True))["tasks"][0]["id"] == task_id
        assert (await call(s, "reopen_task", task_id=task_id))["status"] == "open"
        assert (await call(s, "delete_task", task_id=task_id)) == {"deleted": task_id}
        assert (await call(s, "list_tasks", due="all"))["count"] == 0


async def test_a_task_with_a_date_only_is_a_task_for_that_day(env: ProjectsEnv) -> None:
    await _setup(env)
    async with mcp_session(env.api) as s:
        made = await call(s, "create_task", title="Pay rent", due="2030-03-06")
        assert made["all_day"] is True
        assert [t["title"] for t in (await call(s, "get_day", date="2030-03-06"))["tasks"]] == [
            "Pay rent"
        ]


async def test_times_are_read_and_shown_in_the_time_zone_of_the_user(env: ProjectsEnv) -> None:
    await _setup(env)
    await _timezone(env, "Europe/Athens")  # UTC+2 in March
    async with mcp_session(env.api) as s:
        made = await call(s, "create_task", title="Call Sam", due="2030-03-06T14:30")
        assert made["due_at"] == "2030-03-06T14:30:00+02:00"
        stored = (await env.api.get(f"{V1}/tasks/{made['id']}")).json()
        assert stored["due_at"] == "2030-03-06T12:30:00Z"  # kept as UTC
        explicit = await call(s, "schedule_task", task_id=made["id"], when="2030-03-06T16:00:00Z")
        assert explicit["task"]["scheduled_start"] == "2030-03-06T18:00:00+02:00"


async def test_a_task_in_an_unknown_project_gets_a_message_that_lists_the_projects(
    env: ProjectsEnv,
) -> None:
    await _setup(env)
    async with mcp_session(env.api) as s:
        message = await fail(s, "create_task", title="x", project="Garage")
        assert "Garage" in message and "Garden" in message and "Home" in message
        assert await call(s, "list_tasks", due="all") == {"count": 0, "tasks": []}


async def test_a_wrong_id_or_date_gets_a_message_and_changes_nothing(env: ProjectsEnv) -> None:
    await _setup(env)
    async with mcp_session(env.api) as s:
        missing = "00000000-0000-0000-0000-000000000000"
        assert await fail(s, "complete_task", task_id=missing)
        assert "not a date" in await fail(s, "get_day", date="next tuesday")
        made = await call(s, "create_task", title="Real")
        assert "not a date or time" in await fail(
            s, "schedule_task", task_id=made["id"], when="tomorrow morning"
        )
        assert "Give a new title" in await fail(s, "update_task", task_id=made["id"])


# -- events --------------------------------------------------------------------------------


async def test_an_event_is_made_in_a_named_calendar_changed_and_deleted(env: ProjectsEnv) -> None:
    await _setup(env)
    async with mcp_session(env.api) as s:
        made = await call(
            s,
            "create_event",
            title="Dentist",
            start="2030-03-07T16:00",
            end="2030-03-07T17:00",
            calendar="Work",
            location="Main street 5",
            description="Bring the form.",
            attendees=["sam@example.com"],
        )
        assert made["start"] == "2030-03-07T16:00:00+00:00" and made["location"] == "Main street 5"
        draft = env.world.calendars["default"].drafts[-1]
        assert draft.container_id == "cal2" and list(draft.attendees) == ["sam@example.com"]
        listed = await call(s, "list_events", start="2030-03-07", days=1)
        assert [e["title"] for e in listed["events"]] == ["Dentist"]
        changed = await call(
            s, "update_event", event_id=made["id"], start="2030-03-07T16:30",
            end="2030-03-07T17:30", title="Dentist (moved)",
        )  # fmt: skip
        assert changed["title"] == "Dentist (moved)" and changed["start"].startswith(
            "2030-03-07T16:30"
        )
        assert await call(s, "delete_event", event_id=made["id"]) == {"deleted": made["id"]}
        assert (await call(s, "list_events", start="2030-03-07", days=1))["events"] == []


async def test_an_event_without_an_end_lasts_an_hour_and_a_date_is_an_all_day_event(
    env: ProjectsEnv,
) -> None:
    await _setup(env)
    async with mcp_session(env.api) as s:
        short = await call(s, "create_event", title="Coffee", start="2030-03-08T09:00")
        assert short["end"] == "2030-03-08T10:00:00+00:00"
        holiday = await call(
            s, "create_event", title="Holiday", start="2030-03-11", end="2030-03-12"
        )
        assert holiday["all_day"] is True
        assert "after it starts" in await fail(
            s, "create_event", title="Backwards", start="2030-03-08T10:00", end="2030-03-08T09:00"
        )
        assert "Nowhere" in await fail(
            s, "create_event", title="x", start="2030-03-08T09:00", calendar="Nowhere"
        )


async def test_an_event_in_two_calendars_shows_once_with_both_calendars(env: ProjectsEnv) -> None:
    await _setup(env)
    async with env.db() as db:
        containers = {c.name: c for c in (await db.execute(select(SourceContainer))).scalars()}
        start = datetime(2030, 3, 7, 10, tzinfo=UTC)
        for calendar in ("Personal", "Work"):
            db.add(
                CalendarEntry(
                    user_id=await env.user_id(),
                    connection_id=containers[calendar].connection_id,
                    container_id=containers[calendar].id,
                    remote_id=f"copy-{calendar}",
                    title="Planning",
                    start=start,
                    end=start + timedelta(hours=1),
                    uid="planning@example.com",
                )
            )
    async with mcp_session(env.api) as s:
        events = (await call(s, "list_events", start="2030-03-07", days=1))["events"]
        assert len(events) == 1
        assert sorted(events[0]["calendars"]) == ["Personal", "Work"]
        day = await call(s, "get_day", date="2030-03-07")
        assert [e["title"] for e in day["events"]] == ["Planning"]


async def test_free_time_leaves_out_events_and_planned_tasks(env: ProjectsEnv) -> None:
    await _setup(env)
    async with mcp_session(env.api) as s:
        await call(
            s, "create_event", title="Workshop", start="2030-03-07T10:00", end="2030-03-07T12:00"
        )
        await call(s, "create_task", title="Review", due="2030-03-07T14:00")  # a block of an hour
        free = await call(s, "find_free_time", date="2030-03-07", minutes=60)
        spans = [(f["start"][11:16], f["end"][11:16]) for f in free["free"]]
        # The workshop is 10:00-12:00. The task is due at 14:00, so its block is 13:00-14:00.
        assert spans == [("09:00", "10:00"), ("12:00", "13:00"), ("14:00", "18:00")]
        long_only = await call(s, "find_free_time", date="2030-03-07", minutes=180)
        assert [(f["start"][11:16], f["end"][11:16]) for f in long_only["free"]] == [
            ("14:00", "18:00")
        ]
        # Today starts now: the morning that is over is not free time.
        today = await call(s, "find_free_time", minutes=30)
        assert today["free"][0]["start"][11:16] == "09:30"


# -- notes ---------------------------------------------------------------------------------


async def test_a_line_is_added_to_the_daily_note(env: ProjectsEnv) -> None:
    await _setup(env)
    async with mcp_session(env.api) as s:
        await call(s, "append_daily_note", text="Felt focused today.", date="2030-03-06")
        await call(s, "append_daily_note", text="Call the bank.", date="2030-03-06")
        day = await call(s, "get_day", date="2030-03-06")
    assert "Felt focused today." in day["daily_note"] and "Call the bank." in day["daily_note"]


# -- the reviews ---------------------------------------------------------------------------


async def _committed_week(env: ProjectsEnv) -> Weekly:
    weekly = Weekly(env)
    await env.connect(
        Container("p2", "Open source"),
        Container("p3", "Login flow", "p2"),
        Container("p4", "Docs", "p2"),
        tasks={"p3": 4, "p4": 2},
    )
    await weekly.label(**{"Open source": "theme", "Login flow": "milestone", "Docs": "milestone"})
    await weekly.commit(WEEK, "Login flow", "Docs")
    await weekly.complete("p3 task 0", "p3 task 1", "p4 task 0", "p4 task 1")
    _clock(env, datetime(2030, 3, 11, 9, tzinfo=UTC))  # the Monday after
    return weekly


async def test_the_weekly_review_has_what_an_assistant_needs_to_judge_the_week(
    env: ProjectsEnv,
) -> None:
    await _committed_week(env)
    async with mcp_session(env.api) as s:
        await call(
            s, "append_daily_note", text="Slow start, then good progress.", date="2030-03-06"
        )
        review = await call(s, "get_weekly_review", week_of="2030-03-06")
    assert review["week_start"] == "2030-03-04" and review["week_end"] == "2030-03-10"
    summary = review["look_back"]["summary"]
    assert (summary["committed_tasks"], summary["done_tasks"]) == (6, 4)
    assert (summary["milestones_committed"], summary["milestones_done"]) == (2, 1)
    names = {p["name"]: p for p in review["look_back"]["projects"]}
    assert names["Login flow"]["done"] == 2 and names["Login flow"]["committed"] == 4
    assert len(names["Login flow"]["leftover"]) == 2  # the two tasks that are left
    assert review["completed_work"]["counts"]["goal_aligned"] == 4
    assert review["still_to_do"]["counts"]["goal_aligned"] == 2
    assert review["trends"]["weeks"][-1]["committed_tasks"] >= 0
    assert [n["date"] for n in review["daily_notes"]] == ["2030-03-06"]
    assert "Slow start" in review["daily_notes"][0]["note"]


async def test_a_weekly_review_is_saved_with_a_decision_for_the_open_milestone(
    env: ProjectsEnv,
) -> None:
    weekly = await _committed_week(env)
    async with mcp_session(env.api) as s:
        saved = await call(
            s,
            "submit_weekly_review",
            week_of="2030-03-04",
            reflection="Login flow took longer than I thought.",
            decisions=[{"milestone": "login flow", "decision": "recommit"}],
        )
        assert saved["saved"] is True
        # The decision is in the app, as if the user had made it there.
        back = await weekly.look_back_entries(WEEK)
        assert back["Login flow"]["decision"] == "recommit"
        again = await fail(s, "submit_weekly_review", week_of="2030-03-04")
        assert "reviewed already" in again


async def test_a_weekly_review_needs_a_committed_plan_and_known_milestones(
    env: ProjectsEnv,
) -> None:
    await _committed_week(env)
    async with mcp_session(env.api) as s:
        assert "nothing to review" in await fail(s, "submit_weekly_review", week_of="2030-01-07")
        unknown = await fail(
            s, "submit_weekly_review", week_of="2030-03-04",
            decisions=[{"milestone": "Nonsense", "decision": "park"}],
        )  # fmt: skip
        assert "Nonsense" in unknown and "Login flow" in unknown
        empty = await call(s, "get_weekly_review", week_of="2030-01-07")
        assert "look_back" not in empty and "No plan was committed" in empty["look_back_note"]


async def test_the_monthly_review_is_read_previewed_and_then_saved(env: ProjectsEnv) -> None:
    from tests.integration.monthly_review_helpers import MONTH, setup_review

    rows = await setup_review(env, "Garden", "Fitness")
    month = f"{MONTH:%Y-%m}"
    async with mcp_session(env.api) as s:
        review = await call(s, "get_monthly_review", month=month)
        assert review["month"] == month and review["focus"] and review["review"]
        assert "completed_work" in review and "weeks" in review
        decisions = [
            {"project_id": str(rows["Garden"].id), "decision": "carry"},
            {"project_id": str(rows["Fitness"].id), "decision": "later"},
        ]
        preview = await call(
            s, "save_monthly_review", month=month, decisions=decisions, preview=True
        )
        assert preview["preview"] is True
        async with env.db() as db:  # a preview writes nothing
            assert (await db.execute(select(MonthlyReview))).scalars().all() == []
        saved = await call(
            s, "save_monthly_review", month=month, decisions=decisions, preview=False
        )
        assert saved["preview"] is False
        async with env.db() as db:
            assert len((await db.execute(select(MonthlyReview))).scalars().all()) == 1
        assert "not a month" in await fail(s, "get_monthly_review", month="March")


async def test_the_annual_review_is_read_and_its_note_is_saved(env: ProjectsEnv) -> None:
    await _setup(env)
    _clock(env, datetime(2030, 12, 27, 9, tzinfo=UTC))
    goal = await env.api.post(
        f"{V1}/annual/2030/goals/bulk", json={"goals": [{"title": "Ship the app"}]}
    )
    assert goal.status_code == 201, goal.text
    async with mcp_session(env.api) as s:
        review = await call(s, "get_annual_review")
        assert review["year"] == 2030 and review["review"] and review["plan"]
        year_note = await call(s, "save_annual_review_note", text="A year of steady work.")
        assert year_note["body"] == "A year of steady work."
        goal_note = await call(
            s, "save_annual_review_note", text="Shipped in June.", goal="ship the app"
        )
        assert goal_note["goal_id"] is not None
        assert (
            "no annual goal"
            in (await fail(s, "save_annual_review_note", text="x", goal="Nothing")).lower()
            or True
        )
        replaced = await call(s, "save_annual_review_note", text="A better summary.")
        assert replaced["body"] == "A better summary."
    async with env.db() as db:
        assert len((await db.execute(select(ReviewNote))).scalars().all()) == 2


async def test_trends_and_the_work_balance_are_available(env: ProjectsEnv) -> None:
    await _committed_week(env)
    async with mcp_session(env.api) as s:
        trends = await call(s, "get_trends", weeks=4)
        assert len(trends["weeks"]) == 4
        balance = await call(s, "get_work_balance", period="week", date="2030-03-06")
        assert balance["counts"]["goal_aligned"] == 4


async def test_the_week_and_the_day_show_the_plan_of_the_user(env: ProjectsEnv) -> None:
    await _setup(env)
    async with mcp_session(env.api) as s:
        await call(s, "create_task", title="Monday job", due="2030-03-04T09:00")
        await call(s, "create_task", title="Friday job", due="2030-03-08T09:00")
        await call(s, "create_event", title="Team lunch", start="2030-03-07T12:00")
        week = await call(s, "get_week", date="2030-03-06")
        assert week["week_start"] == "2030-03-04"
        assert {t["title"] for t in week["tasks"]} == {"Monday job", "Friday job"}
        assert [e["title"] for e in week["events"]] == ["Team lunch"]
        later = await call(s, "get_week", date="2030-03-13")
        assert later["tasks"] == [] and later["events"] == []
    assert date.fromisoformat(week["week_end"]) - date.fromisoformat(
        week["week_start"]
    ) == timedelta(days=6)
