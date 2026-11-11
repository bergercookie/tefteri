"""Labels survive a rename, a move and the removal of a project (spec 003, FR-009 to FR-012)."""

from datetime import date

from httpx import AsyncClient

from tefteri.domain.entities import Container
from tefteri.domain.enums import ProjectLabel
from tests.conftest import V1
from tests.fakes.world import FakeWorld
from tests.integration.conftest import ProjectsEnv

PAST = date(2026, 11, 2)
NEXT_WEEK = date(2026, 11, 9)


async def _label(env: ProjectsEnv, name: str, label: ProjectLabel) -> None:
    from tefteri.services.classification import Change

    row = (await env.rows())[name]
    async with env.db() as db:
        await env.classification.save(db, await env.user_id(), [Change(row.id, label)])


async def test_a_renamed_and_moved_project_keeps_its_label(env: ProjectsEnv) -> None:
    await env.connect(
        Container("p2", "Website"), Container("p3", "Garden"), Container("p4", "Launch", "p2")
    )
    await _label(env, "Garden", ProjectLabel.MAINTENANCE)
    before = (await env.rows())["Garden"]
    backend = env.world.tasks["default"]
    backend.containers = [
        Container("p3", "Allotment", "p2") if c.remote_id == "p3" else c for c in backend.containers
    ]  # renamed in the app and moved under Website
    await env.sync()
    after = (await env.rows())["Allotment"]
    assert after.id == before.id  # the same project: the public id does not change
    assert (after.label, after.parent_remote_id) == ("maintenance", "p2")
    assert after.orphaned_reason is None
    assert "Garden" not in await env.rows()


async def test_a_project_that_is_removed_is_marked_orphaned_and_keeps_everything(
    env: ProjectsEnv, api: AsyncClient, world: FakeWorld
) -> None:
    await env.connect(Container("p2", "Garden"), Container("p3", "Taxes"), tasks={"p2": 1})
    await _label(env, "Garden", ProjectLabel.THEME)
    await api.post(f"{V1}/weekly/{PAST}/projects", json={"container_id": await _container(api)})
    await api.post(f"{V1}/weekly/{PAST}/commit")
    backend = world.tasks["default"]
    backend.containers = [c for c in backend.containers if c.remote_id != "p2"]
    await env.sync()

    garden = (await env.rows())["Garden"]  # not deleted, same name
    assert (garden.orphaned_reason, garden.label) == ("missing", "theme")
    assert garden.orphaned_at is not None
    assert [h.label for h in await env.history("Garden")] == ["theme"]
    assert (await env.rows())["Taxes"].orphaned_reason is None

    # Every service that reads projects still works, and shows the stored name (SC-004).
    assert (await api.get(f"{V1}/tasks")).status_code == 200
    assert (await api.get(f"{V1}/tasks", params={"due": "all"})).status_code == 200
    assert (await api.get(f"{V1}/weekly/{NEXT_WEEK}")).status_code == 200
    back = (await api.get(f"{V1}/weekly/{NEXT_WEEK}")).json()["look_back"]
    assert [p["name"] for p in back["projects"]] == ["Garden"]
    names = {c["name"] for c in (await api.get(f"{V1}/weekly/{PAST}/candidates")).json()}
    assert "Garden" not in names
    assert (await api.get(f"{V1}/connections/{env.connection_id}/containers")).status_code == 200
    async with env.db() as db:
        tree = await env.classification.tree(db, await env.user_id())
    (view,) = tree.connections
    found = {p.row.name: p for p in view.projects}
    assert found["Garden"].row.orphaned_reason == "missing" and not found["Garden"].eligible
    assert tree.unsorted_count == 2  # Inbox and Taxes; an orphan is not "unsorted"
    await env.sync()  # a second sync keeps the mark and does not add a row
    assert len(await env.rows()) == 3


async def _container(api: AsyncClient) -> str:
    found = (await api.get(f"{V1}/weekly/{PAST}/candidates")).json()
    return str(next(c["container_id"] for c in found if c["name"] == "Garden"))


async def test_a_project_that_returns_clears_the_mark(env: ProjectsEnv, world: FakeWorld) -> None:
    await env.connect(Container("p2", "Garden"))
    await _label(env, "Garden", ProjectLabel.MILESTONE)
    backend = world.tasks["default"]
    garden = next(c for c in backend.containers if c.remote_id == "p2")
    backend.containers.remove(garden)
    await env.sync()
    assert (await env.rows())["Garden"].orphaned_reason == "missing"
    backend.containers.append(Container("p2", "Garden again"))
    await env.sync()
    back = (await env.rows())["Garden again"]
    assert (back.orphaned_reason, back.orphaned_at, back.label) == (None, None, "milestone")
