"""Shared adapter contract suite, parametrised over every backend implementation.

Adapters register a factory in ``TASK_FACTORIES``/``CALENDAR_FACTORIES``/``NOTE_FACTORIES``
(from their own test modules or conftest) and are then held to the same behaviour.
"""

from collections.abc import Callable
from datetime import UTC, date, datetime, timedelta

import pytest

from tefteri.domain.entities import (
    EntryDraft,
    EntryPatch,
    NoteDraft,
    NotePatch,
    TaskDraft,
    TaskPatch,
)
from tefteri.domain.errors import BackendUnavailable, RemoteConflict
from tefteri.domain.ports import CalendarBackend, NoteBackend, TaskBackend
from tests.fakes.memory import FakeCalendarBackend, FakeNoteBackend, FakeTaskBackend

TASK_FACTORIES: dict[str, Callable[[], TaskBackend]] = {"fake": FakeTaskBackend}
CALENDAR_FACTORIES: dict[str, Callable[[], CalendarBackend]] = {"fake": FakeCalendarBackend}
NOTE_FACTORIES: dict[str, Callable[[], NoteBackend]] = {"fake": FakeNoteBackend}

NOW = datetime(2026, 11, 2, 9, 0, tzinfo=UTC)


@pytest.fixture(params=sorted(TASK_FACTORIES))
def tasks(request: pytest.FixtureRequest) -> TaskBackend:
    return TASK_FACTORIES[request.param]()


@pytest.fixture(params=sorted(CALENDAR_FACTORIES))
def calendar(request: pytest.FixtureRequest) -> CalendarBackend:
    return CALENDAR_FACTORIES[request.param]()


@pytest.fixture(params=sorted(NOTE_FACTORIES))
def notes(request: pytest.FixtureRequest) -> NoteBackend:
    return NOTE_FACTORIES[request.param]()


async def test_task_crud_and_schedule(tasks: TaskBackend) -> None:
    container = (await tasks.list_containers())[0]
    task = await tasks.create_task(TaskDraft(container.remote_id, "Write report"))
    page = await tasks.list_tasks(container, None)
    assert [t.remote_id for t in page.items] == [task.remote_id]

    renamed = await tasks.update_task(task.remote_id, TaskPatch(title="Write"), task.version)
    assert renamed.title == "Write"

    scheduled = await tasks.set_schedule(
        task.remote_id, NOW, NOW + timedelta(hours=1), renamed.version
    )
    assert scheduled.scheduled_start == NOW

    done = await tasks.complete_task(task.remote_id)
    assert done.done
    await tasks.delete_task(task.remote_id)
    assert (await tasks.list_tasks(container, None)).items == []


async def test_task_stale_version_raises_conflict(tasks: TaskBackend) -> None:
    container = (await tasks.list_containers())[0]
    task = await tasks.create_task(TaskDraft(container.remote_id, "x"))
    await tasks.update_task(task.remote_id, TaskPatch(title="y"), task.version)
    with pytest.raises(RemoteConflict):
        await tasks.update_task(task.remote_id, TaskPatch(title="z"), task.version)


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
    appended = await notes.append(daily.remote_id, "met Sam")
    assert "met Sam" in appended.body
    custom = await notes.create_note(NoteDraft("Process"))
    edited = await notes.update_note(custom.remote_id, NotePatch(body="steps"), custom.version)
    assert edited.body == "steps"
    with pytest.raises(RemoteConflict):
        await notes.update_note(custom.remote_id, NotePatch(body="x"), custom.version)
    await notes.delete_note(custom.remote_id)


async def test_unavailable_backend_raises(tasks: TaskBackend) -> None:
    if not hasattr(tasks, "unavailable"):
        pytest.skip("adapter has no failure switch; covered by recorded-HTTP tests")
    tasks.unavailable = True
    with pytest.raises(BackendUnavailable):
        await tasks.list_containers()
