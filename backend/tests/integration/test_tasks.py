"""Task create/edit/complete/delete write through to the task app first."""

from httpx import AsyncClient

from tests.conftest import V1, connect_all
from tests.fakes.world import FakeWorld
from tests.integration.conftest import ProjectsEnv
from tests.integration.stats_helpers import Stats


async def _ready(api: AsyncClient) -> dict[str, str]:
    ids = await connect_all(api)
    await api.post(f"{V1}/sync")  # finds the projects (containers)
    return ids


async def test_crud_and_complete_write_through(api: AsyncClient, world: FakeWorld) -> None:
    ids = await _ready(api)
    created = await api.post(
        f"{V1}/tasks", json={"connection_id": ids["vikunja"], "title": "Write report"}
    )
    assert created.status_code == 201, created.text
    task = created.json()
    assert [t.title for t in world.tasks["default"].tasks.values()] == ["Write report"]

    edited = await api.patch(f"{V1}/tasks/{task['id']}", json={"title": "Write the report"})
    assert edited.json()["title"] == "Write the report"
    assert next(iter(world.tasks["default"].tasks.values())).title == "Write the report"

    done = await api.post(f"{V1}/tasks/{task['id']}/complete")
    assert done.json()["status"] == "done"
    assert next(iter(world.tasks["default"].tasks.values())).done

    assert (await api.delete(f"{V1}/tasks/{task['id']}")).status_code == 204
    assert world.tasks["default"].tasks == {}
    assert (await api.get(f"{V1}/tasks/{task['id']}")).status_code == 404


async def test_unreachable_app_changes_nothing_and_names_connection(
    api: AsyncClient, world: FakeWorld
) -> None:
    ids = await _ready(api)
    task = (
        await api.post(f"{V1}/tasks", json={"connection_id": ids["vikunja"], "title": "A"})
    ).json()
    world.tasks["default"].unavailable = True

    failed = await api.post(f"{V1}/tasks", json={"connection_id": ids["vikunja"], "title": "B"})
    assert failed.status_code == 502 and failed.json()["code"] == "backend_unavailable"
    assert failed.json()["connection"] == "vikunja" and "vikunja" in failed.json()["detail"]
    edit = await api.patch(f"{V1}/tasks/{task['id']}", json={"title": "changed"})
    assert edit.status_code == 502
    assert (await api.delete(f"{V1}/tasks/{task['id']}")).status_code == 502

    world.tasks["default"].unavailable = False
    titles = [t["title"] for t in (await api.get(f"{V1}/tasks")).json()]
    assert titles == ["A"]  # nothing applied locally, nothing queued


async def test_expired_credentials_and_stale_version(api: AsyncClient, world: FakeWorld) -> None:
    ids = await _ready(api)
    task = (
        await api.post(f"{V1}/tasks", json={"connection_id": ids["vikunja"], "title": "A"})
    ).json()
    remote_id = next(iter(world.tasks["default"].tasks))

    world.tasks["default"].edit_remotely(remote_id, "changed in the app")
    stale = await api.patch(f"{V1}/tasks/{task['id']}", json={"title": "mine"})
    assert stale.status_code == 409 and stale.json()["code"] == "remote_conflict"

    world.tasks["default"].auth_expired = True
    expired = await api.post(f"{V1}/tasks/{task['id']}/complete")
    assert expired.status_code == 502 and expired.json()["code"] == "auth_expired"


async def test_create_needs_a_task_connection_and_a_synced_project(
    api: AsyncClient, world: FakeWorld
) -> None:
    # The first sync of a new connection fails, so no project is known yet.
    world.tasks["default"].unavailable = True
    ids = await connect_all(api)
    world.tasks["default"].unavailable = False
    no_projects = await api.post(
        f"{V1}/tasks", json={"connection_id": ids["vikunja"], "title": "x"}
    )
    assert no_projects.status_code == 422  # not synced yet
    wrong = await api.post(f"{V1}/tasks", json={"connection_id": ids["trilium"], "title": "x"})
    assert wrong.status_code == 422


async def test_list_filters(api: AsyncClient, world: FakeWorld) -> None:
    ids = await _ready(api)
    for title in ("one", "two"):
        await api.post(f"{V1}/tasks", json={"connection_id": ids["vikunja"], "title": title})
    first = (await api.get(f"{V1}/tasks")).json()[0]
    await api.post(f"{V1}/tasks/{first['id']}/complete")
    open_tasks = (await api.get(f"{V1}/tasks", params={"status": "open"})).json()
    assert len(open_tasks) == 1
    assert len((await api.get(f"{V1}/tasks", params={"unscheduled": "true"})).json()) == 2


async def test_reopen_and_details(api: AsyncClient, world: FakeWorld) -> None:
    ids = await _ready(api)
    task = (
        await api.post(f"{V1}/tasks", json={"connection_id": ids["vikunja"], "title": "Write"})
    ).json()
    remote = next(iter(world.tasks["default"].tasks.values()))

    done = await api.post(f"{V1}/tasks/{task['id']}/complete")
    assert done.json()["status"] == "done"
    reopened = await api.post(f"{V1}/tasks/{task['id']}/reopen")
    assert reopened.status_code == 200 and reopened.json()["status"] == "open"
    assert not world.tasks["default"].tasks[remote.remote_id].done

    detail = (await api.get(f"{V1}/tasks/{task['id']}")).json()
    assert detail["project"] == "Inbox"
    assert detail["labels"] == []
    assert detail["url"] is None or detail["url"].endswith(f"/tasks/{remote.remote_id}")


async def test_complete_records_the_category_at_once_with_the_cached_project(
    env: ProjectsEnv,
) -> None:
    s = Stats(env)
    await s.standard()
    await s.add("p5", "Wash the car")  # Chores: maintenance
    await s.sync()
    task = await s.weekly.task("Wash the car")
    done = await env.api.post(f"{V1}/tasks/{task['id']}/complete")
    assert done.status_code == 200, done.text
    row = (await s.rows())["Wash the car"]  # no sync in between
    assert (row.category, row.reason, row.decided_via) == (
        "maintenance",
        "maintenance_label",
        "app",
    )
    assert row.project_name == "Chores"
    # The next sync sees the same task done at the same time: the row stays as it was.
    before = await s.snapshot()
    await s.sync()
    assert await s.snapshot() == before


async def test_a_refused_completion_writes_no_row(env: ProjectsEnv) -> None:
    s = Stats(env)
    await s.standard()
    await s.add("p5", "Refused")
    await s.sync()
    task = await s.weekly.task("Refused")
    s.backend.unavailable = True
    failed = await env.api.post(f"{V1}/tasks/{task['id']}/complete")
    assert failed.status_code == 502
    assert await s.rows() == {}
