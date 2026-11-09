"""Google Calendar adapter against recorded (hand-written) HTTP responses."""

from collections.abc import AsyncIterator
from datetime import UTC, datetime

import httpx
import pytest
import respx

from tefteri.adapters.google_calendar import GoogleCalendarBackend
from tefteri.adapters.google_calendar.adapter import API, TOKEN_URL, join_id, split_id
from tefteri.domain.entities import Container, EntryDraft, EntryPatch
from tefteri.domain.enums import ConnectionStatus
from tefteri.domain.errors import AuthExpired, BackendUnavailable, RemoteConflict

NOW = datetime(2026, 11, 2, 9, tzinfo=UTC)
CAL = "family@group.calendar.google.com"


def event(event_id: str = "e1", etag: str = '"1"', **over: object) -> dict[str, object]:
    data: dict[str, object] = {
        "id": event_id,
        "etag": etag,
        "summary": "Standup",
        "start": {"dateTime": "2026-11-02T09:00:00+00:00"},
        "end": {"dateTime": "2026-11-02T09:15:00+00:00"},
    }
    data.update(over)
    return data


@pytest.fixture
async def backend() -> AsyncIterator[GoogleCalendarBackend]:
    async with httpx.AsyncClient() as client:
        yield GoogleCalendarBackend(client, "cid", "secret", "refresh")


def token_route() -> respx.Route:
    return respx.post(TOKEN_URL).respond(json={"access_token": "acc", "expires_in": 3600})


def test_remote_id_roundtrip() -> None:
    assert split_id(join_id(CAL, "e1")) == (CAL, "e1")


@respx.mock
async def test_refreshes_token_and_lists_calendars_of_one_account(
    backend: GoogleCalendarBackend,
) -> None:
    token = token_route()
    cals = respx.get(f"{API}/users/me/calendarList").respond(
        json={"items": [{"id": "me@x.com", "summary": "Me"}, {"id": CAL, "summary": "Family"}]}
    )
    containers = await backend.list_containers()
    assert [c.name for c in containers] == ["Me", "Family"]
    assert cals.calls[0].request.headers["authorization"] == "Bearer acc"
    await backend.list_containers()
    assert token.call_count == 1  # access token is reused


@respx.mock
async def test_expired_access_token_is_refreshed_once(backend: GoogleCalendarBackend) -> None:
    token_route()
    route = respx.get(f"{API}/users/me/calendarList")
    route.side_effect = [httpx.Response(401), httpx.Response(200, json={"items": []})]
    assert await backend.list_containers() == []


@respx.mock
async def test_lists_entries_with_pagination_and_skips_cancelled(
    backend: GoogleCalendarBackend,
) -> None:
    token_route()
    route = respx.get(f"{API}/calendars/{CAL}/events")
    route.side_effect = [
        httpx.Response(200, json={"items": [event("e1")], "nextPageToken": "p2"}),
        httpx.Response(
            200,
            json={
                "items": [
                    event("e2", start={"date": "2026-11-03"}, end={"date": "2026-11-04"}),
                    event("e3", status="cancelled"),
                ],
                "nextSyncToken": "sync1",
            },
        ),
    ]
    page = await backend.list_entries(Container(CAL, "Family"), NOW, NOW.replace(day=30), None)
    assert [e.remote_id for e in page.items] == [join_id(CAL, "e1"), join_id(CAL, "e2")]
    assert page.items[1].all_day and page.sync_token == "sync1"
    assert route.calls[0].request.url.params["singleEvents"] == "true"


@respx.mock
async def test_create_update_if_match_and_delete(backend: GoogleCalendarBackend) -> None:
    token_route()
    respx.post(f"{API}/calendars/{CAL}/events").respond(json=event())
    created = await backend.create_entry(EntryDraft(CAL, "Standup", NOW, NOW.replace(minute=15)))
    assert created.version == '"1"'

    respx.get(f"{API}/calendars/{CAL}/events/e1").respond(json=event())
    assert (await backend.get_entry(created.remote_id)).title == "Standup"
    patch = respx.patch(f"{API}/calendars/{CAL}/events/e1").respond(
        json=event(etag='"2"', summary="Sync")
    )
    updated = await backend.update_entry(created.remote_id, EntryPatch(title="Sync"), '"1"')
    assert updated.title == "Sync"
    assert patch.calls[0].request.headers["if-match"] == '"1"'

    patch.respond(412)
    with pytest.raises(RemoteConflict):
        await backend.update_entry(created.remote_id, EntryPatch(title="x"), '"1"')
    respx.delete(f"{API}/calendars/{CAL}/events/e1").respond(204)
    await backend.delete_entry(created.remote_id)


@respx.mock
async def test_revoked_refresh_token_and_outage(backend: GoogleCalendarBackend) -> None:
    # Google answers 400 ``invalid_grant`` (not 401) for an expired or revoked refresh token.
    respx.post(TOKEN_URL).respond(400, json={"error": "invalid_grant"})
    with pytest.raises(AuthExpired):
        await backend.list_containers()
    assert (await backend.check_connection()).status is ConnectionStatus.NEEDS_ATTENTION
    respx.post(TOKEN_URL).respond(401)
    with pytest.raises(AuthExpired):
        await backend.list_containers()
    assert (await backend.check_connection()).status is ConnectionStatus.NEEDS_ATTENTION
    respx.post(TOKEN_URL).mock(side_effect=httpx.ConnectError("down"))
    with pytest.raises(BackendUnavailable):
        await backend.list_containers()


@respx.mock
async def test_the_id_of_a_special_calendar_is_encoded_in_the_path(
    backend: GoogleCalendarBackend,
) -> None:
    # "#" starts a fragment in a URL: left as it is, Google got a cut address and answered 404.
    token_route()
    holiday = "en.usa#holiday@group.v.calendar.google.com"
    route = respx.get(
        f"{API}/calendars/en.usa%23holiday%40group.v.calendar.google.com/events"
    ).respond(json={"items": [event()]})
    page = await backend.list_entries(
        Container(holiday, "Holidays"), NOW, NOW.replace(day=30), None
    )
    assert [e.title for e in page.items] == ["Standup"]
    assert route.calls[0].request.url.raw_path.startswith(
        b"/calendar/v3/calendars/en.usa%23holiday%40group.v.calendar.google.com/events?"
    )
    # Reading, changing and deleting one event of that calendar uses the same encoding.
    base = f"{API}/calendars/en.usa%23holiday%40group.v.calendar.google.com/events/e1"
    respx.get(base).respond(json=event())
    respx.patch(base).respond(json=event(etag='"2"'))
    respx.delete(base).respond(204)
    remote_id = join_id(holiday, "e1")
    await backend.get_entry(remote_id)
    await backend.update_entry(remote_id, EntryPatch(title="x"), '"1"')
    await backend.delete_entry(remote_id)
