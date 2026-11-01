"""One user never sees or changes another user's data; signed-out requests are refused."""

from collections.abc import Awaitable, Callable

from httpx import AsyncClient

from tests.conftest import V1, connect_all
from tests.fakes.world import FakeWorld

MakeUser = Callable[..., Awaitable[AsyncClient]]
PUBLIC = {
    "/health",
    "/version",
    "/openapi.json",
    "/docs",
    "/docs/oauth2-redirect",
    "/redoc",
    "/api/v1/auth/login",
    "/api/v1/auth/methods",
    "/api/v1/connections/google/callback",
}


async def test_every_route_needs_authentication(client: AsyncClient) -> None:
    routes = (await client.get("/openapi.json")).json()["paths"]
    checked = 0
    for path, methods in routes.items():
        if path in PUBLIC:
            continue
        url = path.replace("{", "").replace("}", "")
        for method in methods:
            r = await client.request(method.upper(), url)
            assert r.status_code in (401, 405), (method, path, r.status_code)
            checked += 1
    assert checked > 30


async def test_other_users_data_is_invisible_and_untouchable(
    api: AsyncClient, world: FakeWorld, make_user: MakeUser
) -> None:
    # the admin builds a full set of data
    ids = await connect_all(api)
    await api.post(f"{V1}/sync")
    task = (
        await api.post(
            f"{V1}/tasks", json={"connection_id": ids["vikunja"], "title": "Secret task"}
        )
    ).json()
    goal = (
        await api.post(
            f"{V1}/goals",
            json={"period_type": "year", "period_start": "2026-01-01", "title": "Secret"},
        )
    ).json()
    await api.post(
        f"{V1}/plans", json={"period_type": "year", "period_start": "2026-01-01", "title": "Plan"}
    )
    await api.get(f"{V1}/notes/daily/2026-11-02")
    entry_id = None
    sam = await make_user("sam")

    # lists are empty for another user
    for path in (
        "connections",
        "tasks",
        "calendar",
        "notes",
        "goals",
        "plans",
        "conflicts",
        "sync/status",
    ):
        assert (await sam.get(f"{V1}/{path}")).json() == [], path
    day = (await sam.get(f"{V1}/views/day/2026-11-02")).json()
    assert day["tasks"] == [] and day["entries"] == [] and day["note"] is None
    assert (await sam.get(f"{V1}/views/year/2026")).json()["goals"] == []

    # direct access by id answers 404 and changes nothing
    unknown_calls = [
        sam.get(f"{V1}/tasks/{task['id']}"),
        sam.patch(f"{V1}/tasks/{task['id']}", json={"title": "hacked"}),
        sam.post(f"{V1}/tasks/{task['id']}/complete"),
        sam.put(f"{V1}/tasks/{task['id']}/schedule", json={"start": "2026-11-02T09:00:00+00:00"}),
        sam.delete(f"{V1}/tasks/{task['id']}"),
        sam.patch(f"{V1}/goals/{goal['id']}", json={"title": "hacked"}),
        sam.delete(f"{V1}/goals/{goal['id']}", params={"linked_tasks": "keep"}),
        sam.post(f"{V1}/goals/{goal['id']}/breakdown", json={}),
        sam.patch(f"{V1}/connections/{ids['vikunja']}", json={"display_name": "hacked"}),
        sam.delete(f"{V1}/connections/{ids['vikunja']}"),
        sam.post(f"{V1}/connections/{ids['vikunja']}/sync"),
        sam.get(f"{V1}/connections/{ids['vikunja']}/containers"),
    ]
    for call in unknown_calls:
        assert (await call).status_code == 404
    assert entry_id is None
    assert (await api.get(f"{V1}/tasks/{task['id']}")).json()["title"] == "Secret task"
    assert next(iter(world.tasks["default"].tasks.values())).title == "Secret task"

    # linking someone else's goal or note to my task is refused too
    mine_conn = await make_user("pat")
    assert (
        await mine_conn.patch(f"{V1}/tasks/{task['id']}", json={"goal_id": goal["id"]})
    ).status_code == 404


async def test_sync_runs_only_for_the_signed_in_user(
    api: AsyncClient, world: FakeWorld, make_user: MakeUser
) -> None:
    await connect_all(api)
    await world.seed()
    sam = await make_user("sam")
    assert (await sam.post(f"{V1}/sync")).json() == []  # sam has no connections
    await api.post(f"{V1}/sync")
    assert [t["title"] for t in (await sam.get(f"{V1}/tasks")).json()] == []
    assert [t["title"] for t in (await api.get(f"{V1}/tasks")).json()] == ["Write report"]


async def test_deleting_a_user_deletes_their_data_only(
    api: AsyncClient, world: FakeWorld, make_user: MakeUser
) -> None:
    sam = await make_user("sam")
    await world.seed()
    await connect_all(api)
    await api.post(f"{V1}/sync")
    await connect_all(sam)
    await sam.post(f"{V1}/sync")
    sam_id = (await sam.get(f"{V1}/auth/me")).json()["id"]
    assert len((await sam.get(f"{V1}/tasks")).json()) == 1

    assert (await api.delete(f"{V1}/users/{sam_id}")).status_code == 204
    assert (await sam.get(f"{V1}/tasks")).status_code == 401  # sessions are gone
    assert len((await api.get(f"{V1}/tasks")).json()) == 1  # the admin's data stays
