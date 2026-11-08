"""Tasks with a due date show in the calendar in the right slot (FR-007, FR-009, FR-010)."""

from dataclasses import replace
from datetime import UTC, datetime

from httpx import AsyncClient

from tefteri.domain.entities import Container, TaskDraft
from tests.conftest import V1, connect_all
from tests.fakes.world import FakeWorld

ATHENS = "Europe/Athens"


async def _setup(api: AsyncClient, tz: str = "UTC") -> None:
    await connect_all(api)
    admin = (await api.get(f"{V1}/auth/me")).json()
    await api.patch(f"{V1}/users/{admin['id']}", json={"timezone": tz})


async def _calendar(api: AsyncClient) -> dict[str, dict[str, object]]:
    items = (await api.get(f"{V1}/calendar")).json()
    return {i["title"]: i for i in items if i["type"] == "task"}


async def test_timed_due_date_is_a_block_that_ends_at_the_due_time(
    api: AsyncClient, world: FakeWorld
) -> None:
    await _setup(api)
    await world.tasks["default"].create_task(
        TaskDraft("p1", "Write", due_at=datetime(2026, 11, 2, 15, tzinfo=UTC))
    )
    await api.post(f"{V1}/sync")
    item = (await _calendar(api))["Write"]
    assert str(item["start"]).startswith("2026-11-02T14:00:00")
    assert str(item["end"]).startswith("2026-11-02T15:00:00")
    assert item["all_day"] is False and item["clipped_start"] is False
    assert item["status"] == "open"


async def test_due_in_the_first_hour_is_clipped_to_the_day(
    api: AsyncClient, world: FakeWorld
) -> None:
    await _setup(api)
    await world.tasks["default"].create_task(
        TaskDraft("p1", "Early", due_at=datetime(2026, 11, 2, 0, 30, tzinfo=UTC))
    )
    await api.post(f"{V1}/sync")
    item = (await _calendar(api))["Early"]
    assert str(item["start"]).startswith("2026-11-02T00:00:00")
    assert item["clipped_start"] is True


async def test_date_only_task_is_all_day_on_its_local_date(
    api: AsyncClient, world: FakeWorld
) -> None:
    await _setup(api, ATHENS)
    backend = world.tasks["default"]
    task = await backend.create_task(
        TaskDraft("p1", "Dated", due_at=datetime(2026, 11, 3, 22, tzinfo=UTC))
    )
    backend.tasks[task.remote_id] = replace(task, all_day=True)
    await api.post(f"{V1}/sync")
    item = (await _calendar(api))["Dated"]
    assert item["all_day"] is True
    # local midnight of 4 November in Athens (UTC+2) up to the next local midnight
    assert datetime.fromisoformat(str(item["start"])) == datetime(2026, 11, 3, 22, tzinfo=UTC)
    assert datetime.fromisoformat(str(item["end"])) == datetime(2026, 11, 4, 22, tzinfo=UTC)
    assert item["clipped_start"] is False


async def test_done_tasks_carry_their_status_and_undated_tasks_do_not_show(
    api: AsyncClient, world: FakeWorld
) -> None:
    await _setup(api)
    backend = world.tasks["default"]
    done = await backend.create_task(
        TaskDraft("p1", "Done", due_at=datetime(2026, 11, 2, 9, tzinfo=UTC))
    )
    backend.tasks[done.remote_id] = replace(done, done=True)
    await backend.create_task(TaskDraft("p1", "Undated"))
    await api.post(f"{V1}/sync")
    items = await _calendar(api)
    assert set(items) == {"Done"} and items["Done"]["status"] == "done"


async def test_due_dates_set_or_removed_in_the_app_appear_and_disappear_after_sync(
    api: AsyncClient, world: FakeWorld
) -> None:
    await _setup(api)
    backend = world.tasks["default"]
    task = await backend.create_task(TaskDraft("p1", "Moving"))
    await api.post(f"{V1}/sync")
    assert await _calendar(api) == {}

    backend.tasks[task.remote_id] = replace(
        task, due_at=datetime(2026, 11, 3, 11, tzinfo=UTC), version="v2"
    )
    await api.post(f"{V1}/sync")
    assert str((await _calendar(api))["Moving"]["start"]).startswith("2026-11-03T10:00:00")

    backend.tasks[task.remote_id] = replace(
        backend.tasks[task.remote_id], due_at=None, version="v3"
    )
    await api.post(f"{V1}/sync")
    assert await _calendar(api) == {}


async def test_window_filter_and_task_and_entry_side_by_side(
    api: AsyncClient, world: FakeWorld
) -> None:
    await _setup(api)
    await world.seed()
    await world.tasks["default"].create_task(
        TaskDraft("p1", "Focus", due_at=datetime(2026, 11, 2, 10, tzinfo=UTC))
    )
    await api.post(f"{V1}/sync")
    day = (
        await api.get(
            f"{V1}/calendar",
            params={"from": "2026-11-02T00:00:00+00:00", "to": "2026-11-03T00:00:00+00:00"},
        )
    ).json()
    assert {(i["type"], i["title"]) for i in day} == {("entry", "Standup"), ("task", "Focus")}
    later = (
        await api.get(
            f"{V1}/calendar",
            params={"from": "2026-11-03T00:00:00+00:00", "to": "2026-11-04T00:00:00+00:00"},
        )
    ).json()
    assert later == []


async def test_a_task_in_the_calendar_names_its_project(api: AsyncClient, world: FakeWorld) -> None:
    backend = world.tasks["default"]
    backend.containers.append(Container("p2", "Website"))
    await _setup(api)
    await backend.create_task(
        TaskDraft("p2", "Fix form", due_at=datetime(2026, 11, 2, 15, tzinfo=UTC))
    )
    await backend.create_task(
        TaskDraft("p1", "Pay rent", due_at=datetime(2026, 11, 3, 15, tzinfo=UTC))
    )
    await api.post(f"{V1}/sync")
    items = await _calendar(api)
    assert items["Fix form"]["project"] == "Website"
    assert items["Pay rent"]["project"] == "Inbox"
    entries = [i for i in (await api.get(f"{V1}/calendar")).json() if i["type"] == "entry"]
    assert all(e["project"] is None for e in entries)
