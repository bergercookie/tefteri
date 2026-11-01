"""Documentation and process notes: create, edit, delete, and two-way links to tasks."""

from collections.abc import Awaitable, Callable

from httpx import AsyncClient

from tests.conftest import V1, connect_all
from tests.fakes.world import FakeWorld


async def _task(api: AsyncClient, title: str = "Release v1") -> str:
    ids = await connect_all(api)
    await api.post(f"{V1}/sync")
    r = await api.post(f"{V1}/tasks", json={"connection_id": ids["vikunja"], "title": title})
    assert r.status_code == 201, r.text
    task_id: str = r.json()["id"]
    return task_id


async def test_create_process_note_linked_to_a_task(api: AsyncClient, world: FakeWorld) -> None:
    task_id = await _task(api)
    r = await api.post(
        f"{V1}/notes",
        json={
            "title": "Release process",
            "body": "1. Tag\n2. Push",
            "kind": "process",
            "context": "work",
            "task_ids": [task_id],
        },
    )
    assert r.status_code == 201, r.text
    note = r.json()
    assert note["kind"] == "process" and note["effective_context"] == "work"
    assert note["task_ids"] == [task_id]
    remote = [n for n in world.notes["default"].notes.values() if n.title == "Release process"]
    assert len(remote) == 1 and remote[0].body == "1. Tag\n2. Push"

    linked = (await api.get(f"{V1}/tasks/{task_id}/notes")).json()
    assert [n["id"] for n in linked] == [note["id"]]
    listed = (await api.get(f"{V1}/notes", params={"kind": "process"})).json()
    assert [n["id"] for n in listed] == [note["id"]]


async def test_create_note_from_a_task(api: AsyncClient) -> None:
    task_id = await _task(api)
    r = await api.post(f"{V1}/tasks/{task_id}/notes", json={"kind": "process"})
    assert r.status_code == 201, r.text
    assert r.json()["title"] == "Release v1" and r.json()["kind"] == "process"
    detail = (await api.get(f"{V1}/notes/{r.json()['id']}")).json()
    assert detail["task_ids"] == [task_id]


async def test_edit_note_writes_to_the_note_app(api: AsyncClient, world: FakeWorld) -> None:
    await _task(api)
    note = (await api.post(f"{V1}/notes", json={"title": "Docs", "body": "old"})).json()
    r = await api.patch(f"{V1}/notes/{note['id']}", json={"body": "new", "context": "life"})
    assert r.status_code == 200, r.text
    assert r.json()["body"] == "new" and r.json()["context"] == "life"
    remote = [n for n in world.notes["default"].notes.values() if n.title == "Docs"]
    assert remote[0].body == "new"
    cleared = await api.patch(f"{V1}/notes/{note['id']}", json={"context": None})
    assert cleared.json()["context"] is None


async def test_edit_fails_cleanly_when_the_note_changed_in_the_app(
    api: AsyncClient, world: FakeWorld
) -> None:
    await _task(api)
    note = (await api.post(f"{V1}/notes", json={"title": "Docs", "body": "old"})).json()
    fake = world.notes["default"]
    remote_id = next(n.remote_id for n in fake.notes.values() if n.title == "Docs")
    fake.notes[remote_id] = fake.notes[remote_id].__class__(
        remote_id=remote_id, title="Docs", body="changed in app", version="other"
    )
    r = await api.patch(f"{V1}/notes/{note['id']}", json={"body": "mine"})
    assert r.status_code == 409 and r.json()["code"] == "remote_conflict"
    assert fake.notes[remote_id].body == "changed in app"
    assert (await api.get(f"{V1}/notes/{note['id']}")).json()["body"] == "old"


async def test_delete_note_removes_it_and_its_links(api: AsyncClient, world: FakeWorld) -> None:
    task_id = await _task(api)
    note = (await api.post(f"{V1}/notes", json={"title": "Docs", "task_ids": [task_id]})).json()
    assert (await api.delete(f"{V1}/notes/{note['id']}")).status_code == 204
    assert not [n for n in world.notes["default"].notes.values() if n.title == "Docs"]
    assert (await api.get(f"{V1}/notes/{note['id']}")).status_code == 404
    assert (await api.get(f"{V1}/tasks/{task_id}/notes")).json() == []
    assert (await api.get(f"{V1}/tasks/{task_id}")).status_code == 200


async def test_unlink_keeps_note_and_task(api: AsyncClient) -> None:
    task_id = await _task(api)
    note = (await api.post(f"{V1}/notes", json={"title": "Docs", "task_ids": [task_id]})).json()
    r = await api.delete(f"{V1}/tasks/{task_id}/notes/{note['id']}")
    assert r.status_code == 204
    assert (await api.get(f"{V1}/notes/{note['id']}")).json()["task_ids"] == []
    assert (await api.get(f"{V1}/tasks/{task_id}/notes")).json() == []


async def test_nothing_is_saved_when_the_note_app_is_down(
    api: AsyncClient, world: FakeWorld
) -> None:
    await _task(api)
    world.notes["default"].unavailable = True
    r = await api.post(f"{V1}/notes", json={"title": "Docs"})
    assert r.status_code == 502 and r.json()["code"] == "backend_unavailable"
    world.notes["default"].unavailable = False
    assert (await api.get(f"{V1}/notes", params={"kind": "custom"})).json() == []


async def test_only_documentation_and_process_kinds_can_be_created(api: AsyncClient) -> None:
    await _task(api)
    for kind in ("daily", "retrospective"):
        r = await api.post(f"{V1}/notes", json={"title": "x", "kind": kind})
        assert r.status_code == 422


async def test_notes_are_per_user(
    api: AsyncClient, make_user: Callable[..., Awaitable[AsyncClient]]
) -> None:
    task_id = await _task(api)
    note = (await api.post(f"{V1}/notes", json={"title": "Docs"})).json()
    other = await make_user("bob")
    assert (await other.get(f"{V1}/notes/{note['id']}")).status_code == 404
    assert (await other.patch(f"{V1}/notes/{note['id']}", json={"body": "x"})).status_code == 404
    assert (await other.delete(f"{V1}/notes/{note['id']}")).status_code == 404
    assert (await other.get(f"{V1}/tasks/{task_id}/notes")).status_code == 404
