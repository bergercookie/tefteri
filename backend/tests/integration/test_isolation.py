"""One user never sees or changes another user's data; signed-out requests are refused."""

from collections.abc import Awaitable, Callable

from httpx import AsyncClient

from tefteri.domain.entities import Container
from tests.conftest import V1, connect_all
from tests.fakes.world import FakeWorld
from tests.integration.annual_helpers import (
    YEAR,
    bare_client,
    create_goal,
    create_goals,
    enter_value,
    freeze,
    kr,
    set_labels,
)
from tests.integration.conftest import ProjectsEnv
from tests.integration.weekly_helpers import Weekly

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
    "/api/v1/key-results/{key_result_id}/push",
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
    freeze(api)
    env = ProjectsEnv(api, world)
    theme = str((await env.rows())["Inbox"].id)
    await set_labels(env, {theme: "theme"})
    created = await create_goals(
        api, [{"title": "Secret", "key_results": [kr("Secret measure", themes=[theme])]}]
    )
    goal = created["goals"][0]
    key_result = goal["key_results"][0]
    await enter_value(api, key_result["id"], 3)
    token = (await api.post(f"{V1}/annual/push-token")).json()["token"]
    await api.get(f"{V1}/notes/daily/2026-11-02")
    entry_id = None
    sam = await make_user("sam")

    # lists are empty for another user
    for path in (
        "connections",
        "tasks",
        "calendar",
        "notes",
        "goals/history",
        "conflicts",
        "sync/status",
    ):
        assert (await sam.get(f"{V1}/{path}")).json() == [], path
    day = (await sam.get(f"{V1}/views/day/2026-11-02")).json()
    assert day["tasks"] == [] and day["entries"] == [] and day["note"] is None
    assert (await sam.get(f"{V1}/views/year/2026")).json()["tasks"] == []
    sam_plan = (await sam.get(f"{V1}/annual/{YEAR}")).json()
    assert (sam_plan["goals"], sam_plan["retired_goals"], sam_plan["theme_usage"]) == ([], [], [])
    assert (await sam.get(f"{V1}/annual/{YEAR}/history")).json()["changes"] == []
    assert (await sam.get(f"{V1}/annual/themes")).json()["themes"] == []
    assert (await sam.get(f"{V1}/annual/push-token")).json() == {"exists": False}

    # direct access by id answers 404 and changes nothing
    unknown_calls = [
        sam.get(f"{V1}/tasks/{task['id']}"),
        sam.patch(f"{V1}/tasks/{task['id']}", json={"title": "hacked"}),
        sam.post(f"{V1}/tasks/{task['id']}/complete"),
        sam.put(f"{V1}/tasks/{task['id']}/schedule", json={"start": "2026-11-02T09:00:00+00:00"}),
        sam.delete(f"{V1}/tasks/{task['id']}"),
        sam.patch(f"{V1}/annual/goals/{goal['id']}", json={"title": "hacked"}),
        sam.post(f"{V1}/annual/goals/{goal['id']}/key-results", json=kr("Hacked")),
        sam.post(f"{V1}/annual/goals/{goal['id']}/retire", json={}),
        sam.post(f"{V1}/annual/goals/{goal['id']}/restore"),
        sam.patch(f"{V1}/annual/key-results/{key_result['id']}", json={"metric": "hacked"}),
        sam.post(f"{V1}/annual/key-results/{key_result['id']}/retire", json={}),
        sam.post(f"{V1}/annual/key-results/{key_result['id']}/restore"),
        sam.put(f"{V1}/annual/key-results/{key_result['id']}/themes", json={"theme_ids": []}),
        sam.post(f"{V1}/annual/key-results/{key_result['id']}/values", json={"value": 9}),
        sam.get(f"{V1}/annual/key-results/{key_result['id']}/values"),
        sam.get(
            f"{V1}/annual/key-results/{key_result['id']}/value-on", params={"date": "2030-07-01"}
        ),
        sam.post(f"{V1}/annual/undo", json={"batch_id": created["batch_id"]}),
        sam.patch(f"{V1}/connections/{ids['vikunja']}", json={"display_name": "hacked"}),
        sam.delete(f"{V1}/connections/{ids['vikunja']}"),
        sam.post(f"{V1}/connections/{ids['vikunja']}/sync"),
        sam.get(f"{V1}/connections/{ids['vikunja']}/containers"),
    ]
    for call in unknown_calls:
        assert (await call).status_code == 404
    assert entry_id is None
    assert (await api.get(f"{V1}/tasks/{task['id']}")).json()["title"] == "Secret task"
    admin_plan = (await api.get(f"{V1}/annual/{YEAR}")).json()
    assert admin_plan["goals"][0]["title"] == "Secret"
    assert admin_plan["goals"][0]["key_results"][0]["metric"] == "Secret measure"
    assert admin_plan["goals"][0]["key_results"][0]["current_value"] == 3
    assert admin_plan["goals"][0]["key_results"][0]["links"][0]["active"] is True
    # A theme of another user cannot be linked, and their push token works only for them.
    sam_goal = await create_goal(sam, "Mine", kr())
    foreign_theme = await sam.put(
        f"{V1}/annual/key-results/{sam_goal['key_results'][0]['id']}/themes",
        json={"theme_ids": [theme]},
    )
    assert foreign_theme.status_code == 422 and foreign_theme.json()["code"] == "not_a_theme"
    async with bare_client(api) as source:
        pushed = await source.post(
            f"{V1}/key-results/{sam_goal['key_results'][0]['id']}/push",
            json={"value": 1, "at": "2030-07-01T09:00:00Z"},
            headers={"Authorization": f"Bearer {token}"},
        )
    assert pushed.status_code == 404
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


async def test_monthly_focus_changes_and_reviews_are_user_scoped(
    api: AsyncClient, world: FakeWorld, make_user: MakeUser
) -> None:
    """Monthly reads are private and mutations cannot reference another user's theme or batch."""
    env = ProjectsEnv(api, world)
    await env.connect(Container("monthly-theme", "Private monthly theme"))
    await Weekly(env).label(**{"Private monthly theme": "theme"})
    theme_id = str((await env.rows())["Private monthly theme"].id)
    month = api.app.state.clock().strftime("%Y-%m")  # type: ignore[attr-defined]
    year = int(month[:4])

    planned = await api.put(
        f"{V1}/monthly/{month}/focus",
        json={"entries": [{"project_id": theme_id, "target": 2}]},
    )
    assert planned.status_code == 200, planned.text
    change = await api.post(
        f"{V1}/monthly/{month}/changes",
        json={"kind": "target", "out_project_id": theme_id, "target": 3},
    )
    assert change.status_code == 200, change.text
    batch_id = change.json()["batch_id"]
    stored = await api.post(
        f"{V1}/monthly/{month}/review",
        json={"decisions": [{"project_id": theme_id, "decision": "carry"}]},
    )
    assert stored.status_code == 201, stored.text

    sam = await make_user("monthly-reader")
    other_plan = (await sam.get(f"{V1}/monthly/{month}")).json()
    assert other_plan["focus_known"] is False
    assert other_plan["entries"] == []
    assert other_plan["review"]["stored"] is False
    assert (await sam.get(f"{V1}/monthly/{month}/history")).json()["changes"] == []
    other_review = (await sam.get(f"{V1}/monthly/{month}/review")).json()
    assert other_review["stored"] is False
    assert other_review["snapshot"]["themes"] == []
    assert (await sam.get(f"{V1}/monthly/snapshots", params={"year": year})).json() == {
        "year": year,
        "snapshots": [],
    }

    foreign_plan = await sam.put(
        f"{V1}/monthly/{month}/focus",
        json={"entries": [{"project_id": theme_id, "target": None}]},
    )
    assert foreign_plan.status_code == 404
    foreign_undo = await sam.post(f"{V1}/monthly/{month}/changes/undo", json={"batch_id": batch_id})
    assert foreign_undo.status_code == 404
    foreign_decision = await sam.post(
        f"{V1}/monthly/{month}/review",
        json={"decisions": [{"project_id": theme_id, "decision": "carry"}]},
    )
    assert foreign_decision.status_code == 404


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


async def test_statistics_are_private(
    api: AsyncClient, world: FakeWorld, make_user: MakeUser
) -> None:
    from tefteri.domain.entities import TaskDraft

    await world.tasks["default"].create_task(TaskDraft("p1", "Private"))
    await connect_all(api)
    await api.post(f"{V1}/sync")
    task = (await api.get(f"{V1}/tasks", params={"due": "all"})).json()[0]
    await api.post(f"{V1}/tasks/{task['id']}/complete")  # recorded for the admin
    mine = (await api.get(f"{V1}/statistics", params={"day": "2030-03-06"})).json()
    assert mine["total"] == 1
    other = await make_user("peer")
    for path in ("/statistics", "/statistics/tasks"):
        body = (
            await other.get(f"{V1}{path}", params={"period": "year", "day": "2030-03-06"})
        ).json()
        assert body.get("total", 0) == 0 and body.get("hidden", 0) == 0
        assert "Private" not in str(body)
