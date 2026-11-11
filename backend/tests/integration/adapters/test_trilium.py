"""Trilium Next adapter against recorded (hand-written) HTTP responses."""

from collections.abc import AsyncIterator
from datetime import date

import httpx
import pytest
import respx

from tefteri.adapters.trilium import TriliumNoteBackend
from tefteri.adapters.trilium.adapter import clean_base_url
from tefteri.domain.entities import NoteDraft, NotePatch
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
async def test_containers_are_the_root_and_its_children(backend: TriliumNoteBackend) -> None:
    root = {**meta("root", "Root"), "childNoteIds": ["w1"]}
    respx.get(f"{BASE}/notes/root").respond(json=root)
    respx.get(f"{BASE}/notes/w1").respond(json=meta("w1", "Work"))
    containers = await backend.list_containers()
    assert [c.name for c in containers] == ["Root", "Work"]
    assert respx.calls[0].request.headers["authorization"] == "etoken"


@respx.mock
async def test_the_adapter_does_not_search_or_list_notes(backend: TriliumNoteBackend) -> None:
    """The note app is not copied: there is no call that lists its notes."""
    assert not hasattr(backend, "list_notes")


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


@pytest.mark.parametrize(
    ("pasted", "expected"),
    [
        ("https://trilium.test", "https://trilium.test"),
        ("https://trilium.test/", "https://trilium.test"),
        ("  https://trilium.test/etapi  ", "https://trilium.test"),
        ("https://trilium.test/etapi/", "https://trilium.test"),
        ("https://trilium.test/#root/abc123", "https://trilium.test"),
        ("http://192.168.1.5:8080/?x=1#root", "http://192.168.1.5:8080"),
        ("https://example.com/trilium/etapi", "https://example.com/trilium"),
        ("https://example.com/trilium/", "https://example.com/trilium"),
    ],
)
def test_the_server_address_is_cleaned(pasted: str, expected: str) -> None:
    assert clean_base_url(pasted) == expected


@respx.mock
async def test_an_address_with_etapi_or_a_note_in_it_still_works() -> None:
    route = respx.get(f"{BASE}/app-info").respond(json={"appVersion": "0.63"})
    respx.get(f"{BASE}/notes/root").respond(json=meta("root", "Root"))
    async with httpx.AsyncClient() as client:
        for pasted in ("https://trilium.test/etapi/", "https://trilium.test/#root/abc"):
            health = await TriliumNoteBackend(client, pasted, "etoken").check_connection()
            assert health.status is ConnectionStatus.OK, pasted
    assert route.call_count == 2


@respx.mock
async def test_system_notes_are_not_containers_or_notes(backend: TriliumNoteBackend) -> None:
    root = {**meta("root", "Root"), "childNoteIds": ["_hidden", "w1", "_share"]}
    respx.get(f"{BASE}/notes/root").respond(json=root)
    hidden = respx.get(f"{BASE}/notes/_hidden").respond(json=meta("_hidden", "Hidden"))
    respx.get(f"{BASE}/notes/w1").respond(json=meta("w1", "Work"))
    assert [c.name for c in await backend.list_containers()] == ["Root", "Work"]
    assert not hidden.called  # not even read


@respx.mock
async def test_a_working_connection_reads_the_app_info_and_the_root(
    backend: TriliumNoteBackend,
) -> None:
    respx.get(f"{BASE}/app-info").respond(json={"appVersion": "0.63"})
    root = respx.get(f"{BASE}/notes/root").respond(json=meta("root", "Root"))
    health = await backend.check_connection()
    assert health.status is ConnectionStatus.OK and health.message == ""
    assert root.called


@respx.mock
async def test_a_wrong_token_says_where_to_make_a_new_one(
    backend: TriliumNoteBackend,
) -> None:
    respx.get(f"{BASE}/app-info").respond(401, json={"code": "NOT_AUTHENTICATED"})
    health = await backend.check_connection()
    assert health.status is ConnectionStatus.NEEDS_ATTENTION and health.detail == "auth_expired"
    assert "ETAPI token" in health.message and f"{BASE}/app-info" in health.message


@respx.mock
async def test_an_address_that_is_not_trilium_says_which_url_answered_what(
    backend: TriliumNoteBackend,
) -> None:
    # A web page or another service answers 404 at /etapi/app-info.
    respx.get(f"{BASE}/app-info").respond(404, text="Not Found")
    health = await backend.check_connection()
    assert health.status is ConnectionStatus.ERROR and health.detail == "error"
    assert f"GET {BASE}/app-info answered 404" in health.message
    assert "address" in health.message


@respx.mock
async def test_a_missing_root_note_is_reported(backend: TriliumNoteBackend) -> None:
    respx.get(f"{BASE}/app-info").respond(json={})
    respx.get(f"{BASE}/notes/root").respond(404, json={"code": "NOTE_NOT_FOUND"})
    health = await backend.check_connection()
    assert health.status is ConnectionStatus.ERROR and "root note" in health.message


@respx.mock
async def test_an_unreachable_server_names_the_address(backend: TriliumNoteBackend) -> None:
    respx.get(f"{BASE}/app-info").mock(side_effect=httpx.ConnectError("name not known"))
    health = await backend.check_connection()
    assert health.status is ConnectionStatus.ERROR and health.detail == "unreachable"
    assert "trilium.test" in health.message and "name not known" in health.message
