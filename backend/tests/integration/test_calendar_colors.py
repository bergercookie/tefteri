"""The color that the user chose for a calendar in the calendar app shows in tefteri."""

from datetime import UTC, datetime, timedelta

from httpx import AsyncClient

from tefteri.domain.entities import Container, RemoteEntry
from tests.conftest import V1
from tests.fakes.world import FakeWorld

NEW = {"settings": {}, "credentials": {"token": "t"}}


def _entry(entry_id: str, calendar: str, title: str) -> RemoteEntry:
    start = datetime.now(UTC).replace(microsecond=0) + timedelta(days=1)
    return RemoteEntry(entry_id, calendar, title, start, start + timedelta(hours=1), "v1")


async def _connect(api: AsyncClient) -> str:
    r = await api.post(
        f"{V1}/connections", json={**NEW, "provider": "google_calendar", "display_name": "G"}
    )
    assert r.status_code == 201, r.text
    return str(r.json()["id"])


async def test_an_entry_has_the_color_of_its_calendar(api: AsyncClient, world: FakeWorld) -> None:
    calendar = world.calendars["default"]
    calendar.containers = [
        Container("work", "Work", color="#d50000"),
        Container("home", "Home", color="#33b679"),
        Container("plain", "Plain"),  # the app sent no color
    ]
    for entry_id, cal in (("e1", "work"), ("e2", "home"), ("e3", "plain")):
        calendar.entries[entry_id] = _entry(entry_id, cal, f"in {cal}")
    connection = await _connect(api)

    by_title = {i["title"]: i for i in (await api.get(f"{V1}/calendar")).json()}
    assert by_title["in work"]["color"] == "#d50000"
    assert by_title["in home"]["color"] == "#33b679"
    assert by_title["in plain"]["color"] is None

    containers = {
        c["name"]: c["color"]
        for c in (await api.get(f"{V1}/connections/{connection}/containers")).json()
    }
    assert containers == {"Work": "#d50000", "Home": "#33b679", "Plain": None}


async def test_the_color_follows_a_change_in_the_calendar_app(
    api: AsyncClient, world: FakeWorld
) -> None:
    calendar = world.calendars["default"]
    calendar.containers = [Container("work", "Work", color="#d50000")]
    calendar.entries["e1"] = _entry("e1", "work", "Standup")
    connection = await _connect(api)
    assert (await api.get(f"{V1}/calendar")).json()[0]["color"] == "#d50000"
    # The user picks another color in Google Calendar; the next sync takes it.
    calendar.containers = [Container("work", "Work", color="#039be5")]
    assert (await api.post(f"{V1}/connections/{connection}/sync")).json()["outcome"] == "ok"
    assert (await api.get(f"{V1}/calendar")).json()[0]["color"] == "#039be5"


async def test_the_views_carry_the_color_too(api: AsyncClient, world: FakeWorld) -> None:
    calendar = world.calendars["default"]
    calendar.containers = [Container("work", "Work", color="#d50000")]
    entry = _entry("e1", "work", "Standup")
    calendar.entries["e1"] = entry
    await _connect(api)
    day = (await api.get(f"{V1}/views/day/{entry.start.date()}")).json()
    assert [e["color"] for e in day["entries"]] == ["#d50000"]
    week = (await api.get(f"{V1}/views/week/{entry.start.date()}")).json()
    assert [e["color"] for e in week["entries"]] == ["#d50000"]
