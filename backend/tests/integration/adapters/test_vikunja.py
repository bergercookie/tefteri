"""Vikunja adapter against recorded (hand-written) HTTP responses."""

from collections.abc import AsyncIterator
from datetime import UTC, datetime

import httpx
import pytest
import respx

from tefteri.adapters.vikunja import VikunjaTaskBackend
from tefteri.domain.entities import Container, TaskDraft, TaskPatch
from tefteri.domain.enums import ConnectionStatus
from tefteri.domain.errors import AuthExpired, BackendError, BackendUnavailable, RemoteConflict

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

    respx.get(f"{BASE}/tasks/7").respond(json=task_json())
    update = respx.post(f"{BASE}/tasks/7").respond(
        json=task_json(title="Report", updated="2026-11-01T11:00:00Z")
    )
    updated = await backend.update_task("7", TaskPatch(title="Report"), created.version)
    assert updated.title == "Report"
    assert b'"title":"Report"' in update.calls[0].request.content.replace(b" ", b"")

    with pytest.raises(RemoteConflict):
        await backend.update_task("7", TaskPatch(title="x"), "an-older-version")


@respx.mock
async def test_set_schedule_writes_start_and_end(backend: VikunjaTaskBackend) -> None:
    respx.get(f"{BASE}/tasks/7").respond(json=task_json())
    post = respx.post(f"{BASE}/tasks/7").respond(
        json=task_json(start_date="2026-11-02T09:00:00Z", end_date="2026-11-02T10:00:00Z")
    )
    start = datetime(2026, 11, 2, 9, tzinfo=UTC)
    current = await backend.get_task("7")
    task = await backend.set_schedule(
        "7", start, datetime(2026, 11, 2, 10, tzinfo=UTC), current.version
    )
    assert task.scheduled_start == start
    sent = post.calls[0].request.content.decode()
    assert "2026-11-02T09:00:00Z" in sent and "2026-11-02T10:00:00Z" in sent


@respx.mock
async def test_complete_and_delete(backend: VikunjaTaskBackend) -> None:
    respx.get(f"{BASE}/tasks/7").respond(json=task_json())
    respx.post(f"{BASE}/tasks/7").respond(json=task_json(done=True))
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
