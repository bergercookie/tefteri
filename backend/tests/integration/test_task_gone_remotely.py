"""A task that was deleted in the task app does not stay in tefteri (the app answers 404)."""

from httpx import AsyncClient

from tefteri.domain.entities import TaskDraft
from tests.conftest import V1, connect_all
from tests.fakes.world import FakeWorld


async def _task_ids(api: AsyncClient) -> list[str]:
    return [t["id"] for t in (await api.get(f"{V1}/tasks")).json()]


async def _gone(api: AsyncClient, world: FakeWorld) -> str:
    """Sync one task, delete it in the app, and return its id in tefteri."""
    await connect_all(api)
    backend = world.tasks["default"]
    task = await backend.create_task(TaskDraft("p1", "Vanished"))
    await api.post(f"{V1}/sync")
    [tefteri_id] = await _task_ids(api)
    del backend.tasks[task.remote_id]
    return tefteri_id


async def test_a_sync_hides_a_task_that_the_app_deleted(api: AsyncClient, world: FakeWorld) -> None:
    await _gone(api, world)
    await api.post(f"{V1}/sync")
    assert await _task_ids(api) == []
    counts = (await api.get(f"{V1}/tasks/counts")).json()
    assert sum(counts.values()) == 0


async def test_completing_a_task_that_the_app_deleted_removes_it(
    api: AsyncClient, world: FakeWorld
) -> None:
    task_id = await _gone(api, world)
    response = await api.post(f"{V1}/tasks/{task_id}/complete")
    assert response.status_code == 200
    assert await _task_ids(api) == []


async def test_deleting_a_task_that_the_app_deleted_removes_it(
    api: AsyncClient, world: FakeWorld
) -> None:
    task_id = await _gone(api, world)
    assert (await api.delete(f"{V1}/tasks/{task_id}")).status_code == 204
    assert await _task_ids(api) == []
