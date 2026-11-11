"""Shared adapter contract suite, parametrised over every backend implementation.

Each port has a factory table (``TASK_FACTORIES``/``CALENDAR_FACTORIES``/``NOTE_FACTORIES``).
A factory gets the active ``respx`` router and a fresh ``httpx.AsyncClient`` and returns the
backend under test plus the switches that simulate an outage or revoked credentials. The real
adapters run against stateful fake servers (``tests.fakes.http``); the in-memory fakes are
their own switches. A new adapter only adds one entry to its port's table.
"""

from collections.abc import AsyncIterator, Callable
from dataclasses import dataclass
from datetime import UTC, date, datetime, timedelta
from typing import Any, Protocol

import httpx
import pytest
import respx

from tefteri.adapters.google_calendar import GoogleCalendarBackend
from tefteri.adapters.trilium import TriliumNoteBackend
from tefteri.adapters.vikunja import VikunjaTaskBackend
from tefteri.domain.entities import (
    EntryDraft,
    EntryPatch,
    NoteDraft,
    NotePatch,
    TaskDraft,
    TaskPatch,
)
from tefteri.domain.enums import Capability, ConnectionStatus
from tefteri.domain.errors import AuthExpired, BackendUnavailable, NotSaved, RemoteConflict
from tefteri.domain.ports import Backend, CalendarBackend, NoteBackend, TaskBackend
from tests.fakes.http import FakeGoogleCalendar, FakeTrilium, FakeVikunja
from tests.fakes.memory import FakeCalendarBackend, FakeNoteBackend, FakeTaskBackend

NOW = datetime(2026, 11, 2, 9, 0, tzinfo=UTC)


class FaultSwitches(Protocol):
    """Simulated failures of the app behind a backend."""

    unavailable: bool
    auth_expired: bool


@dataclass(frozen=True)
class Subject[B: Backend]:
    """A backend under test and the switches of the app it talks to."""

    backend: B
    switches: FaultSwitches


# (respx router, HTTP client) -> subject. The router is untyped (respx ships no stubs).
type Factory[B: Backend] = Callable[[Any, httpx.AsyncClient], Subject[B]]


def _vikunja(router: Any, client: httpx.AsyncClient) -> Subject[TaskBackend]:
    server = FakeVikunja()
    server.mount(router)
    return Subject(VikunjaTaskBackend(client, server.base_url, server.token), server)


def _google_calendar(router: Any, client: httpx.AsyncClient) -> Subject[CalendarBackend]:
    server = FakeGoogleCalendar()
    server.mount(router)
    backend = GoogleCalendarBackend(
        client, server.client_id, server.client_secret, server.refresh_token
    )
    return Subject(backend, server)


def _trilium(router: Any, client: httpx.AsyncClient) -> Subject[NoteBackend]:
    server = FakeTrilium()
    server.mount(router)
    return Subject(TriliumNoteBackend(client, server.base_url, server.token), server)


def _memory_tasks(_router: Any, _client: httpx.AsyncClient) -> Subject[TaskBackend]:
    backend = FakeTaskBackend()
    return Subject(backend, backend)


def _memory_calendar(_router: Any, _client: httpx.AsyncClient) -> Subject[CalendarBackend]:
    backend = FakeCalendarBackend()
    return Subject(backend, backend)


def _memory_notes(_router: Any, _client: httpx.AsyncClient) -> Subject[NoteBackend]:
    backend = FakeNoteBackend()
    return Subject(backend, backend)


TASK_FACTORIES: dict[str, Factory[TaskBackend]] = {"fake": _memory_tasks, "vikunja": _vikunja}
CALENDAR_FACTORIES: dict[str, Factory[CalendarBackend]] = {
    "fake": _memory_calendar,
    "google_calendar": _google_calendar,
}
NOTE_FACTORIES: dict[str, Factory[NoteBackend]] = {"fake": _memory_notes, "trilium": _trilium}
ALL_FACTORIES: dict[str, Factory[Backend]] = {
    **{f"tasks-{name}": f for name, f in TASK_FACTORIES.items()},
    **{f"calendar-{name}": f for name, f in CALENDAR_FACTORIES.items()},
    **{f"notes-{name}": f for name, f in NOTE_FACTORIES.items()},
}


@pytest.fixture
async def http() -> AsyncIterator[tuple[Any, httpx.AsyncClient]]:
    # Unmatched requests fail the test, so nothing ever leaves the process.
    async with httpx.AsyncClient() as client:
        with respx.mock(assert_all_mocked=True, assert_all_called=False) as router:
            yield router, client


@pytest.fixture(params=sorted(TASK_FACTORIES))
def tasks(request: pytest.FixtureRequest, http: tuple[Any, httpx.AsyncClient]) -> TaskBackend:
    return TASK_FACTORIES[request.param](*http).backend


@pytest.fixture(params=sorted(CALENDAR_FACTORIES))
def calendar(
    request: pytest.FixtureRequest, http: tuple[Any, httpx.AsyncClient]
) -> CalendarBackend:
    return CALENDAR_FACTORIES[request.param](*http).backend


@pytest.fixture(params=sorted(NOTE_FACTORIES))
def notes(request: pytest.FixtureRequest, http: tuple[Any, httpx.AsyncClient]) -> NoteBackend:
    return NOTE_FACTORIES[request.param](*http).backend


@pytest.fixture(params=sorted(ALL_FACTORIES))
def subject(
    request: pytest.FixtureRequest, http: tuple[Any, httpx.AsyncClient]
) -> Subject[Backend]:
    return ALL_FACTORIES[request.param](*http)


async def test_task_crud_and_schedule(tasks: TaskBackend) -> None:
    container = (await tasks.list_containers())[0]
    task = await tasks.create_task(TaskDraft(container.remote_id, "Write report"))
    page = await tasks.list_tasks(container, None)
    assert [t.remote_id for t in page.items] == [task.remote_id]

    renamed = await tasks.update_task(task.remote_id, TaskPatch(title="Write"), task.version)
    assert renamed.title == "Write"
    assert (await tasks.get_task(task.remote_id)).title == "Write"

    # Planning is optional; the services refuse it for backends without task times.
    if Capability.TASK_TIME in tasks.capabilities():
        due = NOW + timedelta(hours=1)
        planned = await tasks.set_planned_time(task.remote_id, due, False, renamed.version)
        assert planned.due_at == due and not planned.all_day
        midnight = datetime(2026, 11, 3, tzinfo=UTC)  # the subject's time zone is UTC
        dated = await tasks.set_planned_time(task.remote_id, midnight, True, planned.version)
        assert dated.due_at == midnight and dated.all_day
        cleared = await tasks.set_planned_time(task.remote_id, None, False, dated.version)
        assert cleared.due_at is None and not cleared.all_day
        with pytest.raises(RemoteConflict):
            await tasks.set_planned_time(task.remote_id, due, False, planned.version)
        renamed = cleared

    done = await tasks.complete_task(task.remote_id)
    assert done.done
    await tasks.delete_task(task.remote_id)
    assert (await tasks.list_tasks(container, None)).items == []


async def test_task_reminder_before_the_due_time(tasks: TaskBackend) -> None:
    if Capability.TASK_REMINDERS not in tasks.capabilities():
        pytest.skip("the app has no reminders")
    container = (await tasks.list_containers())[0]
    task = await tasks.create_task(TaskDraft(container.remote_id, "Call Sam"))
    planned = await tasks.set_planned_time(
        task.remote_id, NOW + timedelta(hours=2), False, task.version
    )
    assert await tasks.get_reminder(task.remote_id) is None

    reminded = await tasks.set_reminder(task.remote_id, 15)
    assert await tasks.get_reminder(task.remote_id) == 15
    assert reminded.due_at == planned.due_at

    # Other edits keep the reminder, and a new offset replaces the old one.
    await tasks.update_task(task.remote_id, TaskPatch(title="Call"), reminded.version)
    assert await tasks.get_reminder(task.remote_id) == 15
    again = await tasks.set_reminder(task.remote_id, 60)
    assert await tasks.get_reminder(task.remote_id) == 60
    await tasks.set_planned_time(task.remote_id, NOW + timedelta(hours=5), False, again.version)
    assert await tasks.get_reminder(task.remote_id) == 60  # it follows the due time

    await tasks.set_reminder(task.remote_id, None)
    assert await tasks.get_reminder(task.remote_id) is None


async def test_task_stale_version_raises_conflict(tasks: TaskBackend) -> None:
    container = (await tasks.list_containers())[0]
    task = await tasks.create_task(TaskDraft(container.remote_id, "x"))
    await tasks.update_task(task.remote_id, TaskPatch(title="y"), task.version)
    with pytest.raises(RemoteConflict):
        await tasks.update_task(task.remote_id, TaskPatch(title="z"), task.version)


async def test_task_rename_and_restore_a_project(tasks: TaskBackend) -> None:
    if Capability.RENAME_PROJECTS not in tasks.capabilities():
        pytest.skip("the app cannot rename projects")
    created = await tasks.create_container("Garden", None)
    sub = await tasks.create_container("Beds", created)

    renamed = await tasks.rename_container(created, "Allotment")
    assert (renamed.remote_id, renamed.name) == (created.remote_id, "Allotment")
    listed = {c.remote_id: c for c in await tasks.list_containers()}
    assert listed[created.remote_id].name == "Allotment"
    assert listed[sub.remote_id].parent_id == created.remote_id  # the tree is kept

    if Capability.RESTORE_PROJECTS in tasks.capabilities():
        await tasks.archive_container(sub)
        assert sub.remote_id not in {c.remote_id for c in await tasks.list_containers()}
        await tasks.restore_container(sub)
        back = {c.remote_id: c for c in await tasks.list_containers()}
        assert back[sub.remote_id].name == "Beds"
        assert back[sub.remote_id].parent_id == created.remote_id


@pytest.mark.parametrize("name", sorted(TASK_FACTORIES))
async def test_a_refused_rename_or_restore_changes_nothing(
    name: str, http: tuple[Any, httpx.AsyncClient]
) -> None:
    subject = TASK_FACTORIES[name](*http)
    tasks = subject.backend
    if Capability.RENAME_PROJECTS not in tasks.capabilities():
        pytest.skip("the app cannot rename projects")
    created = await tasks.create_container("Garden", None)
    await tasks.create_container("Other", None)
    subject.switches.unavailable = True
    with pytest.raises(BackendUnavailable):
        await tasks.rename_container(created, "Allotment")
    with pytest.raises(BackendUnavailable):
        await tasks.restore_container(created)
    subject.switches.unavailable = False
    names = {c.remote_id: c.name for c in await tasks.list_containers()}
    assert names[created.remote_id] == "Garden"


async def test_a_task_moves_to_another_project_and_keeps_its_identity(
    tasks: TaskBackend,
) -> None:
    if Capability.MOVE_TASKS not in tasks.capabilities():
        pytest.skip("the app cannot move tasks")
    first = (await tasks.list_containers())[0]
    other = await tasks.create_container("Garden", None)
    task = await tasks.create_task(TaskDraft(first.remote_id, "Rake leaves"))
    moved = await tasks.move_task(task.remote_id, other, task.version)
    assert (moved.remote_id, moved.title) == (task.remote_id, "Rake leaves")
    assert moved.container_id == other.remote_id
    assert [t.remote_id for t in (await tasks.list_tasks(other, None)).items] == [task.remote_id]
    assert (await tasks.list_tasks(first, None)).items == []
    assert (await tasks.get_task(task.remote_id)).container_id == other.remote_id
    # The new version is the one the next write needs.
    back = await tasks.move_task(task.remote_id, first, moved.version)
    assert back.container_id == first.remote_id


@pytest.mark.parametrize("name", sorted(TASK_FACTORIES))
async def test_a_refused_move_raises_and_changes_nothing(
    name: str, http: tuple[Any, httpx.AsyncClient]
) -> None:
    subject = TASK_FACTORIES[name](*http)
    tasks = subject.backend
    if Capability.MOVE_TASKS not in tasks.capabilities():
        pytest.skip("the app cannot move tasks")
    first = (await tasks.list_containers())[0]
    other = await tasks.create_container("Garden", None)
    task = await tasks.create_task(TaskDraft(first.remote_id, "Rake leaves"))
    subject.switches.unavailable = True
    with pytest.raises(BackendUnavailable):
        await tasks.move_task(task.remote_id, other, task.version)
    subject.switches.unavailable = False
    assert (await tasks.get_task(task.remote_id)).container_id == first.remote_id
    # A move that the app keeps from happening is an error too, not a silent success.
    switches: Any = subject.switches
    switches.ignore_moves = True
    with pytest.raises(NotSaved):
        await tasks.move_task(task.remote_id, other, task.version)
    switches.ignore_moves = False
    assert (await tasks.get_task(task.remote_id)).container_id == first.remote_id


async def test_a_move_with_a_stale_version_raises_conflict(tasks: TaskBackend) -> None:
    if Capability.MOVE_TASKS not in tasks.capabilities():
        pytest.skip("the app cannot move tasks")
    first = (await tasks.list_containers())[0]
    other = await tasks.create_container("Garden", None)
    task = await tasks.create_task(TaskDraft(first.remote_id, "Rake leaves"))
    await tasks.update_task(task.remote_id, TaskPatch(title="Rake"), task.version)
    with pytest.raises(RemoteConflict):
        await tasks.move_task(task.remote_id, other, task.version)
    assert (await tasks.get_task(task.remote_id)).container_id == first.remote_id


async def test_calendar_crud(calendar: CalendarBackend) -> None:
    container = (await calendar.list_containers())[0]
    entry = await calendar.create_entry(
        EntryDraft(container.remote_id, "Standup", NOW, NOW + timedelta(minutes=15))
    )
    page = await calendar.list_entries(
        container, NOW - timedelta(days=1), NOW + timedelta(days=1), None
    )
    assert [e.remote_id for e in page.items] == [entry.remote_id]
    assert (await calendar.get_entry(entry.remote_id)).title == "Standup"
    updated = await calendar.update_entry(entry.remote_id, EntryPatch(title="Sync"), entry.version)
    assert updated.title == "Sync"
    with pytest.raises(RemoteConflict):
        await calendar.update_entry(entry.remote_id, EntryPatch(title="again"), entry.version)
    await calendar.delete_entry(entry.remote_id)


async def test_notes_daily_and_append(notes: NoteBackend) -> None:
    day = date(2026, 11, 2)
    daily = await notes.get_or_create_daily(day)
    assert (await notes.get_or_create_daily(day)).remote_id == daily.remote_id
    # Appending is optional; the services report it as unsupported otherwise.
    if Capability.NOTE_APPEND in notes.capabilities():
        appended = await notes.append(daily.remote_id, "met Sam")
        assert "met Sam" in appended.body
    custom = await notes.create_note(NoteDraft("Process"))
    edited = await notes.update_note(custom.remote_id, NotePatch(body="steps"), custom.version)
    assert edited.body == "steps"
    with pytest.raises(RemoteConflict):
        await notes.update_note(custom.remote_id, NotePatch(body="x"), custom.version)
    await notes.delete_note(custom.remote_id)


async def test_unavailable_backend_raises(subject: Subject[Backend]) -> None:
    assert (await subject.backend.check_connection()).status is ConnectionStatus.OK
    subject.switches.unavailable = True
    with pytest.raises(BackendUnavailable):
        await subject.backend.list_containers()
    assert (await subject.backend.check_connection()).status is ConnectionStatus.ERROR


async def test_revoked_credentials_raise_auth_expired(subject: Subject[Backend]) -> None:
    await subject.backend.list_containers()  # signed in (and any access token cached)
    subject.switches.auth_expired = True
    with pytest.raises(AuthExpired):
        await subject.backend.list_containers()
    health = await subject.backend.check_connection()
    assert health.status is ConnectionStatus.NEEDS_ATTENTION
