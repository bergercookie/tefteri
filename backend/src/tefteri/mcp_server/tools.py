"""The tools of the MCP server.

Every tool opens the API of the app as the user of the API key of the call, so it gets the same
checks and the same data as the app. A tool returns plain data with local times, and a failure
is a message that says what to do next.
"""

from collections.abc import AsyncIterator
from contextlib import asynccontextmanager
from datetime import date as Day
from datetime import datetime, time, timedelta
from typing import Annotated, Any, Literal

from mcp.server.fastmcp import Context, FastMCP
from mcp.server.fastmcp.exceptions import ToolError
from mcp.types import ToolAnnotations
from pydantic import Field

from tefteri.mcp_server.calendar_view import free_slots, unique_events
from tefteri.mcp_server.client import (
    Api,
    day_window,
    iso,
    parse_day,
    parse_moment,
)

Due = Literal["today", "tomorrow", "week", "overdue", "none", "all"]

_READ = ToolAnnotations(readOnlyHint=True, openWorldHint=False)
_WRITE = ToolAnnotations(readOnlyHint=False, destructiveHint=False, openWorldHint=False)
_IDEMPOTENT = ToolAnnotations(
    readOnlyHint=False, destructiveHint=False, idempotentHint=True, openWorldHint=False
)
_DELETE = ToolAnnotations(readOnlyHint=False, destructiveHint=True, openWorldHint=False)

_TASK_FIELDS = (
    "id",
    "title",
    "status",
    "due_at",
    "all_day",
    "project",
    "theme",
    "labels",
    "category",
    "scheduled_start",
    "scheduled_end",
    "completed_at",
    "url",
    "sync_state",
)
_DAY = "A day as YYYY-MM-DD. Leave it out for today."
_WHEN = (
    "A date (YYYY-MM-DD) or a time (YYYY-MM-DDTHH:MM). A time without an offset is the local "
    "time of the user."
)


def _task(t: dict[str, Any], *, detail: bool = False) -> dict[str, Any]:
    """The fields of a task that an assistant needs."""
    keep = (*_TASK_FIELDS, "description") if detail else _TASK_FIELDS
    return {k: t[k] for k in keep if k in t and t[k] not in (None, [], "")}


def _week_start(day: Day) -> Day:
    return day - timedelta(days=day.weekday())


def _month_text(text: str | None, today: Day) -> str:
    if text is None or not text.strip():
        return f"{today:%Y-%m}"
    cleaned = text.strip()[:7]
    try:
        datetime.strptime(cleaned, "%Y-%m")  # noqa: DTZ007 - only the month is read
    except ValueError as exc:
        raise ToolError(f"{text!r} is not a month. Use YYYY-MM, for example 2030-03.") from exc
    return cleaned


@asynccontextmanager
async def _session(ctx: Context[Any, Any, Any], app: Any) -> AsyncIterator[Api]:
    """The API for the user of the API key of this call."""
    request = ctx.request_context.request
    authorization = request.headers.get("authorization") if request is not None else None
    if not authorization:
        raise ToolError("Not signed in. Send an API key as 'Authorization: Bearer tft_...'.")
    api = Api(app, authorization)
    api.use_clock(app.state.clock)
    try:
        yield await api.open()
    finally:
        await api.close()


async def _events(api: Api, first: Day, days: int) -> list[dict[str, Any]]:
    """The events from ``first`` for ``days`` days, each once, with local times."""
    start, end = day_window(first, days, api.zone)
    items = await api.get("/calendar", **{"from": start, "to": end})
    return [e for e in api.local(unique_events(items)) if not e.get("all_day") or True]


async def _task_connection(api: Api, name: str | None) -> dict[str, Any]:
    connections: list[dict[str, Any]] = [
        c for c in await api.get("/connections") if c["kind"] == "tasks"
    ]
    if not connections:
        raise ToolError("No task app is connected. Connect one in the app first.")
    if name:
        found = [c for c in connections if name.casefold() in c["display_name"].casefold()]
        if len(found) != 1:
            options = ", ".join(c["display_name"] for c in connections)
            raise ToolError(f"Say which task app: {options}.")
        return found[0]
    return connections[0]


async def _project_id(api: Api, connection_id: str, project: str | None) -> str | None:
    if not project:
        return None
    containers = await api.get(f"/connections/{connection_id}/containers")
    wanted = project.strip().casefold()
    exact = [c for c in containers if c["name"].casefold() == wanted]
    found = exact or [c for c in containers if wanted in c["name"].casefold()]
    if len(found) == 1:
        return str(found[0]["id"])
    names = ", ".join(sorted(c["name"] for c in (found or containers))[:40])
    if not found:
        raise ToolError(f"There is no project called {project!r}. The projects are: {names}.")
    raise ToolError(f"{project!r} fits more than one project. Say which one: {names}.")


async def _calendar(api: Api, name: str | None) -> tuple[str, str | None]:
    """The connection and the calendar (container) for a new event."""
    connections = [c for c in await api.get("/connections") if c["kind"] == "calendar"]
    if not connections:
        raise ToolError("No calendar app is connected. Connect one in the app first.")
    writable: list[tuple[dict[str, Any], dict[str, Any]]] = []
    for c in connections:
        for cal in await api.get(f"/connections/{c['id']}/containers"):
            if cal.get("enabled", True) and not cal.get("read_only", False):
                writable.append((c, cal))
    if name:
        wanted = name.strip().casefold()
        exact = [w for w in writable if w[1]["name"].casefold() == wanted]
        found = exact or [w for w in writable if wanted in w[1]["name"].casefold()]
        if len(found) != 1:
            options = ", ".join(w[1]["name"] for w in writable)
            reason = "fits more than one calendar" if found else "is not a calendar you can change"
            raise ToolError(f"{name!r} {reason}. The calendars you can change are: {options}.")
        return str(found[0][0]["id"]), str(found[0][1]["id"])
    chosen = (await api.get("/me/settings")).get("default_event_container_id")
    for c, cal in writable:
        if str(cal["id"]) == str(chosen):
            return str(c["id"]), str(cal["id"])
    if not writable:
        return str(connections[0]["id"]), None
    return str(writable[0][0]["id"]), str(writable[0][1]["id"])


def register(mcp: FastMCP, app: Any) -> None:  # noqa: C901, PLR0915 - one place lists every tool
    """Add the tools to ``mcp``."""
    # -- orientation ------------------------------------------------------------------

    @mcp.tool(annotations=_READ)
    async def get_overview(ctx: Context[Any, Any, Any]) -> dict[str, Any]:
        """Start here. Who the user is, what day and time it is for them, and what they have.

        Returns today's date and the weekday, the week, the time zone, the connected apps, the
        calendars that can take a new event, the projects, how many open tasks each filter has,
        and the reminder times. Call it first in a conversation, so that dates are right.
        """
        async with _session(ctx, app) as api:
            today = api.today
            connections = await api.get("/connections")
            calendars: list[dict[str, Any]] = []
            projects: list[dict[str, Any]] = []
            for c in connections:
                if c["kind"] not in ("calendar", "tasks"):
                    continue
                for cont in await api.get(f"/connections/{c['id']}/containers"):
                    if c["kind"] == "calendar":
                        if cont.get("enabled", True):
                            calendars.append(
                                {
                                    "name": cont["name"],
                                    "read_only": cont.get("read_only", False),
                                    "connection": c["display_name"],
                                }
                            )
                    else:
                        projects.append({"name": cont["name"], "connection": c["display_name"]})
            settings = await api.get("/me/settings")
            monday = _week_start(today)
            return api.local(
                {
                    "user": api.username,
                    "time_zone": str(api.zone),
                    "now": api.now.replace(microsecond=0).isoformat(),
                    "today": today.isoformat(),
                    "weekday": f"{today:%A}",
                    "this_week": {
                        "monday": monday.isoformat(),
                        "sunday": (monday + timedelta(days=6)).isoformat(),
                    },
                    "this_month": f"{today:%Y-%m}",
                    "apps": [
                        {"kind": c["kind"], "name": c["display_name"], "status": c["status"]}
                        for c in connections
                    ],
                    "calendars": calendars,
                    "projects": projects[:200],
                    "open_task_counts": await api.get("/tasks/counts"),
                    "reminders": {
                        "task_minutes_before": settings["default_reminder_minutes"],
                        "event_minutes_before": settings["event_reminder_minutes"],
                    },
                }
            )

    # -- looking at time --------------------------------------------------------------

    @mcp.tool(annotations=_READ)
    async def get_day(
        ctx: Context[Any, Any, Any],
        date: Annotated[str | None, Field(description=_DAY)] = None,
    ) -> dict[str, Any]:
        """Everything on one day: the events, the tasks that are due and the daily note.

        An event that sits in more than one calendar shows once, with all its calendars. Times
        are local times of the user. Use it to plan or to look back at a day.
        """
        async with _session(ctx, app) as api:
            day = parse_day(date, api.zone, api.today)
            view = await api.get(f"/views/day/{day.isoformat()}")
            events = await _events(api, day, 1)
            note = (view.get("note") or {}).get("body")
            return api.local(
                {
                    "date": day.isoformat(),
                    "weekday": f"{day:%A}",
                    "events": events,
                    "tasks": [_task(t) for t in view["tasks"]],
                    "daily_note": note,
                }
            )

    @mcp.tool(annotations=_READ)
    async def list_events(
        ctx: Context[Any, Any, Any],
        start: Annotated[str | None, Field(description=_DAY)] = None,
        days: Annotated[int, Field(ge=1, le=62, description="How many days to look at.")] = 7,
    ) -> dict[str, Any]:
        """The calendar events from a day on, each once, in time order, with local times.

        Use it to see how busy a stretch of days is, or to find an event to change.
        """
        async with _session(ctx, app) as api:
            first = parse_day(start, api.zone, api.today)
            return {
                "from": first.isoformat(),
                "days": days,
                "events": await _events(api, first, days),
            }

    @mcp.tool(annotations=_READ)
    async def find_free_time(
        ctx: Context[Any, Any, Any],
        date: Annotated[str | None, Field(description=_DAY)] = None,
        minutes: Annotated[int, Field(ge=5, le=720, description="The shortest gap.")] = 30,
        from_hour: Annotated[int, Field(ge=0, le=23, description="Start of the day.")] = 9,
        to_hour: Annotated[int, Field(ge=1, le=24, description="End of the day.")] = 18,
    ) -> dict[str, Any]:
        """The free gaps of a day, between the events and the tasks that are planned for a time.

        Use it before you schedule an event or a task, to pick a time that is free. Only the
        hours from ``from_hour`` to ``to_hour`` count, and a day in the past starts now.
        """
        async with _session(ctx, app) as api:
            day = parse_day(date, api.zone, api.today)
            start, end = day_window(day, 1, api.zone)
            items = await api.get("/calendar", **{"from": start, "to": end})
            busy: list[tuple[datetime, datetime]] = []
            for item in items:
                if item.get("all_day") or item.get("status") == "done":
                    continue
                busy.append(
                    (
                        datetime.fromisoformat(item["start"].replace("Z", "+00:00")),
                        datetime.fromisoformat(item["end"].replace("Z", "+00:00")),
                    )
                )
            low = datetime.combine(day, time(from_hour), tzinfo=api.zone)
            high = datetime.combine(day, time(0), tzinfo=api.zone) + timedelta(hours=to_hour)
            if day == api.today:
                low = max(low, api.now.replace(second=0, microsecond=0))
            gaps = free_slots(busy, low, high, timedelta(minutes=minutes)) if low < high else []
            return {
                "date": day.isoformat(),
                "free": [
                    {
                        "start": s.astimezone(api.zone).isoformat(),
                        "end": e.astimezone(api.zone).isoformat(),
                        "minutes": int((e - s).total_seconds() // 60),
                    }
                    for s, e in gaps
                ],
            }

    @mcp.tool(annotations=_READ)
    async def get_week(
        ctx: Context[Any, Any, Any],
        date: Annotated[
            str | None, Field(description="Any day of the week. Default: today.")
        ] = None,
    ) -> dict[str, Any]:
        """One week, Monday to Sunday: the events and the tasks that are due, and the work done.

        The tasks carry their category (goal-aligned, maintenance or off-plan) when the week has
        a committed plan.
        """
        async with _session(ctx, app) as api:
            monday = _week_start(parse_day(date, api.zone, api.today))
            view = await api.get(f"/views/week/{monday.isoformat()}")
            return api.local(
                {
                    "week_start": monday.isoformat(),
                    "week_end": (monday + timedelta(days=6)).isoformat(),
                    "events": await _events(api, monday, 7),
                    "tasks": [_task(t) for t in view["tasks"]],
                }
            )

    # -- tasks ------------------------------------------------------------------------

    @mcp.tool(annotations=_READ)
    async def list_tasks(
        ctx: Context[Any, Any, Any],
        due: Annotated[
            Due,
            Field(
                description="Which open tasks: due today, tomorrow, this week, overdue, with "
                "no due date, or all."
            ),
        ] = "today",
        query: Annotated[
            str | None, Field(description="Search the titles of all open tasks. Ignores 'due'.")
        ] = None,
        done: Annotated[
            bool, Field(description="List finished tasks instead of open ones.")
        ] = False,
        limit: Annotated[int, Field(ge=1, le=200)] = 100,
    ) -> dict[str, Any]:
        """List tasks. Open ones by due date, or a search, or the finished ones.

        Each task has an id, which the other task tools need.
        """
        async with _session(ctx, app) as api:
            if done:
                found = await api.get("/tasks", status="done")
                found.sort(key=lambda t: t.get("completed_at") or "", reverse=True)
            elif query and query.strip():
                found = await api.get("/tasks", q=query.strip())
            else:
                found = await api.get("/tasks", due=due)
            if not done:
                found.sort(
                    key=lambda t: (t.get("due_at") is None, t.get("due_at") or "", t["title"])
                )
            return api.local({"count": len(found), "tasks": [_task(t) for t in found[:limit]]})

    @mcp.tool(annotations=_READ)
    async def get_task(
        ctx: Context[Any, Any, Any], task_id: Annotated[str, Field(description="The id of a task.")]
    ) -> dict[str, Any]:
        """One task with its description, project, due time and reminder."""
        async with _session(ctx, app) as api:
            task = await api.get(f"/tasks/{task_id}")
            out = _task(task, detail=True)
            if task.get("scheduled_start"):
                out["scheduled_start"] = task["scheduled_start"]
                out["scheduled_end"] = task.get("scheduled_end")
            return api.local(out)

    @mcp.tool(annotations=_WRITE)
    async def create_task(
        ctx: Context[Any, Any, Any],
        title: Annotated[str, Field(min_length=1, max_length=500)],
        project: Annotated[
            str | None, Field(description="The name of the project. Default: the inbox of the app.")
        ] = None,
        due: Annotated[
            str | None,
            Field(
                description="The deadline. A date makes it a task for that day; a time is the "
                "time when it is due. " + _WHEN
            ),
        ] = None,
        description: str = "",
        labels: list[str] | None = None,
        task_app: Annotated[
            str | None, Field(description="The name of the task app, if there is more than one.")
        ] = None,
    ) -> dict[str, Any]:
        """Add a task, optionally in a project and with a due date or time.

        ``due`` is a deadline. To plan when to work on the task, call schedule_task afterwards.
        A task with a due time gets a reminder notification on the phone of the user, at their
        usual time before it.
        """
        async with _session(ctx, app) as api:
            connection = await _task_connection(api, task_app)
            body: dict[str, Any] = {
                "connection_id": connection["id"],
                "title": title,
                "description": description,
                "labels": labels or [],
            }
            container = await _project_id(api, connection["id"], project)
            if container:
                body["container_id"] = container
            task = await api.post("/tasks", body)
            if due:
                moment, date_only = parse_moment(due, api.zone)
                if date_only:
                    local_day = moment.astimezone(api.zone).date().isoformat()
                    await api.put(f"/tasks/{task['id']}/schedule", {"date": local_day})
                else:
                    await api.patch(f"/tasks/{task['id']}", {"due_at": iso(moment)})
            return api.local(_task(await api.get(f"/tasks/{task['id']}"), detail=True))

    @mcp.tool(annotations=_IDEMPOTENT)
    async def update_task(
        ctx: Context[Any, Any, Any],
        task_id: str,
        title: str | None = None,
        description: Annotated[
            str | None, Field(description="The whole new description. It replaces the old one.")
        ] = None,
    ) -> dict[str, Any]:
        """Change the title or the description of a task. Use schedule_task to move it in time."""
        async with _session(ctx, app) as api:
            if title is None and description is None:
                raise ToolError("Give a new title or a new description.")
            current = await api.get(f"/tasks/{task_id}")
            task = await api.patch(
                f"/tasks/{task_id}",
                {
                    "title": title if title is not None else current["title"],
                    "description": description
                    if description is not None
                    else current.get("description", ""),
                },
            )
            return api.local(_task(task, detail=True))

    @mcp.tool(annotations=_IDEMPOTENT)
    async def schedule_task(
        ctx: Context[Any, Any, Any],
        task_id: str,
        when: Annotated[
            str,
            Field(
                description="A date puts the task on that day without a time. A time plans a "
                "block of an hour that starts then: the task is due when the block ends. " + _WHEN
            ),
        ],
    ) -> dict[str, Any]:
        """Plan a task for a day, or for a time. It moves a task that is planned already.

        The answer lists the events that overlap the new time, so you can offer another time.
        """
        async with _session(ctx, app) as api:
            moment, date_only = parse_moment(when, api.zone)
            path = f"/tasks/{task_id}/schedule"
            if date_only:
                body: dict[str, Any] = {"date": moment.astimezone(api.zone).date().isoformat()}
            else:
                body = {"start": iso(moment)}
            result = await api.put(path, body)
            planned = await api.get(f"/tasks/{task_id}")
            out: dict[str, Any] = {"task": _task(planned, detail=True)}
            if result.get("overlaps"):
                out["overlaps_with"] = [
                    {k: e[k] for k in ("title", "start", "end") if k in e}
                    for e in result["overlaps"]
                ]
            return api.local(out)

    @mcp.tool(annotations=_IDEMPOTENT)
    async def unschedule_task(ctx: Context[Any, Any, Any], task_id: str) -> dict[str, Any]:
        """Take the due date and time off a task. The task stays open, with no day."""
        async with _session(ctx, app) as api:
            await api.delete(f"/tasks/{task_id}/schedule")
            return api.local(_task(await api.get(f"/tasks/{task_id}"), detail=True))

    @mcp.tool(annotations=_IDEMPOTENT)
    async def complete_task(ctx: Context[Any, Any, Any], task_id: str) -> dict[str, Any]:
        """Mark a task as done."""
        async with _session(ctx, app) as api:
            return api.local(_task(await api.post(f"/tasks/{task_id}/complete")))

    @mcp.tool(annotations=_IDEMPOTENT)
    async def reopen_task(ctx: Context[Any, Any, Any], task_id: str) -> dict[str, Any]:
        """Mark a done task as open again."""
        async with _session(ctx, app) as api:
            return api.local(_task(await api.post(f"/tasks/{task_id}/reopen")))

    @mcp.tool(annotations=_DELETE)
    async def delete_task(ctx: Context[Any, Any, Any], task_id: str) -> dict[str, Any]:
        """Delete a task for good, also in the task app. Ask the user first."""
        async with _session(ctx, app) as api:
            await api.delete(f"/tasks/{task_id}")
            return {"deleted": task_id}

    # -- events -----------------------------------------------------------------------

    @mcp.tool(annotations=_WRITE)
    async def create_event(
        ctx: Context[Any, Any, Any],
        title: Annotated[str, Field(min_length=1, max_length=500)],
        start: Annotated[
            str, Field(description="When it starts. A date makes an all-day event. " + _WHEN)
        ],
        end: Annotated[
            str | None,
            Field(description="When it ends. Default: an hour after the start. " + _WHEN),
        ] = None,
        calendar: Annotated[
            str | None,
            Field(
                description="The name of the calendar. Default: the calendar that the user chose."
            ),
        ] = None,
        location: str = "",
        description: str = "",
        attendees: Annotated[
            list[str] | None,
            Field(
                description="E-mail addresses to invite. The calendar app sends the invitations."
            ),
        ] = None,
    ) -> dict[str, Any]:
        """Add an event to a calendar. Use find_free_time first to pick a time that is free.

        The user gets a reminder notification before it starts, at their usual time.
        """
        async with _session(ctx, app) as api:
            begin, all_day = parse_moment(start, api.zone)
            if all_day:
                last = parse_moment(end, api.zone)[0] if end else begin
                finish = last + timedelta(days=1)
            elif end:
                finish = parse_moment(end, api.zone)[0]
            else:
                finish = begin + timedelta(hours=1)
            if finish <= begin:
                raise ToolError("The event must end after it starts.")
            connection_id, container_id = await _calendar(api, calendar)
            body: dict[str, Any] = {
                "connection_id": connection_id,
                "title": title,
                "start": iso(begin),
                "end": iso(finish),
                "all_day": all_day,
                "location": location,
                "attendees": attendees or [],
            }
            if container_id:
                body["container_id"] = container_id
            entry = await api.post("/calendar/entries", body)
            if description:
                entry = await api.patch(
                    f"/calendar/entries/{entry['id']}", {"description": description}
                )
            return api.local(entry)

    @mcp.tool(annotations=_IDEMPOTENT)
    async def update_event(
        ctx: Context[Any, Any, Any],
        event_id: Annotated[str, Field(description="The id from list_events or get_day.")],
        title: str | None = None,
        start: Annotated[str | None, Field(description="The new start. " + _WHEN)] = None,
        end: Annotated[str | None, Field(description="The new end. " + _WHEN)] = None,
        location: str | None = None,
        description: str | None = None,
    ) -> dict[str, Any]:
        """Change an event: its title, its time, its place or its description.

        To move an event, give both the new start and the new end, so that its length is right.
        """
        async with _session(ctx, app) as api:
            body: dict[str, Any] = {}
            if title is not None:
                body["title"] = title
            if start is not None:
                body["start"] = iso(parse_moment(start, api.zone)[0])
            if end is not None:
                body["end"] = iso(parse_moment(end, api.zone)[0])
            if location is not None:
                body["location"] = location
            if description is not None:
                body["description"] = description
            if not body:
                raise ToolError("Give something to change.")
            return api.local(await api.patch(f"/calendar/entries/{event_id}", body))

    @mcp.tool(annotations=_DELETE)
    async def delete_event(
        ctx: Context[Any, Any, Any],
        event_id: Annotated[str, Field(description="The id of the event.")],
    ) -> dict[str, Any]:
        """Delete an event from its calendar. Ask the user first."""
        async with _session(ctx, app) as api:
            await api.delete(f"/calendar/entries/{event_id}")
            return {"deleted": event_id}

    # -- notes ------------------------------------------------------------------------

    @mcp.tool(annotations=_WRITE)
    async def append_daily_note(
        ctx: Context[Any, Any, Any],
        text: Annotated[str, Field(min_length=1)],
        date: Annotated[str | None, Field(description=_DAY)] = None,
    ) -> dict[str, Any]:
        """Add a line to the daily note of a day. It does not change the text that is there."""
        async with _session(ctx, app) as api:
            day = parse_day(date, api.zone, api.today)
            await api.post(f"/notes/daily/{day.isoformat()}/append", {"text": text})
            return {"date": day.isoformat(), "appended": text}

    # -- reviews ----------------------------------------------------------------------

    @mcp.tool(annotations=_READ)
    async def get_weekly_review(
        ctx: Context[Any, Any, Any],
        week_of: Annotated[
            str | None,
            Field(description="Any day of the week to review. Default: the week that is running."),
        ] = None,
    ) -> dict[str, Any]:
        """Everything for the weekly review of one week, in one answer.

        It has the look-back (what was committed, what got done, what is left, the pace, the
        focus share), the work by category (goal-aligned, maintenance, off-plan), the tasks that
        are still open, the events of the week, the daily notes, the numbers of the last weeks
        for comparison, and the plan that is made for the week after. Use it to write a review
        that is based on what happened. Then submit_weekly_review saves the decisions.
        """
        async with _session(ctx, app) as api:
            monday = _week_start(parse_day(week_of, api.zone, api.today))
            following = monday + timedelta(days=7)
            state = await api.get(f"/weekly/{following.isoformat()}")
            stats = await api.get("/statistics", period="week", day=monday.isoformat())
            still_open = await api.get("/statistics/open", day=monday.isoformat())
            trends = await api.get("/weekly/trends", weeks=8)
            notes = []
            for offset in range(7):
                day = monday + timedelta(days=offset)
                view = await api.get(f"/views/day/{day.isoformat()}")
                body = (view.get("note") or {}).get("body")
                if body:
                    notes.append({"date": day.isoformat(), "note": body})
            return api.local(
                {
                    "week_start": monday.isoformat(),
                    "week_end": (monday + timedelta(days=6)).isoformat(),
                    "look_back": state.get("look_back"),
                    "look_back_note": None
                    if state.get("look_back")
                    else "No plan was committed for this week, so there is no look-back.",
                    "completed_work": stats,
                    "still_to_do": still_open,
                    "events": await _events(api, monday, 7),
                    "daily_notes": notes,
                    "trends": trends,
                    "next_week_plan": state.get("plan"),
                }
            )

    @mcp.tool(annotations=_WRITE)
    async def submit_weekly_review(
        ctx: Context[Any, Any, Any],
        week_of: Annotated[
            str | None,
            Field(description="Any day of the week that is reviewed. Default: the running week."),
        ] = None,
        reflection: Annotated[
            str, Field(description="A few sentences about how the week went, in the user's words.")
        ] = "",
        decisions: Annotated[
            list[dict[str, Any]] | None,
            Field(
                description="One entry for each milestone that is not finished: "
                "{'milestone': <name from get_weekly_review>, 'decision': 'recommit' (carry it "
                "to next week) | 'park' | 'close' (needs the milestone to be closed already) | "
                "'decide_later', 'mark_done': true to mark it finished}."
            ),
        ] = None,
    ) -> dict[str, Any]:
        """Save the weekly review: the reflection and a decision for each unfinished milestone.

        The review is saved once. Show the user the decisions and ask before you call it, because
        a recommit changes the plan of the next week. It ends the weekly review reminder.
        """
        async with _session(ctx, app) as api:
            monday = _week_start(parse_day(week_of, api.zone, api.today))
            state = await api.get(f"/weekly/{(monday + timedelta(days=7)).isoformat()}")
            back = state.get("look_back")
            if not back:
                raise ToolError("That week has no committed plan, so there is nothing to review.")
            by_name = {p["name"].casefold(): p["id"] for p in back["projects"]}
            answers = []
            for d in decisions or []:
                name = str(d.get("milestone", "")).casefold()
                if name not in by_name:
                    known = ", ".join(sorted(p["name"] for p in back["projects"]))
                    raise ToolError(
                        f"There is no milestone {d.get('milestone')!r}. Known: {known}."
                    )
                answers.append(
                    {
                        "plan_project_id": by_name[name],
                        "decision": d.get("decision"),
                        "mark_done": bool(d.get("mark_done", False)),
                    }
                )
            result = await api.post(
                f"/weekly/reviews/{back['plan_id']}",
                {"projects": answers, "reflection": reflection},
            )
            return api.local({"saved": True, "result": result})

    @mcp.tool(annotations=_READ)
    async def get_monthly_review(
        ctx: Context[Any, Any, Any],
        month: Annotated[
            str | None, Field(description="The month as YYYY-MM. Default: this month.")
        ] = None,
    ) -> dict[str, Any]:
        """Everything for the monthly review of one month, in one answer.

        It has the review of the app (the themes of the month, their key results and the
        suggestions for the next month), the focus of the month, the work by category, and the
        numbers of each week of the month. Use it to judge the month against its focus and its
        key results, and to propose the focus of the next month.
        """
        async with _session(ctx, app) as api:
            text = _month_text(month, api.today)
            first = Day.fromisoformat(f"{text}-01")
            review = await api.get(f"/monthly/{text}/review")
            focus = await api.get(f"/monthly/{text}")
            stats = await api.get("/statistics", period="month", day=first.isoformat())
            trends = await api.get("/weekly/trends", weeks=8)
            weeks = [
                w
                for w in trends.get("weeks", [])
                if first - timedelta(days=6)
                <= Day.fromisoformat(w["week_start"])
                <= first.replace(day=28) + timedelta(days=4)
            ]
            return api.local(
                {
                    "month": text,
                    "review": review,
                    "focus": focus,
                    "completed_work": stats,
                    "weeks": weeks,
                }
            )

    @mcp.tool(annotations=_WRITE)
    async def save_monthly_review(
        ctx: Context[Any, Any, Any],
        month: Annotated[str | None, Field(description="YYYY-MM. Default: this month.")] = None,
        decisions: Annotated[
            list[dict[str, Any]] | None,
            Field(
                description="One entry for each theme of the month: {'project_id': <id>, "
                "'decision': 'carry' | 'drop' | 'replace' | 'later', 'replacement_project_id': "
                "<id, for 'replace'>}. The ids are in get_monthly_review."
            ),
        ] = None,
        key_result_values: Annotated[
            list[dict[str, Any]] | None,
            Field(description="Values to record: {'key_result_id': <id>, 'value': <number>}."),
        ] = None,
        preview: Annotated[
            bool, Field(description="True: only show what saving would do. Nothing is written.")
        ] = True,
    ) -> dict[str, Any]:
        """Save the monthly review with a decision for each theme. Preview first.

        It starts as a preview (``preview`` is true) that shows the effect and writes nothing.
        Show it to the user, and call again with ``preview`` false when they agree. Saving ends
        the monthly review reminder.
        """
        async with _session(ctx, app) as api:
            text = _month_text(month, api.today)
            body = {
                "decisions": decisions or [],
                "key_result_values": key_result_values or [],
                "dry_run": preview,
            }
            result = await api.post(f"/monthly/{text}/review", body)
            return api.local({"month": text, "preview": preview, "result": result})

    @mcp.tool(annotations=_READ)
    async def get_annual_review(
        ctx: Context[Any, Any, Any],
        year: Annotated[
            int | None, Field(ge=2000, le=2100, description="Default: this year.")
        ] = None,
    ) -> dict[str, Any]:
        """Everything for the annual review of one year, in one answer.

        It has the review of the app (the goals and their key results with what they reached,
        the month by month record, what the next year can inherit) and the annual plan with its
        goals and key results. Use it to look back at the year and to propose the plan of the next.
        """
        async with _session(ctx, app) as api:
            chosen = year or api.today.year
            return api.local(
                {
                    "year": chosen,
                    "review": await api.get(f"/annual-review/{chosen}"),
                    "plan": await api.get(f"/annual/{chosen}"),
                    "work_balance": await api.get(
                        "/statistics", period="year", day=f"{chosen}-01-01"
                    ),
                }
            )

    @mcp.tool(annotations=_IDEMPOTENT)
    async def save_annual_review_note(
        ctx: Context[Any, Any, Any],
        text: Annotated[str, Field(min_length=1, max_length=2000)],
        year: Annotated[
            int | None, Field(ge=2000, le=2100, description="Default: this year.")
        ] = None,
        goal: Annotated[
            str | None,
            Field(description="The name of an annual goal. Leave it out for the note of the year."),
        ] = None,
    ) -> dict[str, Any]:
        """Write the note of the annual review: for the whole year, or for one goal.

        A note replaces the note that was there. Writing one ends the annual review reminders.
        """
        async with _session(ctx, app) as api:
            chosen = year or api.today.year
            goal_id: str | None = None
            if goal:
                plan = await api.get(f"/annual/{chosen}")
                goals = plan.get("goals", [])
                found = [g for g in goals if str(g.get("title", "")).casefold() == goal.casefold()]
                if len(found) != 1:
                    names = ", ".join(str(g.get("title")) for g in goals)
                    raise ToolError(f"There is no annual goal {goal!r}. The goals are: {names}.")
                goal_id = found[0]["id"]
            note = await api.put(
                f"/annual-review/{chosen}/notes", {"goal_id": goal_id, "body": text}
            )
            return api.local(note)

    @mcp.tool(annotations=_READ)
    async def get_trends(
        ctx: Context[Any, Any, Any],
        weeks: Annotated[int, Field(ge=1, le=52, description="How many weeks.")] = 12,
    ) -> dict[str, Any]:
        """The numbers of the last weeks, oldest first, to compare a week with the ones before.

        For each week: how many committed tasks were done, the milestones, the tasks done, and
        the share of goal-aligned, maintenance and off-plan work.
        """
        async with _session(ctx, app) as api:
            return api.local(await api.get("/weekly/trends", weeks=weeks))

    @mcp.tool(annotations=_READ)
    async def get_work_balance(
        ctx: Context[Any, Any, Any],
        period: Literal["week", "month", "year"] = "week",
        date: Annotated[str | None, Field(description=_DAY)] = None,
    ) -> dict[str, Any]:
        """The completed work of a week, a month or a year, by category and by project.

        Goal-aligned work is in a milestone of the committed plan. Maintenance is routine work.
        Everything else is off-plan.
        """
        async with _session(ctx, app) as api:
            day = parse_day(date, api.zone, api.today)
            return api.local(await api.get("/statistics", period=period, day=day.isoformat()))
