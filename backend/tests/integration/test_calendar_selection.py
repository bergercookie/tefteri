"""Choosing the calendars of a Google account, and calendars that are read-only."""

from datetime import UTC, datetime, timedelta

import httpx
import respx
from httpx import AsyncClient

from tefteri.adapters.google_calendar import GoogleCalendarBackend
from tefteri.adapters.google_calendar.adapter import API, TOKEN_URL
from tefteri.domain.entities import Container, RemoteEntry
from tests.conftest import V1
from tests.fakes.world import FakeWorld

NEW = {"settings": {}, "credentials": {"token": "t"}}


def _entry(entry_id: str, calendar: str) -> RemoteEntry:
    start = datetime.now(UTC).replace(microsecond=0) + timedelta(days=1)
    return RemoteEntry(
        entry_id, calendar, f"in {calendar}", start, start + timedelta(hours=1), "v1"
    )


async def _connect(api: AsyncClient) -> dict[str, object]:
    r = await api.post(
        f"{V1}/connections", json={**NEW, "provider": "google_calendar", "display_name": "G"}
    )
    assert r.status_code == 201, r.text
    body: dict[str, object] = r.json()
    return body


async def _containers(api: AsyncClient, connection: object) -> dict[str, dict[str, object]]:
    listed = (await api.get(f"{V1}/connections/{connection}/containers")).json()
    return {c["name"]: c for c in listed}


async def _titles(api: AsyncClient) -> set[str]:
    return {i["title"] for i in (await api.get(f"{V1}/calendar")).json()}


async def test_only_the_calendars_that_start_on_are_synced(
    api: AsyncClient, world: FakeWorld
) -> None:
    calendar = world.calendars["default"]
    calendar.containers = [
        Container("mine", "Mine"),
        Container("holidays", "Holidays", enabled_by_default=False),
    ]
    calendar.entries = {"a": _entry("a", "mine"), "b": _entry("b", "holidays")}
    connection = await _connect(api)
    assert await _titles(api) == {"in mine"}
    containers = await _containers(api, connection["id"])
    assert containers["Mine"]["enabled"] is True
    assert containers["Holidays"]["enabled"] is False  # known, so the user can choose it


async def test_the_user_chooses_the_calendars_and_the_events_follow(
    api: AsyncClient, world: FakeWorld
) -> None:
    calendar = world.calendars["default"]
    calendar.containers = [
        Container("mine", "Mine"),
        Container("holidays", "Holidays", enabled_by_default=False),
    ]
    calendar.entries = {"a": _entry("a", "mine"), "b": _entry("b", "holidays")}
    connection = await _connect(api)
    ids = {n: c["id"] for n, c in (await _containers(api, connection["id"])).items()}

    both = await api.put(
        f"{V1}/connections/{connection['id']}/containers/enabled",
        json={"container_ids": [ids["Mine"], ids["Holidays"]]},
    )
    assert both.status_code == 200, both.text
    assert both.json()["sync"]["outcome"] == "ok"
    assert all(c["enabled"] for c in both.json()["containers"])
    assert await _titles(api) == {"in mine", "in holidays"}
    # An entry names its calendar, so the client can hide that calendar only.
    by_title = {i["title"]: i for i in (await api.get(f"{V1}/calendar")).json()}
    assert by_title["in mine"]["container_id"] == ids["Mine"]
    assert by_title["in holidays"]["container_id"] == ids["Holidays"]

    # Switching one off takes its events out of the cache.
    only = await api.put(
        f"{V1}/connections/{connection['id']}/containers/enabled",
        json={"container_ids": [ids["Holidays"]]},
    )
    assert {c["name"]: c["enabled"] for c in only.json()["containers"]} == {
        "Mine": False,
        "Holidays": True,
    }
    assert await _titles(api) == {"in holidays"}


async def test_a_calendar_that_is_not_in_the_connection_is_refused(
    api: AsyncClient, world: FakeWorld
) -> None:
    connection = await _connect(api)
    r = await api.put(
        f"{V1}/connections/{connection['id']}/containers/enabled",
        json={"container_ids": ["00000000-0000-0000-0000-000000000001"]},
    )
    assert r.status_code == 422 and r.json()["code"] == "unknown_container"
    missing = await api.put(
        f"{V1}/connections/00000000-0000-0000-0000-000000000002/containers/enabled",
        json={"container_ids": []},
    )
    assert missing.status_code == 404


async def test_a_read_only_calendar_cannot_be_changed(api: AsyncClient, world: FakeWorld) -> None:
    calendar = world.calendars["default"]
    calendar.containers = [Container("mine", "Mine"), Container("shared", "Shared", read_only=True)]
    calendar.entries = {"a": _entry("a", "mine"), "b": _entry("b", "shared")}
    await _connect(api)
    items = {i["title"]: i for i in (await api.get(f"{V1}/calendar")).json()}
    assert items["in mine"]["read_only"] is False
    assert items["in shared"]["read_only"] is True  # the client can switch dragging off

    shared = items["in shared"]["id"]
    original_start = calendar.entries["b"].start
    moved = await api.patch(
        f"{V1}/calendar/entries/{shared}",
        json={"start": "2030-01-01T10:00:00Z", "end": "2030-01-01T11:00:00Z"},
    )
    assert moved.status_code == 422 and "read-only" in moved.json()["detail"]
    assert (await api.delete(f"{V1}/calendar/entries/{shared}")).status_code == 422
    # Nothing changed in the app.
    assert calendar.entries["b"].start == original_start
    own = items["in mine"]["id"]
    ok = await api.patch(
        f"{V1}/calendar/entries/{own}",
        json={"start": "2030-01-01T10:00:00Z", "end": "2030-01-01T11:00:00Z"},
    )
    assert ok.status_code == 200, ok.text
    assert ok.json()["start"].startswith("2030-01-01T10:00:00")


async def test_a_new_event_goes_to_a_calendar_that_the_user_can_change(
    api: AsyncClient, world: FakeWorld
) -> None:
    calendar = world.calendars["default"]
    calendar.containers = [
        Container("a-shared", "A shared", read_only=True),  # first by name, but read-only
        Container("off", "B off", enabled_by_default=False),
        Container("mine", "C mine"),
    ]
    connection = await _connect(api)
    start = datetime(2030, 3, 4, 9, tzinfo=UTC)
    r = await api.post(
        f"{V1}/calendar/entries",
        json={
            "connection_id": connection["id"],
            "title": "Dentist",
            "start": start.isoformat(),
            "end": (start + timedelta(hours=1)).isoformat(),
        },
    )
    assert r.status_code == 201, r.text
    assert [e.container_id for e in calendar.entries.values()] == ["mine"]
    # Choosing a read-only calendar by id is refused.
    ids = {n: c["id"] for n, c in (await _containers(api, connection["id"])).items()}
    refused = await api.post(
        f"{V1}/calendar/entries",
        json={
            "connection_id": connection["id"],
            "container_id": ids["A shared"],
            "title": "Nope",
            "start": start.isoformat(),
            "end": (start + timedelta(hours=1)).isoformat(),
        },
    )
    assert refused.status_code == 422


@respx.mock
async def test_the_google_adapter_lists_every_calendar_with_its_role() -> None:
    respx.post(TOKEN_URL).respond(json={"access_token": "acc", "expires_in": 3600})
    route = respx.get(f"{API}/users/me/calendarList").respond(
        json={
            "items": [
                {"id": "me", "summary": "Me", "primary": True, "accessRole": "owner"},
                {"id": "team", "summary": "Team", "selected": True, "accessRole": "writer"},
                {"id": "shared", "summary": "Shared", "selected": True, "accessRole": "reader"},
                {"id": "busy", "summary": "Busy", "selected": True, "accessRole": "freeBusyReader"},
                {"id": "off", "summary": "Off", "accessRole": "owner"},
                {"id": "hid", "summary": "Hid", "selected": True, "hidden": True},
                {"id": "fam", "summary": "Family", "accessRole": "writer"},
            ]
        }
    )
    async with httpx.AsyncClient() as client:
        containers = await GoogleCalendarBackend(
            client, "cid", "secret", "refresh"
        ).list_containers()
    # Hidden calendars are asked for, so that the user can choose them.
    assert route.calls[0].request.url.params["showHidden"] == "true"
    by_name = {c.name: c for c in containers}
    assert [c.enabled_by_default for c in containers] == [
        True,  # the primary calendar
        True,  # the user shows it in Google Calendar
        True,
        False,  # free/busy only: no events can be read
        False,  # not shown in Google Calendar
        False,  # hidden
        False,  # Family: not shown, so the user chooses it
    ]
    assert by_name["Shared"].read_only and by_name["Busy"].read_only
    assert not by_name["Team"].read_only and not by_name["Me"].read_only


async def test_an_all_day_event_made_in_tefteri_lands_on_the_days_of_the_user(
    api: AsyncClient, world: FakeWorld
) -> None:
    admin = (await api.get(f"{V1}/auth/me")).json()
    await api.patch(f"{V1}/users/{admin['id']}", json={"timezone": "Europe/Athens"})
    calendar = world.calendars["default"]
    calendar.containers = [Container("mine", "Mine")]
    connection = await _connect(api)
    # The client sends local midnight of 20 November in Athens: 19 November, 22:00 UTC.
    r = await api.post(
        f"{V1}/calendar/entries",
        json={
            "connection_id": connection["id"],
            "title": "Holiday",
            "start": "2030-11-19T22:00:00Z",
            "end": "2030-11-20T22:00:00Z",
            "all_day": True,
        },
    )
    assert r.status_code == 201, r.text
    # The app got the dates of the user's days (20 November), not 19 November.
    (sent,) = calendar.entries.values()
    assert sent.all_day and sent.start.date().isoformat() == "2030-11-20"
    assert sent.end.date().isoformat() == "2030-11-21"
    # The cache has them at local midnight.
    item = r.json()
    assert item["all_day"] is True
    assert item["start"].startswith("2030-11-19T22:00:00")
    assert item["end"].startswith("2030-11-20T22:00:00")
