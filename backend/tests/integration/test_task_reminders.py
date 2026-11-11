"""A reminder before the due time of a task, written to the task app."""

from datetime import UTC, datetime

from httpx import AsyncClient

from tefteri.domain.enums import Capability
from tests.conftest import V1, connect_all
from tests.fakes.world import FakeWorld


async def _task(api: AsyncClient, *, start: str | None = "2026-11-02T09:00:00+00:00") -> str:
    """Make a task; a timed one by default (one hour from ``start``)."""
    ids = await connect_all(api)
    await api.post(f"{V1}/sync")
    created = await api.post(f"{V1}/tasks", json={"connection_id": ids["vikunja"], "title": "T"})
    task_id = str(created.json()["id"])
    if start:
        await api.put(f"{V1}/tasks/{task_id}/schedule", json={"start": start})
    return task_id


def _backend(world: FakeWorld):  # type: ignore[no-untyped-def]
    return world.tasks["default"]


def _remote_id(world: FakeWorld) -> str:
    return str(next(iter(_backend(world).tasks)))


async def test_a_task_has_no_reminder_until_one_is_added(api: AsyncClient) -> None:
    task_id = await _task(api)
    r = await api.get(f"{V1}/tasks/{task_id}/reminder")
    assert r.status_code == 200 and r.json() == {"supported": True, "minutes_before": None}


async def test_the_default_offset_is_fifteen_minutes(api: AsyncClient, world: FakeWorld) -> None:
    task_id = await _task(api)
    r = await api.put(f"{V1}/tasks/{task_id}/reminder", json={})
    assert r.status_code == 200 and r.json() == {"supported": True, "minutes_before": 15}
    assert _backend(world).reminders == {_remote_id(world): 15}
    assert (await api.get(f"{V1}/tasks/{task_id}/reminder")).json()["minutes_before"] == 15


async def test_the_offset_comes_from_the_users_setting(api: AsyncClient, world: FakeWorld) -> None:
    task_id = await _task(api)
    await api.patch(f"{V1}/me/settings", json={"default_reminder_minutes": 45})
    r = await api.put(f"{V1}/tasks/{task_id}/reminder", json={})
    assert r.json()["minutes_before"] == 45
    assert _backend(world).reminders == {_remote_id(world): 45}


async def test_an_explicit_offset_wins_and_zero_means_at_the_due_time(
    api: AsyncClient, world: FakeWorld
) -> None:
    task_id = await _task(api)
    await api.put(f"{V1}/tasks/{task_id}/reminder", json={"minutes_before": 30})
    assert _backend(world).reminders == {_remote_id(world): 30}
    zero = await api.put(f"{V1}/tasks/{task_id}/reminder", json={"minutes_before": 0})
    assert zero.json()["minutes_before"] == 0  # replaced, not added


async def test_removing_the_reminder(api: AsyncClient, world: FakeWorld) -> None:
    task_id = await _task(api)
    await api.put(f"{V1}/tasks/{task_id}/reminder", json={})
    gone = await api.delete(f"{V1}/tasks/{task_id}/reminder")
    assert gone.status_code == 200 and gone.json() == {"supported": True, "minutes_before": None}
    assert _backend(world).reminders == {}
    # Removing it twice is fine.
    assert (await api.delete(f"{V1}/tasks/{task_id}/reminder")).status_code == 200


async def test_a_task_without_a_time_of_day_cannot_have_a_reminder(
    api: AsyncClient, world: FakeWorld
) -> None:
    undated = await _task(api, start=None)
    refused = await api.put(f"{V1}/tasks/{undated}/reminder", json={})
    assert refused.status_code == 422 and "day and a time" in refused.json()["detail"]

    dated = await _task_all_day(api)
    assert (await api.put(f"{V1}/tasks/{dated}/reminder", json={})).status_code == 422
    assert _backend(world).reminders == {}


async def _task_all_day(api: AsyncClient) -> str:
    created = await api.post(
        f"{V1}/tasks",
        json={"connection_id": (await api.get(f"{V1}/connections")).json()[0]["id"], "title": "D"},
    )
    task_id = str(created.json()["id"])
    await api.put(f"{V1}/tasks/{task_id}/schedule", json={"date": "2026-11-03"})
    return task_id


async def test_editing_the_task_keeps_its_reminder_and_the_cache_stays_in_step(
    api: AsyncClient, world: FakeWorld
) -> None:
    task_id = await _task(api)
    await api.put(f"{V1}/tasks/{task_id}/reminder", json={})
    renamed = await api.patch(f"{V1}/tasks/{task_id}", json={"title": "Renamed"})
    assert renamed.status_code == 200  # the version after the reminder is the one we hold
    assert (await api.get(f"{V1}/tasks/{task_id}/reminder")).json()["minutes_before"] == 15
    moved = await api.put(f"{V1}/tasks/{task_id}/schedule", json={"start": "2026-11-03T10:00:00Z"})
    assert moved.status_code == 200
    assert _backend(world).tasks[_remote_id(world)].due_at == datetime(2026, 11, 3, 11, tzinfo=UTC)
    assert (await api.get(f"{V1}/tasks/{task_id}/reminder")).json()["minutes_before"] == 15


async def test_an_app_without_reminders_reports_it_and_refuses(
    api: AsyncClient, world: FakeWorld
) -> None:
    task_id = await _task(api)
    _backend(world).supported.discard(Capability.TASK_REMINDERS)
    got = await api.get(f"{V1}/tasks/{task_id}/reminder")
    assert got.json() == {"supported": False, "minutes_before": None}
    refused = await api.put(f"{V1}/tasks/{task_id}/reminder", json={})
    assert refused.status_code in (409, 422, 502) and "reminders" in refused.json()["detail"]


async def test_the_app_being_down_is_reported(api: AsyncClient, world: FakeWorld) -> None:
    task_id = await _task(api)
    _backend(world).unavailable = True
    r = await api.put(f"{V1}/tasks/{task_id}/reminder", json={})
    assert r.status_code >= 400 and "cannot be reached" in r.json()["detail"]
    assert _backend(world).reminders == {}


async def test_the_offset_is_limited_to_a_week_and_one_task_belongs_to_one_user(
    api: AsyncClient,
) -> None:
    task_id = await _task(api)
    too_long = await api.put(f"{V1}/tasks/{task_id}/reminder", json={"minutes_before": 10081})
    assert too_long.status_code == 422
    negative = await api.put(f"{V1}/tasks/{task_id}/reminder", json={"minutes_before": -1})
    assert negative.status_code == 422
    unknown = await api.get(f"{V1}/tasks/00000000-0000-0000-0000-000000000000/reminder")
    assert unknown.status_code == 404
