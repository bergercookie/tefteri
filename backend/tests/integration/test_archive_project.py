"""Archiving a project of the task app from tefteri."""

from collections.abc import Awaitable, Callable
from datetime import date

from httpx import AsyncClient

from tefteri.domain.entities import Container, TaskDraft
from tefteri.domain.enums import Capability
from tests.conftest import V1, connect_all
from tests.fakes.world import FakeWorld

WEEK = date(2030, 3, 4)  # a Monday, later than any "today" the tests run on
PAST = date(2026, 11, 2)


async def _setup(api: AsyncClient, world: FakeWorld) -> tuple[str, dict[str, str]]:
    """Connect, with the projects Website (two tasks), Launch (in Website) and Garden."""
    backend = world.tasks["default"]
    backend.containers.extend(
        [Container("p2", "Website"), Container("p3", "Launch", "p2"), Container("p4", "Garden")]
    )
    for project in ("p2", "p3", "p4"):
        await backend.create_task(TaskDraft(project, f"{project} task"))
    ids = await connect_all(api)
    await api.post(f"{V1}/sync")
    found = (await api.get(f"{V1}/weekly/{WEEK}/candidates")).json()
    return ids["vikunja"], {c["name"]: c["container_id"] for c in found}


async def _archive(api: AsyncClient, connection: str, container: str) -> int:
    r = await api.post(f"{V1}/connections/{connection}/containers/{container}/archive")
    return r.status_code


async def _names(api: AsyncClient, connection: str) -> set[str]:
    r = await api.get(f"{V1}/connections/{connection}/containers")
    return {c["name"] for c in r.json()}


async def test_archive_hides_the_project_and_its_tasks(api: AsyncClient, world: FakeWorld) -> None:
    connection, ids = await _setup(api, world)
    assert await _archive(api, connection, ids["Garden"]) == 204
    assert [c.name for c in world.tasks["default"].archived] == ["Garden"]
    assert "Garden" not in await _names(api, connection)
    garden = [t for t in (await api.get(f"{V1}/tasks")).json() if t["title"] == "p4 task"]
    assert garden[0]["sync_state"] == "deleted_remotely"
    candidates = (await api.get(f"{V1}/weekly/{WEEK}/candidates")).json()
    assert "Garden" not in {c["name"] for c in candidates}
    # The next sync agrees: nothing comes back.
    await api.post(f"{V1}/sync")
    assert "Garden" not in await _names(api, connection)


async def test_archive_takes_the_subprojects_along(api: AsyncClient, world: FakeWorld) -> None:
    connection, ids = await _setup(api, world)
    assert await _archive(api, connection, ids["Website"]) == 204
    assert {c.name for c in world.tasks["default"].archived} == {"Website", "Launch"}
    names = await _names(api, connection)
    assert names.isdisjoint({"Website", "Launch"}) and "Garden" in names


async def test_archive_removes_the_project_from_a_draft_plan(
    api: AsyncClient, world: FakeWorld
) -> None:
    connection, ids = await _setup(api, world)
    for name in ("Garden", "Website"):
        await api.post(f"{V1}/weekly/{WEEK}/projects", json={"container_id": ids[name]})
    await _archive(api, connection, ids["Garden"])
    state = (await api.get(f"{V1}/weekly/{WEEK}")).json()
    assert [p["name"] for p in state["plan"]["projects"]] == ["Website"]


async def _commit_past_week(api: AsyncClient, ids: dict[str, str]) -> None:
    await api.post(f"{V1}/weekly/{PAST}/projects", json={"container_id": ids["Garden"]})
    task = next(t for t in (await api.get(f"{V1}/tasks")).json() if t["title"] == "p4 task")
    await api.put(f"{V1}/tasks/{task['id']}/schedule", json={"date": str(PAST)})
    await api.post(f"{V1}/weekly/{PAST}/commit")


async def test_a_project_waiting_for_its_look_back_cannot_be_archived(
    api: AsyncClient, world: FakeWorld
) -> None:
    connection, ids = await _setup(api, world)
    await _commit_past_week(api, ids)
    r = await api.post(f"{V1}/connections/{connection}/containers/{ids['Garden']}/archive")
    assert r.status_code == 422 and "looked back" in r.json()["detail"]
    assert world.tasks["default"].archived == []
    assert "Garden" in await _names(api, connection)


async def test_the_look_back_can_archive_a_project_and_keeps_its_counts(
    api: AsyncClient, world: FakeWorld
) -> None:
    connection, ids = await _setup(api, world)
    await _commit_past_week(api, ids)
    task = next(t for t in (await api.get(f"{V1}/tasks")).json() if t["title"] == "p4 task")
    await api.post(f"{V1}/tasks/{task['id']}/complete")
    back = (await api.get(f"{V1}/weekly/{date(2026, 11, 9)}")).json()["look_back"]
    (project,) = back["projects"]
    done = await api.post(
        f"{V1}/weekly/reviews/{back['plan_id']}",
        json={"projects": [{"plan_project_id": project["id"], "archive": True}]},
    )
    assert done.status_code == 200, done.text
    assert [c.name for c in world.tasks["default"].archived] == ["Garden"]
    entry = done.json()["entries"][0]
    assert (entry["committed_projects"], entry["done_projects"]) == (1, 1)
    assert (entry["committed_tasks"], entry["done_tasks"]) == (1, 1)
    assert entry["projects"] == [{"name": "Garden", "done": True}]
    # Once the week is reviewed, the project is archived and the name stays in the history.
    assert "Garden" not in await _names(api, connection)


async def test_archive_changes_nothing_when_the_task_app_cannot(
    api: AsyncClient, world: FakeWorld
) -> None:
    connection, ids = await _setup(api, world)
    backend = world.tasks["default"]
    backend.supported.discard(Capability.ARCHIVE_PROJECTS)
    unsupported = await api.post(
        f"{V1}/connections/{connection}/containers/{ids['Garden']}/archive"
    )
    assert unsupported.status_code == 409 and unsupported.json()["code"] == "not_supported"
    backend.supported.add(Capability.ARCHIVE_PROJECTS)
    backend.unavailable = True
    down = await api.post(f"{V1}/connections/{connection}/containers/{ids['Garden']}/archive")
    assert down.status_code == 502
    backend.unavailable = False
    assert "Garden" in await _names(api, connection)
    assert backend.archived == []


async def test_a_project_of_another_user_cannot_be_archived(
    api: AsyncClient,
    world: FakeWorld,
    make_user: Callable[..., Awaitable[AsyncClient]],
) -> None:
    connection, ids = await _setup(api, world)
    other = await make_user("sam")
    r = await other.post(f"{V1}/connections/{connection}/containers/{ids['Garden']}/archive")
    assert r.status_code == 404
    unknown = "00000000-0000-0000-0000-000000000000"
    assert (await _archive(api, connection, unknown)) == 404
    assert world.tasks["default"].archived == []
