"""Scheduling writes the time to the task app and creates no calendar event."""

from httpx import AsyncClient

from tefteri.domain.enums import Capability
from tests.conftest import V1, connect_all
from tests.fakes.world import FakeWorld


async def _task(api: AsyncClient) -> str:
    ids = await connect_all(api)
    await api.post(f"{V1}/sync")
    created = await api.post(f"{V1}/tasks", json={"connection_id": ids["vikunja"], "title": "T"})
    return str(created.json()["id"])


async def test_schedule_writes_back_and_creates_no_event(
    api: AsyncClient, world: FakeWorld
) -> None:
    task_id = await _task(api)
    r = await api.put(
        f"{V1}/tasks/{task_id}/schedule",
        json={"start": "2026-11-02T09:00:00+00:00", "end": "2026-11-02T09:30:00+00:00"},
    )
    assert r.status_code == 200 and r.json()["overlaps"] == []
    remote = next(iter(world.tasks["default"].tasks.values()))
    assert remote.scheduled_start is not None and remote.scheduled_end is not None
    assert world.calendars["default"].entries == {}  # no event created

    items = (await api.get(f"{V1}/calendar")).json()
    assert [(i["type"], i["title"]) for i in items] == [("task", "T")]

    cleared = await api.delete(f"{V1}/tasks/{task_id}/schedule")
    assert cleared.json()["scheduled_start"] is None
    assert next(iter(world.tasks["default"].tasks.values())).scheduled_start is None
    assert (await api.get(f"{V1}/calendar")).json() == []


async def test_end_defaults_to_one_hour_and_must_follow_start(api: AsyncClient) -> None:
    task_id = await _task(api)
    ok = await api.put(
        f"{V1}/tasks/{task_id}/schedule", json={"start": "2026-11-02T09:00:00+00:00"}
    )
    assert ok.json()["task"]["scheduled_end"].startswith("2026-11-02T10:00:00")
    bad = await api.put(
        f"{V1}/tasks/{task_id}/schedule",
        json={"start": "2026-11-02T09:00:00+00:00", "end": "2026-11-02T08:00:00+00:00"},
    )
    assert bad.status_code == 422


async def test_unsupported_unreachable_and_stale(api: AsyncClient, world: FakeWorld) -> None:
    task_id = await _task(api)
    body = {"start": "2026-11-02T09:00:00+00:00"}
    world.tasks["default"].supported.discard(Capability.TASK_TIME)
    unsupported = await api.put(f"{V1}/tasks/{task_id}/schedule", json=body)
    assert unsupported.status_code == 409 and unsupported.json()["code"] == "not_supported"

    world.tasks["default"].supported.add(Capability.TASK_TIME)
    world.tasks["default"].unavailable = True
    down = await api.put(f"{V1}/tasks/{task_id}/schedule", json=body)
    assert down.status_code == 502
    world.tasks["default"].unavailable = False
    assert (await api.get(f"{V1}/tasks/{task_id}")).json()["scheduled_start"] is None

    remote_id = next(iter(world.tasks["default"].tasks))
    world.tasks["default"].edit_remotely(remote_id, "changed")
    stale = await api.put(f"{V1}/tasks/{task_id}/schedule", json=body)
    assert stale.status_code == 409 and stale.json()["code"] == "remote_conflict"
