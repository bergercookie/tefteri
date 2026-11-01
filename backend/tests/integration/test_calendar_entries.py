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
