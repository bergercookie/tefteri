"""Vikunja adapter against recorded (hand-written) HTTP responses."""

import json
from collections.abc import AsyncIterator
from datetime import UTC, datetime

import httpx
import pytest
import respx

from tefteri.adapters.vikunja import VikunjaTaskBackend
from tefteri.domain.entities import Container, TaskDraft, TaskPatch
from tefteri.domain.enums import ConnectionStatus
from tefteri.domain.errors import (
    AuthExpired,
    BackendError,
    BackendUnavailable,
    NotSaved,
    RemoteConflict,
)

BASE = "https://vikunja.test/api/v1"


def task_json(**over: object) -> dict[str, object]:
    data: dict[str, object] = {
        "id": 7,
        "project_id": 2,
        "title": "Write report",
        "description": "",
        "done": False,
        "due_date": "0001-01-01T00:00:00Z",
        "start_date": "0001-01-01T00:00:00Z",
        "end_date": "0001-01-01T00:00:00Z",
        "updated": "2026-11-01T10:00:00Z",
    }
    data.update(over)
    return data


class _Stored:
    """A Vikunja task that keeps what is written to it and answers reads with it.

    The adapter reads a task back after each write, so a mock of the write alone is not
    enough: the next read must show the change.
    """

    def __init__(self, **fields: object) -> None:
        self.data = task_json(**fields)
        self.posts: list[dict[str, object]] = []

    def mount(self, task_id: int = 7) -> "_Stored":
        respx.get(f"{BASE}/tasks/{task_id}").mock(side_effect=self._read)
        respx.post(f"{BASE}/tasks/{task_id}").mock(side_effect=self._write)
        return self

    def _read(self, request: httpx.Request) -> httpx.Response:
        return httpx.Response(200, json=self.data)

    def _write(self, request: httpx.Request) -> httpx.Response:
        body = json.loads(request.content)
        self.posts.append(body)
        stamp = f"2026-11-04T10:00:{len(self.posts):02d}Z"
        self.data = {**body, "updated": stamp}
        return httpx.Response(200, json=self.data)


@pytest.fixture
async def backend() -> AsyncIterator[VikunjaTaskBackend]:
    async with httpx.AsyncClient() as client:
        yield VikunjaTaskBackend(client, "https://vikunja.test/", "tok")


@respx.mock
async def test_lists_projects_and_tasks_with_auth_header(backend: VikunjaTaskBackend) -> None:
    projects = respx.get(f"{BASE}/projects").respond(json=[{"id": 2, "title": "Work"}])
    tasks = respx.get(f"{BASE}/projects/2/tasks").respond(json=[task_json()])
    containers = await backend.list_containers()
    assert containers == [Container("2", "Work")]
    page = await backend.list_tasks(containers[0], None)
    assert page.items[0].title == "Write report"
    assert page.items[0].due_at is None
    assert page.items[0].version.startswith("2026-11-01T10:00:00Z#")
    assert projects.calls[0].request.headers["authorization"] == "Bearer tok"
    assert tasks.call_count == 1


@respx.mock
async def test_saved_filters_are_not_containers(backend: VikunjaTaskBackend) -> None:
    respx.get(f"{BASE}/projects").respond(
        json=[{"id": 2, "title": "Work"}, {"id": -2, "title": "My Open Tasks"}]
    )
    assert await backend.list_containers() == [Container("2", "Work")]


@respx.mock
async def test_subprojects_name_their_parent_and_can_be_created(
    backend: VikunjaTaskBackend,
) -> None:
    respx.get(f"{BASE}/projects").respond(
        json=[
            {"id": 2, "title": "Work", "parent_project_id": 0},
            {"id": 5, "title": "Launch", "parent_project_id": 2},
        ]
    )
    assert await backend.list_containers() == [
        Container("2", "Work"),
        Container("5", "Launch", "2"),
    ]
    create = respx.put(f"{BASE}/projects")
    create.side_effect = [
        httpx.Response(201, json={"id": 9, "title": "Docs", "parent_project_id": 2}),
        httpx.Response(201, json={"id": 10, "title": "Top"}),
    ]
    made = await backend.create_container("Docs", Container("2", "Work"))
    assert made == Container("9", "Docs", "2")
    assert json.loads(create.calls[0].request.content) == {"title": "Docs", "parent_project_id": 2}
    assert await backend.create_container("Top", None) == Container("10", "Top")
    assert json.loads(create.calls[1].request.content) == {"title": "Top"}


@respx.mock
async def test_archive_sets_the_flag_and_checks_that_it_stuck(
    backend: VikunjaTaskBackend,
) -> None:
    project = {"id": 2, "title": "Work", "is_archived": False}
    reads = respx.get(f"{BASE}/projects/2")
    reads.side_effect = [
        httpx.Response(200, json=project),
        httpx.Response(200, json={**project, "is_archived": True}),
    ]
    write = respx.post(f"{BASE}/projects/2").respond(json={**project, "is_archived": True})
    await backend.archive_container(Container("2", "Work"))
    assert json.loads(write.calls[0].request.content)["is_archived"] is True
    assert json.loads(write.calls[0].request.content)["title"] == "Work"  # nothing else changes


@respx.mock
async def test_archive_that_vikunja_did_not_keep_is_an_error(
    backend: VikunjaTaskBackend,
) -> None:
    project = {"id": 2, "title": "Work", "is_archived": False}
    respx.get(f"{BASE}/projects/2").respond(json=project)
    respx.post(f"{BASE}/projects/2").respond(json=project)
    with pytest.raises(NotSaved):
        await backend.archive_container(Container("2", "Work"))


@respx.mock
async def test_pagination(backend: VikunjaTaskBackend) -> None:
    first = [task_json(id=i) for i in range(50)]
    route = respx.get(f"{BASE}/projects/2/tasks")
    route.side_effect = [
        httpx.Response(200, json=first),
        httpx.Response(200, json=[task_json(id=99)]),
    ]
    page = await backend.list_tasks(Container("2", "Work"), None)
    assert len(page.items) == 51


@respx.mock
async def test_create_update_and_stale_version(backend: VikunjaTaskBackend) -> None:
    respx.put(f"{BASE}/projects/2/tasks").respond(json=task_json())
    created = await backend.create_task(TaskDraft("2", "Write report"))
    assert created.remote_id == "7"

    store = _Stored().mount()
    updated = await backend.update_task("7", TaskPatch(title="Report"), created.version)
    assert updated.title == "Report"
    assert store.posts[0]["title"] == "Report"

    with pytest.raises(RemoteConflict):
        await backend.update_task("7", TaskPatch(title="x"), "an-older-version")


@respx.mock
async def test_set_planned_time_writes_only_the_due_date(backend: VikunjaTaskBackend) -> None:
    store = _Stored().mount()
    due = datetime(2026, 11, 2, 10, tzinfo=UTC)
    current = await backend.get_task("7")
    task = await backend.set_planned_time("7", due, False, current.version)
    assert task.due_at == due and not task.all_day
    body = store.posts[0]
    assert body["due_date"] == "2026-11-02T10:00:00Z"
    # constitution VII: the start and end dates are not tefteri's planning dates
    assert body["start_date"] == "0001-01-01T00:00:00Z"
    assert body["end_date"] == "0001-01-01T00:00:00Z"


@respx.mock
async def test_set_planned_time_keeps_foreign_start_and_end_dates(
    backend: VikunjaTaskBackend,
) -> None:
    mine = {"start_date": "2026-10-01T08:00:00Z", "end_date": "2026-10-02T08:00:00Z"}
    store = _Stored(**mine).mount()
    current = await backend.get_task("7")
    await backend.set_planned_time(
        "7", datetime(2026, 11, 2, 10, tzinfo=UTC), False, current.version
    )
    body = store.posts[0]
    assert body["start_date"] == mine["start_date"] and body["end_date"] == mine["end_date"]


@respx.mock
async def test_set_planned_time_clears_the_due_date(backend: VikunjaTaskBackend) -> None:
    store = _Stored(due_date="2026-11-02T10:00:00Z").mount()
    current = await backend.get_task("7")
    task = await backend.set_planned_time("7", None, False, current.version)
    assert task.due_at is None
    assert store.posts[0]["due_date"] == "0001-01-01T00:00:00Z"


@respx.mock
async def test_date_only_due_is_00_00_in_the_users_time_zone() -> None:
    async with httpx.AsyncClient() as client:
        athens = VikunjaTaskBackend(client, "https://vikunja.test/", "tok", "Europe/Athens")
        store = _Stored().mount()
        current = await athens.get_task("7")
        # the caller may pass any instant on the day; the adapter writes local midnight
        noon = datetime(2026, 11, 4, 12, tzinfo=UTC)
        task = await athens.set_planned_time("7", noon, True, current.version)
    assert store.posts[0]["due_date"] == "2026-11-03T22:00:00Z"  # 00:00 on 4 Nov, UTC+2
    assert task.all_day and task.due_at == datetime(2026, 11, 3, 22, tzinfo=UTC)


@respx.mock
async def test_a_due_time_of_00_00_local_reads_as_all_day() -> None:
    async with httpx.AsyncClient() as client:
        athens = VikunjaTaskBackend(client, "https://vikunja.test/", "tok", "Europe/Athens")
        respx.get(f"{BASE}/tasks/7").respond(json=task_json(due_date="2026-11-03T22:00:00Z"))
        respx.get(f"{BASE}/tasks/8").respond(json=task_json(id=8, due_date="2026-11-03T22:30:00Z"))
        assert (await athens.get_task("7")).all_day
        assert not (await athens.get_task("8")).all_day


@respx.mock
async def test_start_and_end_dates_are_not_read(backend: VikunjaTaskBackend) -> None:
    respx.get(f"{BASE}/tasks/7").respond(
        json=task_json(start_date="2026-11-02T09:00:00Z", end_date="2026-11-02T10:00:00Z")
    )
    task = await backend.get_task("7")
    assert task.due_at is None and not task.all_day


@respx.mock
async def test_complete_and_delete(backend: VikunjaTaskBackend) -> None:
    _Stored().mount()
    assert (await backend.complete_task("7")).done
    delete = respx.delete(f"{BASE}/tasks/7").respond(json={"message": "ok"})
    await backend.delete_task("7")
    assert delete.called


@respx.mock
async def test_error_mapping(backend: VikunjaTaskBackend) -> None:
    respx.get(f"{BASE}/projects").respond(401)
    with pytest.raises(AuthExpired):
        await backend.list_containers()
    health = await backend.check_connection()
    assert health.status is ConnectionStatus.NEEDS_ATTENTION

    respx.get(f"{BASE}/projects").mock(side_effect=httpx.ConnectError("down"))
    with pytest.raises(BackendUnavailable):
        await backend.list_containers()
    assert (await backend.check_connection()).status is ConnectionStatus.ERROR

    respx.get(f"{BASE}/projects").respond(503)
    with pytest.raises(BackendUnavailable):
        await backend.list_containers()


@respx.mock
async def test_version_detects_writes_within_the_same_second(backend: VikunjaTaskBackend) -> None:
    # ``updated`` has second resolution: a remote edit in the same second must still conflict.
    respx.get(f"{BASE}/tasks/7").respond(json=task_json())
    seen = await backend.get_task("7")
    respx.get(f"{BASE}/tasks/7").respond(json=task_json(title="Edited in Vikunja"))
    with pytest.raises(RemoteConflict):
        await backend.update_task("7", TaskPatch(title="x"), seen.version)


@respx.mock
async def test_invalid_data_is_not_a_conflict(backend: VikunjaTaskBackend) -> None:
    # Vikunja answers 412 "Invalid Data" for validation errors; that is no version conflict.
    respx.put(f"{BASE}/projects/2/tasks").respond(
        412, json={"code": 2002, "message": "Invalid Data", "invalid_fields": ["title"]}
    )
    with pytest.raises(BackendError) as raised:
        await backend.create_task(TaskDraft("2", ""))
    assert not isinstance(raised.value, RemoteConflict)


class _RealisticVikunja:
    """A Vikunja whose update answer is formatted differently from a later read.

    The update answer carries the in-memory task: a sub-second ``updated`` stamp and the
    due date in the server's offset. A later read gives what the database stored: whole
    seconds and UTC. A client that builds the version of a task from the update answer
    then sees a "conflict" when it writes the same task again.
    """

    def __init__(self) -> None:
        self.stored = task_json(updated="2026-11-04T10:00:00Z")
        self.writes = 0

    def read(self, request: httpx.Request) -> httpx.Response:
        return httpx.Response(200, json=self.stored)

    def write(self, request: httpx.Request) -> httpx.Response:
        body = json.loads(request.content)
        self.writes += 1
        stamp = f"2026-11-04T10:00:0{self.writes}"
        self.stored = {**body, "updated": f"{stamp}Z"}
        due = body["due_date"]
        shown = {"due_date": due.replace("Z", "+02:00")} if due != "0001-01-01T00:00:00Z" else {}
        return httpx.Response(200, json={**self.stored, **shown, "updated": f"{stamp}.482913Z"})


@respx.mock
async def test_the_same_task_can_be_planned_twice_in_a_row(backend: VikunjaTaskBackend) -> None:
    server = _RealisticVikunja()
    respx.get(f"{BASE}/tasks/7").mock(side_effect=server.read)
    respx.post(f"{BASE}/tasks/7").mock(side_effect=server.write)

    first = await backend.get_task("7")
    planned = await backend.set_planned_time(
        "7", datetime(2026, 11, 4, 15, tzinfo=UTC), False, first.version
    )
    # the user drags the block again, with the version that the first write returned
    moved = await backend.set_planned_time(
        "7", datetime(2026, 11, 4, 17, tzinfo=UTC), False, planned.version
    )
    assert moved.due_at == datetime(2026, 11, 4, 17, tzinfo=UTC)
    cleared = await backend.set_planned_time("7", None, False, moved.version)
    assert cleared.due_at is None
    assert server.writes == 3


@respx.mock
async def test_a_real_change_in_the_app_is_still_a_conflict(
    backend: VikunjaTaskBackend,
) -> None:
    server = _RealisticVikunja()
    respx.get(f"{BASE}/tasks/7").mock(side_effect=server.read)
    respx.post(f"{BASE}/tasks/7").mock(side_effect=server.write)
    first = await backend.get_task("7")
    planned = await backend.set_planned_time(
        "7", datetime(2026, 11, 4, 15, tzinfo=UTC), False, first.version
    )
    server.stored = {
        **server.stored,
        "title": "Renamed in the app",
        "updated": "2026-11-04T11:00:00Z",
    }
    with pytest.raises(RemoteConflict):
        await backend.set_planned_time(
            "7", datetime(2026, 11, 4, 17, tzinfo=UTC), False, planned.version
        )


class _IgnoresDueDate(_Stored):
    """A Vikunja that answers 200 to a due date change but keeps the old date."""

    def _write(self, request: httpx.Request) -> httpx.Response:
        body = json.loads(request.content)
        body["due_date"] = self.data["due_date"]
        self.posts.append(body)
        self.data = {**body, "updated": f"2026-11-04T10:00:{len(self.posts):02d}Z"}
        return httpx.Response(200, json=self.data)


@respx.mock
async def test_a_due_date_that_vikunja_does_not_keep_is_an_error(
    backend: VikunjaTaskBackend,
) -> None:
    store = _IgnoresDueDate(due_date="2026-11-04T09:00:00Z").mount()
    current = await backend.get_task("7")
    with pytest.raises(NotSaved, match="Vikunja has 2026-11-04 09:00:00"):
        await backend.set_planned_time(
            "7", datetime(2026, 11, 5, 11, tzinfo=UTC), False, current.version
        )
    assert len(store.posts) == 1  # the write was tried once, not repeated


@respx.mock
async def test_clearing_a_due_date_that_vikunja_keeps_is_an_error(
    backend: VikunjaTaskBackend,
) -> None:
    _IgnoresDueDate(due_date="2026-11-04T09:00:00Z").mount()
    current = await backend.get_task("7")
    with pytest.raises(NotSaved):
        await backend.set_planned_time("7", None, False, current.version)


def test_a_version_is_the_same_for_every_form_of_the_same_task() -> None:
    from tefteri.adapters.vikunja.adapter import _version  # noqa: PLC0415

    # Recorded from Vikunja v2.7.1: the create answer and a later read of the same task.
    created = task_json(updated="2026-11-03T21:04:25.982515748Z", due_date="2026-11-04T09:00:00Z")
    read = task_json(updated="2026-11-03T21:04:25Z", due_date="2026-11-04T09:00:00Z")
    assert _version(created) == _version(read)
    # the same instant in another offset is the same task
    offset = task_json(updated="2026-11-03T23:04:25+02:00", due_date="2026-11-04T11:00:00+02:00")
    assert _version(offset) == _version(read)
    # a real change is still a different version, also within the same second
    assert _version(task_json(updated="2026-11-03T21:04:25Z", title="x")) != _version(read)
    assert _version(
        task_json(updated="2026-11-03T21:04:25Z", due_date="2026-11-05T09:00:00Z")
    ) != _version(read)
    # a stamp that is not a timestamp is kept as it is
    assert _version(task_json(updated="soon")).startswith("soon#")


@respx.mock
async def test_a_task_that_tefteri_just_created_can_be_moved(backend: VikunjaTaskBackend) -> None:
    """Real Vikunja: the create answer has a nanosecond stamp; the first move used to conflict."""
    created_json = task_json(updated="2026-11-03T21:04:25.982515748Z")
    respx.put(f"{BASE}/projects/2/tasks").respond(json=created_json)
    created = await backend.create_task(TaskDraft("2", "Write report"))
    store = _Stored(updated="2026-11-03T21:04:25Z").mount()
    moved = await backend.set_planned_time(
        "7", datetime(2026, 11, 4, 15, tzinfo=UTC), False, created.version
    )
    assert moved.due_at == datetime(2026, 11, 4, 15, tzinfo=UTC)
    assert len(store.posts) == 1


@respx.mock
async def test_reads_label_names_and_reopens(backend: VikunjaTaskBackend) -> None:
    stored = _Stored(
        done=True,
        labels=[{"id": 1, "title": "errand"}, {"id": 2, "title": "home"}, {"id": 3}],
    ).mount()
    task = await backend.get_task("7")
    assert task.labels == ("errand", "home")

    reopened = await backend.reopen_task("7")
    assert not reopened.done
    assert stored.posts[-1]["done"] is False
