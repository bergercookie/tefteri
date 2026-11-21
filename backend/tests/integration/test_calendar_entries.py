"""Calendar entry create/edit/delete and the combined calendar view."""

from datetime import UTC, datetime

from httpx import AsyncClient

from tefteri.domain.entities import EntryDraft
from tests.conftest import V1, connect_all
from tests.fakes.world import FakeWorld


async def _ready(api: AsyncClient) -> dict[str, str]:
    ids = await connect_all(api)
    await api.post(f"{V1}/sync")
    return ids


async def test_entry_crud_write_through(api: AsyncClient, world: FakeWorld) -> None:
    ids = await _ready(api)
    r = await api.post(
        f"{V1}/calendar/entries",
        json={
            "connection_id": ids["google_calendar"],
            "title": "Dentist",
            "start": "2026-11-02T15:00:00+00:00",
            "end": "2026-11-02T16:00:00+00:00",
        },
    )
    assert r.status_code == 201, r.text
    entry = r.json()
    assert [e.title for e in world.calendars["default"].entries.values()] == ["Dentist"]

    edited = await api.patch(f"{V1}/calendar/entries/{entry['id']}", json={"title": "Dentist 2"})
    assert edited.json()["title"] == "Dentist 2"
    assert (await api.delete(f"{V1}/calendar/entries/{entry['id']}")).status_code == 204
    assert world.calendars["default"].entries == {}


async def test_validation_unreachable_and_wrong_kind(api: AsyncClient, world: FakeWorld) -> None:
    ids = await _ready(api)
    body = {
        "connection_id": ids["google_calendar"],
        "title": "x",
        "start": "2026-11-02T16:00:00+00:00",
        "end": "2026-11-02T15:00:00+00:00",
    }
    assert (await api.post(f"{V1}/calendar/entries", json=body)).status_code == 422
    body["end"] = "2026-11-02T17:00:00+00:00"
    world.calendars["default"].unavailable = True
    down = await api.post(f"{V1}/calendar/entries", json=body)
    assert down.status_code == 502 and down.json()["connection"] == "google_calendar"
    world.calendars["default"].unavailable = False
    assert (await api.get(f"{V1}/calendar")).json() == []
    body["connection_id"] = ids["vikunja"]
    assert (await api.post(f"{V1}/calendar/entries", json=body)).status_code == 422


async def test_calendar_window_and_overlap_reporting(api: AsyncClient, world: FakeWorld) -> None:
    ids = await _ready(api)
    nine = datetime(2026, 11, 2, 9, tzinfo=UTC)
    await world.calendars["default"].create_entry(
        EntryDraft("cal1", "Standup", nine, nine.replace(minute=30))
    )
    await api.post(f"{V1}/sync")
    task = (
        await api.post(f"{V1}/tasks", json={"connection_id": ids["vikunja"], "title": "Focus"})
    ).json()
    overlap = await api.put(
        f"{V1}/tasks/{task['id']}/schedule", json={"start": "2026-11-02T09:15:00+00:00"}
    )
    assert [e["title"] for e in overlap.json()["overlaps"]] == ["Standup"]
    no_overlap = await api.put(
        f"{V1}/tasks/{task['id']}/schedule", json={"start": "2026-11-02T09:30:00+00:00"}
    )
    assert no_overlap.json()["overlaps"] == []  # touching is not overlapping

    window = (
        await api.get(
            f"{V1}/calendar",
            params={"from": "2026-11-02T00:00:00+00:00", "to": "2026-11-02T09:10:00+00:00"},
        )
    ).json()
    assert [(i["type"], i["title"]) for i in window] == [("entry", "Standup")]


async def test_an_event_can_invite_people(api: AsyncClient, world: FakeWorld) -> None:
    ids = await _ready(api)
    base = {
        "connection_id": ids["google_calendar"],
        "title": "Planning",
        "start": "2026-11-02T15:00:00+00:00",
        "end": "2026-11-02T16:00:00+00:00",
    }
    r = await api.post(
        f"{V1}/calendar/entries",
        json=base | {"attendees": ["sam@example.com", "Sam@example.com", "kim@example.org"]},
    )
    assert r.status_code == 201, r.text
    assert world.calendars["default"].drafts[-1].attendees == ("sam@example.com", "kim@example.org")
    # Without attendees nobody is invited; a text that is not an address is refused.
    assert (await api.post(f"{V1}/calendar/entries", json=base)).status_code == 201
    assert not world.calendars["default"].drafts[-1].attendees
    bad = await api.post(f"{V1}/calendar/entries", json=base | {"attendees": ["not an address"]})
    assert bad.status_code == 422, bad.text


async def test_an_event_can_be_edited_in_title_time_place_and_description(
    api: AsyncClient, world: FakeWorld
) -> None:
    ids = await _ready(api)
    r = await api.post(
        f"{V1}/calendar/entries",
        json={
            "connection_id": ids["google_calendar"],
            "title": "Dentist",
            "start": "2026-11-02T15:00:00+00:00",
            "end": "2026-11-02T16:00:00+00:00",
        },
    )
    entry = r.json()
    edited = await api.patch(
        f"{V1}/calendar/entries/{entry['id']}",
        json={
            "title": "Dentist, second visit",
            "start": "2026-11-02T14:30:00+00:00",
            "end": "2026-11-02T16:30:00+00:00",
            "location": "Main street 5",
            "description": "Bring the x-rays.\nAsk about the bill.",
        },
    )
    assert edited.status_code == 200, edited.text
    body = edited.json()
    assert body["title"] == "Dentist, second visit"
    assert body["description"] == "Bring the x-rays.\nAsk about the bill."
    remote = next(iter(world.calendars["default"].entries.values()))
    assert (remote.title, remote.location, remote.description) == (
        "Dentist, second visit",
        "Main street 5",
        "Bring the x-rays.\nAsk about the bill.",
    )
    assert remote.start.isoformat().startswith("2026-11-02T14:30")
    assert remote.end.isoformat().startswith("2026-11-02T16:30")
    # The calendar view carries the place and the description, so the pop-up can show them.
    items = (await api.get(f"{V1}/calendar")).json()
    item = next(i for i in items if i["id"] == entry["id"])
    assert item["location"] == "Main street 5"
    assert item["description"] == "Bring the x-rays.\nAsk about the bill."
    # A patch of one field leaves the others as they were.
    only = await api.patch(f"{V1}/calendar/entries/{entry['id']}", json={"description": ""})
    assert only.json()["description"] == "" and only.json()["location"] == "Main street 5"


async def test_the_description_of_an_event_comes_from_the_app(
    api: AsyncClient, world: FakeWorld
) -> None:
    ids = await _ready(api)
    r = await api.post(
        f"{V1}/calendar/entries",
        json={
            "connection_id": ids["google_calendar"],
            "title": "Review",
            "start": "2026-11-03T09:00:00+00:00",
            "end": "2026-11-03T10:00:00+00:00",
        },
    )
    from dataclasses import replace

    backend = world.calendars["default"]
    remote_id, current = next(iter(backend.entries.items()))
    backend.entries[remote_id] = replace(
        current, description="Agenda: roadmap", version=current.version + "+"
    )
    await api.post(f"{V1}/sync")
    items = (await api.get(f"{V1}/calendar")).json()
    assert next(i for i in items if i["id"] == r.json()["id"])["description"] == "Agenda: roadmap"


async def test_an_event_cannot_end_before_it_starts_and_an_all_day_event_keeps_its_time(
    api: AsyncClient, world: FakeWorld
) -> None:
    ids = await _ready(api)
    timed = (
        await api.post(
            f"{V1}/calendar/entries",
            json={
                "connection_id": ids["google_calendar"],
                "title": "Call",
                "start": "2026-11-04T09:00:00+00:00",
                "end": "2026-11-04T10:00:00+00:00",
            },
        )
    ).json()
    for patch in (
        {"end": "2026-11-04T08:00:00+00:00"},  # before its start
        {"start": "2026-11-04T10:30:00+00:00"},  # after its end
        {"start": "2026-11-04T11:00:00+00:00", "end": "2026-11-04T11:00:00+00:00"},
    ):
        r = await api.patch(f"{V1}/calendar/entries/{timed['id']}", json=patch)
        assert r.status_code == 422, (patch, r.text)
    allday = (
        await api.post(
            f"{V1}/calendar/entries",
            json={
                "connection_id": ids["google_calendar"],
                "title": "Holiday",
                "start": "2026-11-05T00:00:00+00:00",
                "end": "2026-11-06T00:00:00+00:00",
                "all_day": True,
            },
        )
    ).json()
    moved = await api.patch(
        f"{V1}/calendar/entries/{allday['id']}",
        json={"start": "2026-11-05T09:00:00+00:00", "end": "2026-11-05T10:00:00+00:00"},
    )
    assert moved.status_code == 422 and "all-day" in moved.text
    # Its title and description still change.
    renamed = await api.patch(
        f"{V1}/calendar/entries/{allday['id']}",
        json={"title": "Public holiday", "description": "Office closed"},
    )
    assert renamed.status_code == 200 and renamed.json()["title"] == "Public holiday"
