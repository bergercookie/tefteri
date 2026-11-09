"""Times from the cache say that they are UTC, and all-day events follow the days of the user.

SQLite drops the zone of a stored time. A response without a zone ("2026-11-10T09:00:00") is read
by a browser as the user's local time, so every event showed two hours early in Athens.
"""

from datetime import UTC, datetime, timedelta

from httpx import AsyncClient

from tefteri.domain.entities import RemoteEntry
from tests.conftest import V1
from tests.fakes.world import FakeWorld

NEW = {"settings": {}, "credentials": {"token": "t"}}


def _has_zone(text: str) -> bool:
    """True when a time as text ends with a zone (``Z`` or an offset)."""
    return datetime.fromisoformat(text.replace("Z", "+00:00")).tzinfo is not None


async def _connect(api: AsyncClient, provider: str, name: str) -> dict[str, object]:
    r = await api.post(
        f"{V1}/connections", json={**NEW, "provider": provider, "display_name": name}
    )
    assert r.status_code == 201, r.text
    body: dict[str, object] = r.json()
    return body


async def test_the_times_of_cached_events_carry_their_zone(
    api: AsyncClient, world: FakeWorld
) -> None:
    start = datetime.now(UTC).replace(microsecond=0) + timedelta(days=1)
    world.calendars["default"].entries["e1"] = RemoteEntry(
        "e1", "cal1", "Standup", start, start + timedelta(hours=1), "v1"
    )
    await _connect(api, "google_calendar", "G")
    item = (await api.get(f"{V1}/calendar")).json()[0]
    assert _has_zone(item["start"]) and _has_zone(item["end"])
    # The same instant that the app sent, not shifted by the zone of the server or the reader.
    assert datetime.fromisoformat(item["start"].replace("Z", "+00:00")) == start


async def test_other_cached_times_carry_their_zone_too(api: AsyncClient, world: FakeWorld) -> None:
    await world.seed()
    await _connect(api, "vikunja", "T")
    status = (await api.get(f"{V1}/sync/status")).json()
    assert all(_has_zone(s["last_sync_at"]) for s in status)
    listed = (await api.get(f"{V1}/connections")).json()
    assert all(_has_zone(c["last_sync_at"]) for c in listed)


async def test_an_all_day_event_follows_the_days_of_the_user(
    api: AsyncClient, world: FakeWorld
) -> None:
    admin = (await api.get(f"{V1}/auth/me")).json()
    await api.patch(f"{V1}/users/{admin['id']}", json={"timezone": "Europe/Athens"})
    day = datetime(2026, 11, 20)  # a plain date from the app: no time, no zone
    world.calendars["default"].entries["d1"] = RemoteEntry(
        "d1", "cal1", "Holiday", day, day + timedelta(days=1), "v1", all_day=True
    )
    await _connect(api, "google_calendar", "G")
    item = (await api.get(f"{V1}/calendar")).json()[0]
    assert item["all_day"] is True
    start = datetime.fromisoformat(item["start"].replace("Z", "+00:00"))
    end = datetime.fromisoformat(item["end"].replace("Z", "+00:00"))
    # Midnight in Athens (UTC+2 in November) is 22:00 UTC of the day before.
    assert start == datetime(2026, 11, 19, 22, tzinfo=UTC)
    assert end == datetime(2026, 11, 20, 22, tzinfo=UTC)
