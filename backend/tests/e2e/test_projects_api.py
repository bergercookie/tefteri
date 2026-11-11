"""Project classification through HTTP (spec 003): labels, undo, rename, create, archive."""

from collections.abc import Awaitable, Callable
from typing import Any

from httpx import AsyncClient

from tefteri.domain.entities import Container, TaskDraft
from tefteri.domain.enums import Capability
from tests.conftest import V1, connect_all
from tests.fakes.world import FakeWorld

UNKNOWN = "00000000-0000-0000-0000-000000000000"


async def _setup(api: AsyncClient, world: FakeWorld) -> dict[str, Any]:
    """Connect with Website (2 tasks) > Launch, and Garden. Return the projects by name."""
    backend = world.tasks["default"]
    backend.containers.extend(
        [Container("p2", "Website"), Container("p3", "Launch", "p2"), Container("p4", "Garden")]
    )
    for project in ("p2", "p2", "p4"):
        await backend.create_task(TaskDraft(project, f"{project} task"))
    ids = await connect_all(api)
    return {"connection": ids["vikunja"], **await _projects(api)}


async def _tree(api: AsyncClient, **params: str) -> dict[str, Any]:
    r = await api.get(f"{V1}/projects/classification", params=params)
    assert r.status_code == 200, r.text
    body: dict[str, Any] = r.json()
    return body


async def _projects(api: AsyncClient) -> dict[str, Any]:
    (connection,) = (await _tree(api))["connections"]
    return {p["name"]: p for p in connection["projects"]}


# -- classification, labels, undo --------------------------------------------------------------


async def test_the_classification_lists_projects_with_proposals(
    api: AsyncClient, world: FakeWorld
) -> None:
    ids = await _setup(api, world)
    tree = await _tree(api)
    assert tree["unsorted_count"] == 4
    (connection,) = tree["connections"]
    assert connection["connection_id"] == ids["connection"]
    assert connection["capabilities"] == {"rename": True, "restore": True, "move_tasks": True}
    # The screen shows a broken connection instead of a bare "no projects".
    assert (connection["status"], connection["last_sync_outcome"]) == ("ok", "ok")
    assert [p["name"] for p in connection["projects"]] == ["Garden", "Inbox", "Website", "Launch"]
    website, launch = ids["Website"], ids["Launch"]
    assert website["label"] is None and website["unsorted"] is True
    assert website["proposal"] == {"label": "theme", "reason": "top_level"}
    assert website["effective_label"] == "theme" and website["parent_id"] is None
    assert launch["proposal"] == {"label": "milestone", "reason": "nested"}
    assert launch["parent_id"] == website["id"] and launch["parent_theme_id"] == website["id"]
    assert (website["open_tasks"], website["subprojects"], website["eligible"]) == (2, 1, True)
    assert website["orphaned"] is None and website["in_committed_plan"] is False
    only = await _tree(api, connection_id=ids["connection"])
    assert only == tree


async def test_a_project_inside_a_routine_is_proposed_as_routine_and_not_listed_weekly(
    api: AsyncClient, world: FakeWorld
) -> None:
    ids = await _setup(api, world)
    r = await api.put(
        f"{V1}/projects/labels",
        json={"changes": [{"id": ids["Website"]["id"], "label": "maintenance"}]},
    )
    assert r.status_code == 200, r.text
    launch = (await _projects(api))["Launch"]
    assert launch["proposal"] == {"label": "maintenance", "reason": "inside_routine"}
    assert launch["effective_label"] == "maintenance" and launch["label"] is None
    week = await api.get(f"{V1}/weekly/2030-03-04/candidates")
    assert {c["name"] for c in week.json()} == {"Inbox", "Garden"}


async def test_labels_are_saved_previewed_and_undone(api: AsyncClient, world: FakeWorld) -> None:
    ids = await _setup(api, world)
    changes = [
        {"id": ids["Website"]["id"], "label": "theme"},
        {"id": ids["Launch"]["id"], "label": "milestone"},
        {"id": ids["Garden"]["id"], "label": "maintenance"},
    ]
    preview = await api.put(f"{V1}/projects/labels", json={"changes": changes, "dry_run": True})
    assert preview.status_code == 200, preview.text
    assert preview.json()["batch_id"] is None
    assert preview.json()["effect"]["changed"] == 3
    assert {t["label"] for t in (await _projects(api)).values()} == {None}  # nothing written

    saved = await api.put(
        f"{V1}/projects/labels", json={"changes": changes, "source": "suggestion"}
    )
    assert saved.status_code == 200, saved.text
    body = saved.json()
    assert body["effect"] == preview.json()["effect"]
    assert {"from": "none", "to": "theme", "count": 1} in body["effect"]["by_change"]
    assert body["effect"]["in_committed_plan"] == 0
    after = await _projects(api)
    assert (after["Website"]["label"], after["Garden"]["label"]) == ("theme", "maintenance")
    assert after["Website"]["unsorted"] is False
    assert (await _tree(api))["unsorted_count"] == 1  # Inbox

    undone = await api.post(f"{V1}/projects/labels/undo", json={"batch_id": body["batch_id"]})
    assert undone.status_code == 200 and undone.json() == {"restored": 3}
    assert {t["label"] for t in (await _projects(api)).values()} == {None}
    again = await api.post(f"{V1}/projects/labels/undo", json={"batch_id": body["batch_id"]})
    assert again.status_code == 409 and again.json()["code"] == "already_undone"


async def test_a_label_can_be_cleared_and_an_unknown_one_is_refused(
    api: AsyncClient, world: FakeWorld
) -> None:
    ids = await _setup(api, world)
    one = ids["Garden"]["id"]
    await api.put(f"{V1}/projects/labels", json={"changes": [{"id": one, "label": "ignored"}]})
    assert (await _projects(api))["Garden"]["eligible"] is False
    await api.put(f"{V1}/projects/labels", json={"changes": [{"id": one, "label": None}]})
    assert (await _projects(api))["Garden"]["label"] is None
    bad = await api.put(f"{V1}/projects/labels", json={"changes": [{"id": one, "label": "boss"}]})
    assert bad.status_code == 422
    unknown = await api.put(
        f"{V1}/projects/labels", json={"changes": [{"id": UNKNOWN, "label": "theme"}]}
    )
    assert unknown.status_code == 404 and unknown.json()["code"] == "not_found"
    missing = await api.post(f"{V1}/projects/labels/undo", json={"batch_id": UNKNOWN})
    assert missing.status_code == 404


async def test_labels_are_private_to_the_user(
    api: AsyncClient,
    world: FakeWorld,
    make_user: Callable[..., Awaitable[AsyncClient]],
) -> None:
    ids = await _setup(api, world)
    other = await make_user("sam")
    assert (await other.get(f"{V1}/projects/classification")).json() == {
        "connections": [],
        "unsorted_count": 0,
    }
    mine = ids["Garden"]["id"]
    change = {"changes": [{"id": mine, "label": "theme"}]}
    assert (await other.put(f"{V1}/projects/labels", json=change)).status_code == 404
    saved = (await api.put(f"{V1}/projects/labels", json=change)).json()
    undo = await other.post(f"{V1}/projects/labels/undo", json={"batch_id": saved["batch_id"]})
    assert undo.status_code == 404
    assert (await other.patch(f"{V1}/projects/{mine}", json={"name": "x"})).status_code == 404
    assert (await other.post(f"{V1}/projects/{mine}/archive")).status_code == 404
    assert (await other.post(f"{V1}/projects/{mine}/restore")).status_code == 404
    other_connection = ids["connection"]
    assert (
        await other.get(f"{V1}/projects/classification", params={"connection_id": other_connection})
    ).status_code == 404
    made = await other.post(
        f"{V1}/projects",
        json={"connection_id": other_connection, "name": "Mine now", "label": "theme"},
    )
    assert made.status_code == 404
    assert "Mine now" not in {c.name for c in world.tasks["default"].containers}


# -- rename, create, archive, restore ------------------------------------------------------------


async def test_rename_changes_the_app_and_keeps_the_label(
    api: AsyncClient, world: FakeWorld
) -> None:
    ids = await _setup(api, world)
    garden = ids["Garden"]["id"]
    await api.put(f"{V1}/projects/labels", json={"changes": [{"id": garden, "label": "theme"}]})
    r = await api.patch(f"{V1}/projects/{garden}", json={"name": "Allotment"})
    assert r.status_code == 200, r.text
    assert (r.json()["id"], r.json()["name"], r.json()["label"]) == (garden, "Allotment", "theme")
    assert "Allotment" in {c.name for c in world.tasks["default"].containers}
    assert (await api.post(f"{V1}/sync")).status_code == 200
    assert (await _projects(api))["Allotment"]["label"] == "theme"


async def test_rename_errors(api: AsyncClient, world: FakeWorld) -> None:
    ids = await _setup(api, world)
    garden, backend = ids["Garden"]["id"], world.tasks["default"]
    backend.supported.discard(Capability.RENAME_PROJECTS)
    unsupported = await api.patch(f"{V1}/projects/{garden}", json={"name": "Allotment"})
    assert unsupported.status_code == 409 and unsupported.json()["code"] == "not_supported"
    assert (await _tree(api))["connections"][0]["capabilities"]["rename"] is False
    backend.supported.add(Capability.RENAME_PROJECTS)
    backend.unavailable = True
    down = await api.patch(f"{V1}/projects/{garden}", json={"name": "Allotment"})
    assert down.status_code == 502 and down.json()["code"] == "backend_unavailable"
    backend.unavailable = False
    assert "Garden" in await _projects(api)  # nothing changed
    empty = await api.patch(f"{V1}/projects/{garden}", json={"name": "   "})
    assert empty.status_code == 422
    backend.containers = [c for c in backend.containers if c.remote_id != "p4"]
    await api.post(f"{V1}/sync")
    gone = await api.patch(f"{V1}/projects/{garden}", json={"name": "Allotment"})
    assert gone.status_code == 404  # an orphaned project cannot be renamed
    assert (await _projects(api))["Garden"]["orphaned"]["reason"] == "missing"


async def test_create_a_project_and_label_it(api: AsyncClient, world: FakeWorld) -> None:
    ids = await _setup(api, world)
    r = await api.post(
        f"{V1}/projects",
        json={"connection_id": ids["connection"], "name": "Open source", "label": "theme"},
    )
    assert r.status_code == 201, r.text
    theme = r.json()
    assert (theme["label"], theme["name"], theme["parent_id"]) == ("theme", "Open source", None)
    child = await api.post(
        f"{V1}/projects",
        json={
            "connection_id": ids["connection"],
            "name": "Release 1",
            "parent_id": theme["id"],
            "label": "milestone",
        },
    )
    assert child.status_code == 201 and child.json()["parent_theme_id"] == theme["id"]
    assert {"Open source", "Release 1"} <= {c.name for c in world.tasks["default"].containers}
    world.tasks["default"].unavailable = True
    down = await api.post(
        f"{V1}/projects",
        json={"connection_id": ids["connection"], "name": "Nope", "label": "theme"},
    )
    assert down.status_code == 502
    world.tasks["default"].unavailable = False
    assert "Nope" not in await _projects(api)
    bad = await api.post(
        f"{V1}/projects", json={"connection_id": ids["connection"], "name": "x", "label": "boss"}
    )
    assert bad.status_code == 422


async def test_archive_and_restore(api: AsyncClient, world: FakeWorld) -> None:
    ids = await _setup(api, world)
    backend = world.tasks["default"]
    website = ids["Website"]["id"]
    await api.put(f"{V1}/projects/labels", json={"changes": [{"id": website, "label": "theme"}]})
    gone = await api.post(f"{V1}/projects/{website}/archive")
    assert gone.status_code == 200, gone.text
    assert gone.json()["orphaned"]["reason"] == "archived" and gone.json()["label"] == "theme"
    assert {c.name for c in backend.archived} == {"Website", "Launch"}
    projects = await _projects(api)
    assert projects["Launch"]["orphaned"]["reason"] == "archived"
    assert projects["Website"]["eligible"] is False
    again = await api.post(f"{V1}/projects/{website}/archive")
    assert again.status_code == 422

    backend.unavailable = True
    refused = await api.post(f"{V1}/projects/{website}/restore")
    assert refused.status_code == 502
    backend.unavailable = False
    assert (await _projects(api))["Website"]["orphaned"]["reason"] == "archived"
    backend.supported.discard(Capability.RESTORE_PROJECTS)
    unsupported = await api.post(f"{V1}/projects/{website}/restore")
    assert unsupported.status_code == 409 and unsupported.json()["code"] == "not_supported"
    backend.supported.add(Capability.RESTORE_PROJECTS)

    back = await api.post(f"{V1}/projects/{website}/restore")
    assert back.status_code == 200 and back.json()["orphaned"] is None
    assert back.json()["label"] == "theme"
    assert (await _projects(api))["Launch"]["orphaned"] is None
    assert backend.archived == []


async def test_the_old_archive_route_keeps_the_project_as_orphaned(
    api: AsyncClient, world: FakeWorld
) -> None:
    ids = await _setup(api, world)
    containers = (await api.get(f"{V1}/connections/{ids['connection']}/containers")).json()
    garden = next(c["id"] for c in containers if c["name"] == "Garden")
    r = await api.post(f"{V1}/connections/{ids['connection']}/containers/{garden}/archive")
    assert r.status_code == 204
    assert (await _projects(api))["Garden"]["orphaned"]["reason"] == "archived"


# -- capabilities of a connection ----------------------------------------------------------------


async def test_capability_fields_on_connect_and_check(api: AsyncClient, world: FakeWorld) -> None:
    world.tasks["default"].supported.discard(Capability.RESTORE_PROJECTS)
    made = await api.post(
        f"{V1}/connections",
        json={"provider": "vikunja", "display_name": "T", "settings": {}, "credentials": {}},
    )
    assert made.status_code == 201
    assert made.json()["capabilities"] == {
        "missing_required": [],
        "optional": {"rename": True, "restore": False, "move_tasks": True},
    }
    checked = (await api.post(f"{V1}/connections/{made.json()['id']}/check")).json()
    assert checked["capabilities"] == made.json()["capabilities"]


async def test_a_task_app_that_lacks_a_required_capability_is_refused(
    api: AsyncClient, world: FakeWorld
) -> None:
    world.tasks["default"].supported -= {Capability.SUBPROJECTS, Capability.COMPLETION_TIMES}
    r = await api.post(
        f"{V1}/connections",
        json={"provider": "vikunja", "display_name": "T", "settings": {}, "credentials": {}},
    )
    assert r.status_code == 422 and r.json()["code"] == "missing_capability"
    assert "subprojects" in r.json()["detail"] and "completion_times" in r.json()["detail"]
    assert (await api.get(f"{V1}/connections")).json() == []


async def test_the_weekly_candidates_say_which_projects_are_unsorted(
    api: AsyncClient, world: FakeWorld
) -> None:
    ids = await _setup(api, world)
    await api.put(
        f"{V1}/projects/labels",
        json={"changes": [{"id": ids["Garden"]["id"], "label": "ignored"}]},
    )
    found = (await api.get(f"{V1}/weekly/2030-03-04/candidates")).json()
    # Website is unclassified but has a subproject, so it is no milestone (spec 004).
    assert {c["name"]: c["unsorted"] for c in found} == {"Inbox": True, "Launch": True}
    assert {c["kind"] for c in found} == {"unsorted"}
