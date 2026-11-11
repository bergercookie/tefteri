"""Sync volume target (SC-002): 2,000 tasks and 1,000 entries in under 30 seconds.

The note app holds 500 notes too, to show that sync leaves them alone.
"""

import time
from datetime import UTC, datetime, timedelta

from httpx import AsyncClient

from tefteri.domain.entities import RemoteEntry, RemoteNote, RemoteTask
from tests.conftest import V1
from tests.fakes.world import FakeWorld

LIMIT_SECONDS = 30


def _fill(world: FakeWorld) -> None:
    # Inside the calendar sync window (90 days back, 400 days ahead).
    start = datetime.now(UTC).replace(microsecond=0) - timedelta(days=30)
    tasks = world.tasks["default"]
    for i in range(2000):
        tasks.tasks[f"t{i}"] = RemoteTask(
            f"t{i}", "p1", f"Task {i}", "v1", due_at=start + timedelta(hours=i)
        )
    calendar = world.calendars["default"]
    for i in range(1000):
        begin = start + timedelta(hours=3 * i)
        calendar.entries[f"e{i}"] = RemoteEntry(
            f"e{i}", "cal1", f"Event {i}", begin, begin + timedelta(hours=1), "v1"
        )
    notes = world.notes["default"]
    for i in range(500):
        notes.notes[f"n{i}"] = RemoteNote(f"n{i}", f"Note {i}", "text " * 50, "v1")


async def test_full_sync_meets_the_target(api: AsyncClient, world: FakeWorld) -> None:
    _fill(world)
    # A new connection syncs once at once: this is the first sync of every provider.
    started = time.perf_counter()
    created = {}
    for provider in ("vikunja", "google_calendar", "trilium"):
        r = await api.post(
            f"{V1}/connections",
            json={
                "provider": provider,
                "display_name": provider,
                "settings": {},
                "credentials": {"token": "t"},
            },
        )
        assert r.status_code == 201, r.text
        created[provider] = r.json()["sync"]["counts"]["created"]
    first = time.perf_counter() - started
    # The 500 notes of the note app are not copied: its sync is only a check.
    assert created == {"vikunja": 2000, "google_calendar": 1000, "trilium": 0}
    assert (await api.get(f"{V1}/notes")).json() == []
    assert first < LIMIT_SECONDS, f"first sync took {first:.1f} s"

    # A second sync with every item changed is the worst case for updates.
    for key, task in list(world.tasks["default"].tasks.items()):
        world.tasks["default"].tasks[key] = RemoteTask(
            task.remote_id, task.container_id, task.title + "!", "v2", due_at=task.due_at
        )
    started = time.perf_counter()
    r = await api.post(f"{V1}/sync")
    second = time.perf_counter() - started
    assert {x["name"]: x["counts"].get("updated", 0) for x in r.json()}["vikunja"] == 2000
    assert second < LIMIT_SECONDS, f"second sync took {second:.1f} s"
