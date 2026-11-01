"""Trilium Next adapter against recorded (hand-written) HTTP responses."""

from collections.abc import AsyncIterator
from datetime import date

import httpx
import pytest
import respx

from tefteri.adapters.trilium import TriliumNoteBackend
from tefteri.domain.entities import Container, NoteDraft, NotePatch
from tefteri.domain.enums import ConnectionStatus
from tefteri.domain.errors import AuthExpired, BackendUnavailable, RemoteConflict

BASE = "https://trilium.test/etapi"


def meta(note_id: str = "n1", title: str = "Note", modified: str = "v1") -> dict[str, object]:
    return {"noteId": note_id, "title": title, "utcDateModified": modified, "childNoteIds": []}


@pytest.fixture
async def backend() -> AsyncIterator[TriliumNoteBackend]:
    async with httpx.AsyncClient() as client:
        yield TriliumNoteBackend(client, "https://trilium.test", "etoken")


@respx.mock
async def test_containers_and_listing(backend: TriliumNoteBackend) -> None:
    root = {**meta("root", "Root"), "childNoteIds": ["w1"]}
    respx.get(f"{BASE}/notes/root").respond(json=root)
    respx.get(f"{BASE}/notes/w1").respond(json=meta("w1", "Work"))
    containers = await backend.list_containers()
    assert [c.name for c in containers] == ["Root", "Work"]

    search = respx.get(f"{BASE}/notes").respond(json={"results": [meta()]})
    respx.get(f"{BASE}/notes/n1/content").respond(
        text="<p>hi</p>", headers={"content-type": "text/html"}
    )
    notes = await backend.list_notes(Container("w1", "Work"), None)
    assert notes[0].body == "<p>hi</p>" and notes[0].version == "v1"
    assert search.calls[0].request.url.params["ancestorNoteId"] == "w1"
    assert search.calls[0].request.headers["authorization"] == "etoken"


@respx.mock
async def test_create_update_conflict_delete(backend: TriliumNoteBackend) -> None:
    respx.post(f"{BASE}/create-note").respond(json={"note": meta("n2", "Process"), "branch": {}})
    respx.get(f"{BASE}/notes/n2/content").respond(
        text="steps", headers={"content-type": "text/plain"}
    )
    created = await backend.create_note(NoteDraft("Process", "steps"))
    assert created.remote_id == "n2"

    respx.get(f"{BASE}/notes/n2").respond(json=meta("n2", "Process", "v1"))
    put = respx.put(f"{BASE}/notes/n2/content").respond(204)
    await backend.update_note("n2", NotePatch(body="new"), "v1")
    assert put.calls[0].request.content == b"new"

    with pytest.raises(RemoteConflict):
        await backend.update_note("n2", NotePatch(body="x"), "stale")
    respx.delete(f"{BASE}/notes/n2").respond(204)
    await backend.delete_note("n2")


@respx.mock
async def test_daily_note_and_append(backend: TriliumNoteBackend) -> None:
    respx.get(f"{BASE}/calendar/days/2026-11-02").respond(json=meta("d1", "2026-11-02"))
    content = respx.get(f"{BASE}/notes/d1/content").respond(
        text="<p>a</p>", headers={"content-type": "text/html"}
    )
    daily = await backend.get_or_create_daily(date(2026, 11, 2))
    assert daily.note_date == date(2026, 11, 2)

    respx.get(f"{BASE}/notes/d1").respond(json=meta("d1"))
    put = respx.put(f"{BASE}/notes/d1/content").respond(204)
    await backend.append("d1", "met Sam")
    assert put.calls[0].request.content == b"<p>a</p><p>met Sam</p>"
    assert content.called


@respx.mock
async def test_error_mapping(backend: TriliumNoteBackend) -> None:
    respx.get(f"{BASE}/app-info").respond(401)
    assert (await backend.check_connection()).status is ConnectionStatus.NEEDS_ATTENTION
    respx.get(f"{BASE}/app-info").mock(side_effect=httpx.ConnectError("down"))
    assert (await backend.check_connection()).status is ConnectionStatus.ERROR
    respx.get(f"{BASE}/notes/x").respond(403)
    with pytest.raises(AuthExpired):
        await backend.get_note("x")
    respx.get(f"{BASE}/notes/y").respond(502)
    with pytest.raises(BackendUnavailable):
        await backend.get_note("y")
