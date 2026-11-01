"""A change made in tefteri and in the app is detected, shown, and resolved only by choice."""

from datetime import UTC, datetime

from httpx import AsyncClient

from tefteri.domain.entities import EntryDraft
from tests.conftest import V1, connect_all
from tests.fakes.world import FakeWorld


async def _task(api: AsyncClient, world: FakeWorld) -> tuple[str, str]:
    ids = await connect_all(api)
    await api.post(f"{V1}/sync")
    task = (
        await api.post(f"{V1}/tasks", json={"connection_id": ids["vikunja"], "title": "Original"})
    ).json()
    return task["id"], next(iter(world.tasks["default"].tasks))


async def test_stale_edit_creates_a_conflict_and_overwrites_nothing(
    api: AsyncClient, world: FakeWorld
) -> None:
    task_id, remote_id = await _task(api, world)
    world.tasks["default"].edit_remotely(remote_id, "Changed in the app")

    r = await api.patch(f"{V1}/tasks/{task_id}", json={"title": "Changed in tefteri"})
    assert r.status_code == 409 and r.json()["code"] == "remote_conflict"
    assert "Conflicts screen" in r.json()["detail"]
    assert world.tasks["default"].tasks[remote_id].title == "Changed in the app"  # not overwritten

    conflicts = (await api.get(f"{V1}/conflicts")).json()
    assert len(conflicts) == 1 and conflicts[0]["entity_type"] == "task"
    assert conflicts[0]["local_snapshot"]["title"] == "Changed in tefteri"
    assert conflicts[0]["remote_snapshot"]["title"] == "Changed in the app"
    assert (await api.get(f"{V1}/tasks/{task_id}")).json()["sync_state"] == "conflict"

    # sync does not touch an item in conflict
    await api.post(f"{V1}/sync")
    assert (await api.get(f"{V1}/tasks/{task_id}")).json()["title"] == "Original"
    assert len((await api.get(f"{V1}/conflicts")).json()) == 1


async def test_keep_remote_takes_the_app_version(api: AsyncClient, world: FakeWorld) -> None:
    task_id, remote_id = await _task(api, world)
    world.tasks["default"].edit_remotely(remote_id, "Changed in the app")
    await api.patch(f"{V1}/tasks/{task_id}", json={"title": "Mine"})
    conflict = (await api.get(f"{V1}/conflicts")).json()[0]

    done = await api.post(
        f"{V1}/conflicts/{conflict['id']}/resolve", json={"resolution": "keep_remote"}
    )
    assert done.status_code == 204
    task = (await api.get(f"{V1}/tasks/{task_id}")).json()
    assert task["title"] == "Changed in the app" and task["sync_state"] == "synced"
    assert world.tasks["default"].tasks[remote_id].title == "Changed in the app"
    assert (await api.get(f"{V1}/conflicts")).json() == []


async def test_keep_local_writes_my_version_to_the_app(api: AsyncClient, world: FakeWorld) -> None:
    task_id, remote_id = await _task(api, world)
    world.tasks["default"].edit_remotely(remote_id, "Changed in the app")
    await api.patch(f"{V1}/tasks/{task_id}", json={"title": "Mine"})
    conflict = (await api.get(f"{V1}/conflicts")).json()[0]

    await api.post(f"{V1}/conflicts/{conflict['id']}/resolve", json={"resolution": "keep_local"})
    assert world.tasks["default"].tasks[remote_id].title == "Mine"
    assert (await api.get(f"{V1}/tasks/{task_id}")).json()["sync_state"] == "synced"
    again = await api.post(
        f"{V1}/conflicts/{conflict['id']}/resolve", json={"resolution": "keep_local"}
    )
    assert again.status_code == 404  # already resolved


async def test_entry_conflict_and_resolution(api: AsyncClient, world: FakeWorld) -> None:
    ids = await connect_all(api)
    await api.post(f"{V1}/sync")
    nine = datetime(2026, 11, 2, 9, tzinfo=UTC)
    await world.calendars["default"].create_entry(
        EntryDraft("cal1", "Standup", nine, nine.replace(minute=30))
    )
    await api.post(f"{V1}/sync")
    entry = (await api.get(f"{V1}/calendar")).json()[0]
    remote_id = next(iter(world.calendars["default"].entries))
    world.calendars["default"].edit_remotely(remote_id, "Renamed in the app")

    r = await api.patch(f"{V1}/calendar/entries/{entry['id']}", json={"title": "Mine"})
    assert r.status_code == 409
    conflict = (await api.get(f"{V1}/conflicts")).json()[0]
    assert (
        conflict["entity_type"] == "entry"
        and conflict["remote_snapshot"]["title"] == "Renamed in the app"
    )
    await api.post(f"{V1}/conflicts/{conflict['id']}/resolve", json={"resolution": "keep_local"})
    assert world.calendars["default"].entries[remote_id].title == "Mine"
    assert ids  # connections stay usable


async def test_conflicts_are_private_to_their_owner(api: AsyncClient, world: FakeWorld) -> None:
    task_id, remote_id = await _task(api, world)
    world.tasks["default"].edit_remotely(remote_id, "x")
    await api.patch(f"{V1}/tasks/{task_id}", json={"title": "y"})
    missing = await api.post(
        f"{V1}/conflicts/00000000-0000-0000-0000-000000000000/resolve",
        json={"resolution": "keep_remote"},
    )
    assert missing.status_code == 404
