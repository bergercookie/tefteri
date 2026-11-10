"""Scheduling writes only the due date to the task app and creates no calendar event."""

from datetime import UTC, datetime, timedelta

from httpx import AsyncClient

from tefteri.domain.enums import Capability
from tests.conftest import V1, connect_all
from tests.fakes.world import FakeWorld


async def _task(api: AsyncClient) -> str:
    ids = await connect_all(api)
    await api.post(f"{V1}/sync")
    created = await api.post(f"{V1}/tasks", json={"connection_id": ids["vikunja"], "title": "T"})
    return str(created.json()["id"])


def _remote(world: FakeWorld):  # type: ignore[no-untyped-def]
    return next(iter(world.tasks["default"].tasks.values()))


async def test_block_start_stores_due_one_hour_later_and_creates_no_event(
    api: AsyncClient, world: FakeWorld
) -> None:
    task_id = await _task(api)
    r = await api.put(f"{V1}/tasks/{task_id}/schedule", json={"start": "2026-11-02T09:07:00+00:00"})
    assert r.status_code == 200 and r.json()["overlaps"] == []
    # 09:07 snaps to the 09:00 mark: block 09:00-10:00, due 10:00
    assert _remote(world).due_at == datetime(2026, 11, 2, 10, tzinfo=UTC)
    assert not _remote(world).all_day
    assert r.json()["task"]["scheduled_start"].startswith("2026-11-02T09:00:00")
    assert r.json()["task"]["scheduled_end"].startswith("2026-11-02T10:00:00")
    assert world.calendars["default"].entries == {}  # no event created

    items = (await api.get(f"{V1}/calendar")).json()
    assert [(i["type"], i["title"]) for i in items] == [("task", "T")]
    assert items[0]["start"].startswith("2026-11-02T09:00:00")
    assert items[0]["end"].startswith("2026-11-02T10:00:00")


async def test_move_and_clear(api: AsyncClient, world: FakeWorld) -> None:
    task_id = await _task(api)
    await api.put(f"{V1}/tasks/{task_id}/schedule", json={"start": "2026-11-02T09:00:00+00:00"})
    moved = await api.put(
        f"{V1}/tasks/{task_id}/schedule", json={"start": "2026-11-03T10:15:00+00:00"}
    )
    assert moved.json()["task"]["due_at"].startswith("2026-11-03T11:15:00")
    assert _remote(world).due_at == datetime(2026, 11, 3, 11, 15, tzinfo=UTC)

    cleared = await api.delete(f"{V1}/tasks/{task_id}/schedule")
    assert cleared.json()["due_at"] is None and cleared.json()["scheduled_start"] is None
    assert _remote(world).due_at is None
    assert (await api.get(f"{V1}/calendar")).json() == []


async def test_body_needs_exactly_one_of_start_and_date(api: AsyncClient) -> None:
    task_id = await _task(api)
    url = f"{V1}/tasks/{task_id}/schedule"
    assert (await api.put(url, json={})).status_code == 422
    both = {"start": "2026-11-02T09:00:00+00:00", "date": "2026-11-02"}
    assert (await api.put(url, json=both)).status_code == 422
    old = {"start": "2026-11-02T09:00:00+00:00", "end": "2026-11-02T10:00:00+00:00"}
    assert (await api.put(url, json=old)).status_code == 422  # ``end`` was removed


async def test_date_only_drop_is_all_day_by_default(api: AsyncClient, world: FakeWorld) -> None:
    task_id = await _task(api)
    r = await api.put(f"{V1}/tasks/{task_id}/schedule", json={"date": "2026-11-04"})
    assert r.status_code == 200
    assert _remote(world).all_day and _remote(world).due_at == datetime(2026, 11, 4, tzinfo=UTC)
    assert r.json()["task"]["scheduled_start"] is None
    item = (await api.get(f"{V1}/calendar")).json()[0]
    assert item["all_day"] is True and item["start"].startswith("2026-11-04T00:00:00")


async def test_date_only_drop_with_random_time_setting(api: AsyncClient, world: FakeWorld) -> None:
    task_id = await _task(api)
    on = await api.patch(f"{V1}/me/settings", json={"random_time_on_date_drop": True})
    assert on.json()["random_time_on_date_drop"] is True
    for _ in range(25):
        r = await api.put(f"{V1}/tasks/{task_id}/schedule", json={"date": "2026-11-04"})
        task = r.json()["task"]
        start = datetime.fromisoformat(task["scheduled_start"])
        end = datetime.fromisoformat(task["scheduled_end"])
        assert start.date().isoformat() == "2026-11-04"
        assert start.minute % 15 == 0 and 8 <= start.hour < 20
        assert end - start == timedelta(hours=1)
        assert not _remote(world).all_day


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
    assert "vikunja" in down.json()["detail"] and "Nothing was changed" in down.json()["detail"]
    world.tasks["default"].unavailable = False
    unchanged = (await api.get(f"{V1}/tasks/{task_id}")).json()
    assert unchanged["due_at"] is None and unchanged["scheduled_start"] is None

    remote_id = next(iter(world.tasks["default"].tasks))
    world.tasks["default"].edit_remotely(remote_id, "changed")
    stale = await api.put(f"{V1}/tasks/{task_id}/schedule", json=body)
    assert stale.status_code == 409 and stale.json()["code"] == "remote_conflict"
    assert "Conflicts screen" in stale.json()["detail"]
    conflicts = (await api.get(f"{V1}/conflicts")).json()
    assert len(conflicts) == 1 and conflicts[0]["entity_type"] == "task"
    assert conflicts[0]["local_snapshot"]["due_at"].startswith("2026-11-02T10:00:00")
    assert conflicts[0]["remote_snapshot"]["title"] == "changed"
    # the cached task was not changed and the other change was not overwritten
    cached = (await api.get(f"{V1}/tasks/{task_id}")).json()
    assert cached["due_at"] is None
    assert next(iter(world.tasks["default"].tasks.values())).due_at is None
