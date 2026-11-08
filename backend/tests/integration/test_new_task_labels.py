"""Create a task with labels and a project, and list labels and projects for suggestions."""

from collections.abc import AsyncIterator, Awaitable, Callable

import httpx
import pytest
import respx
from httpx import ASGITransport, AsyncClient

from tefteri.adapters.vikunja import VikunjaTaskBackend
from tefteri.domain.entities import Container
from tefteri.domain.enums import ConnectionKind
from tefteri.main import create_app
from tefteri.services.connections import AdapterRegistry
from tests.conftest import ADMIN_PASSWORD, V1, connect_all
from tests.fakes.http.vikunja import FakeVikunja
from tests.fakes.world import FakeWorld


async def _task_connection(api: AsyncClient) -> str:
    return (await connect_all(api))["vikunja"]


async def test_a_task_is_created_in_the_chosen_project_with_clean_labels(
    api: AsyncClient, world: FakeWorld
) -> None:
    world.tasks["default"].containers.append(Container("p2", "Website"))
    connection = await _task_connection(api)
    await api.post(f"{V1}/sync")
    containers = {
        c["name"]: c["id"]
        for c in (await api.get(f"{V1}/connections/{connection}/containers")).json()
    }
    r = await api.post(
        f"{V1}/tasks",
        json={
            "connection_id": connection,
            "container_id": containers["Website"],
            "title": "Fix the form",
            "labels": ["  Urgent ", "home", "URGENT", "", "   "],
        },
    )
    assert r.status_code == 201, r.text
    assert r.json()["project"] == "Website"
    assert r.json()["labels"] == ["Urgent", "home"]
    (made,) = world.tasks["default"].tasks.values()
    assert made.container_id == "p2" and made.labels == ("Urgent", "home")


async def test_a_task_without_labels_still_works(api: AsyncClient) -> None:
    connection = await _task_connection(api)
    await api.post(f"{V1}/sync")
    r = await api.post(f"{V1}/tasks", json={"connection_id": connection, "title": "Plain"})
    assert r.status_code == 201 and r.json()["labels"] == []


async def test_too_many_or_too_long_labels_are_refused(api: AsyncClient) -> None:
    connection = await _task_connection(api)
    await api.post(f"{V1}/sync")
    many = await api.post(
        f"{V1}/tasks",
        json={"connection_id": connection, "title": "x", "labels": [f"l{i}" for i in range(21)]},
    )
    long = await api.post(
        f"{V1}/tasks",
        json={"connection_id": connection, "title": "x", "labels": ["x" * 101]},
    )
    assert many.status_code == 422 and long.status_code == 422


async def test_labels_are_listed_for_suggestions(api: AsyncClient, world: FakeWorld) -> None:
    connection = await _task_connection(api)
    world.tasks["default"].known_labels.update({"zeta", "Alpha"})
    r = await api.get(f"{V1}/connections/{connection}/labels")
    assert r.status_code == 200 and r.json() == ["Alpha", "zeta"]


async def test_labels_of_a_connection_that_is_down_are_an_error(
    api: AsyncClient, world: FakeWorld
) -> None:
    connection = await _task_connection(api)
    world.tasks["default"].unavailable = True
    assert (await api.get(f"{V1}/connections/{connection}/labels")).status_code == 502


async def test_labels_need_a_task_connection_of_the_user(
    api: AsyncClient, make_user: Callable[..., Awaitable[AsyncClient]]
) -> None:
    ids = await connect_all(api)
    assert (await api.get(f"{V1}/connections/{ids['trilium']}/labels")).status_code == 404
    other = await make_user("sam")
    assert (await other.get(f"{V1}/connections/{ids['vikunja']}/labels")).status_code == 404


async def test_the_containers_name_their_parent(api: AsyncClient, world: FakeWorld) -> None:
    world.tasks["default"].containers.extend(
        [Container("p2", "Website"), Container("p3", "Launch", "p2")]
    )
    connection = await _task_connection(api)
    await api.post(f"{V1}/sync")
    found = {
        c["name"]: c["parent_remote_id"]
        for c in (await api.get(f"{V1}/connections/{connection}/containers")).json()
    }
    assert found == {"Inbox": None, "Website": None, "Launch": "p2"}


@pytest.fixture
async def stack(  # type: ignore[no-untyped-def]
    make_settings,
) -> AsyncIterator[tuple[AsyncClient, FakeVikunja, str]]:
    """The app and the stateful Vikunja, with the real adapter."""
    with respx.mock(assert_all_called=False) as router:
        server = FakeVikunja()
        server.mount(router)
        async with httpx.AsyncClient() as http:
            registry = AdapterRegistry()
            registry.register(
                "vikunja",
                ConnectionKind.TASKS,
                lambda s, c: VikunjaTaskBackend(http, s["base_url"], c["token"]),
            )
            app = create_app(make_settings(), registry=registry)
            async with (
                app.router.lifespan_context(app),
                AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as api,
            ):
                login = await api.post(
                    f"{V1}/auth/login", json={"username": "admin", "password": ADMIN_PASSWORD}
                )
                api.headers["Authorization"] = f"Bearer {login.json()['token']}"
                made = await api.post(
                    f"{V1}/connections",
                    json={
                        "provider": "vikunja",
                        "display_name": "Home tasks",
                        "default_context": "life",
                        "settings": {"base_url": server.base_url},
                        "credentials": {"token": server.token},
                    },
                )
                await api.post(f"{V1}/sync")
                yield api, server, made.json()["id"]


async def test_labels_reach_vikunja_and_come_back_in_the_task(
    stack: tuple[AsyncClient, FakeVikunja, str],
) -> None:
    api, server, connection = stack
    server.add_project("Website")
    await api.post(f"{V1}/sync")
    project = next(
        c["id"]
        for c in (await api.get(f"{V1}/connections/{connection}/containers")).json()
        if c["name"] == "Website"
    )
    first = await api.post(
        f"{V1}/tasks",
        json={
            "connection_id": connection,
            "container_id": project,
            "title": "Fix the form",
            "labels": ["Urgent", "Home"],
        },
    )
    assert first.status_code == 201, first.text
    assert first.json()["labels"] == ["Urgent", "Home"]
    assert sorted(label["title"] for label in server.labels.values()) == ["Home", "Urgent"]
    # A second task reuses the labels, and Vikunja gets no copies.
    second = await api.post(
        f"{V1}/tasks",
        json={
            "connection_id": connection,
            "container_id": project,
            "title": "Call Sam",
            "labels": ["home", "Phone"],
        },
    )
    assert second.json()["labels"] == ["Home", "Phone"]
    assert len(server.labels) == 3
    assert (await api.get(f"{V1}/connections/{connection}/labels")).json() == [
        "Home",
        "Phone",
        "Urgent",
    ]
