"""Onboarding end to end: a new user signs in, connects an app and syncs it.

The connection is created with the body that the web client's Add connection dialog sends
(frontend/lib/features/settings/add_connection_dialog.dart), against the real adapters with
their HTTP mocked. A change to either side that breaks onboarding fails here.
"""

import respx
from httpx import AsyncClient

from tests.conftest import ADMIN_PASSWORD, V1

VIKUNJA = "https://vikunja.test/api/v1"
TASK = {
    "id": 7,
    "project_id": 2,
    "title": "Write report",
    "description": "",
    "done": False,
    "due_date": "0001-01-01T00:00:00Z",
    "start_date": "0001-01-01T00:00:00Z",
    "end_date": "0001-01-01T00:00:00Z",
    "updated": "2026-11-01T10:00:00Z",
}


async def _login(c: AsyncClient, username: str, password: str) -> None:
    r = await c.post(f"{V1}/auth/login", json={"username": username, "password": password})
    assert r.status_code == 200, r.text
    c.headers["Authorization"] = f"Bearer {r.json()['token']}"


# `client` runs the default adapter registry, so the real Vikunja adapter reads the body.
@respx.mock
async def test_new_user_adds_a_vikunja_connection_and_syncs(client: AsyncClient) -> None:
    respx.get(f"{VIKUNJA}/projects").respond(json=[{"id": 2, "title": "Home"}])
    tasks_route = respx.get(f"{VIKUNJA}/projects/2/tasks").respond(json=[TASK])
    await _login(client, "admin", ADMIN_PASSWORD)
    made = await client.post(
        f"{V1}/users", json={"username": "newcomer", "password": "another good pw"}
    )
    assert made.status_code == 201, made.text
    user = client
    await _login(user, "newcomer", "another good pw")
    assert (await user.get(f"{V1}/connections")).json() == []

    created = await user.post(
        f"{V1}/connections",
        json={
            "provider": "vikunja",
            "display_name": "Home tasks",
            "default_context": "life",
            "settings": {"base_url": "https://vikunja.test/"},
            "credentials": {"token": "tok"},
        },
    )
    assert created.status_code == 201, created.text
    assert created.json()["kind"] == "tasks" and "credentials" not in created.json()
    listed = (await user.get(f"{V1}/connections")).json()
    assert [c["display_name"] for c in listed] == ["Home tasks"]

    results = (await user.post(f"{V1}/sync")).json()
    assert [(r["name"], r["outcome"]) for r in results] == [("Home tasks", "ok")], results
    assert tasks_route.calls[0].request.headers["authorization"] == "Bearer tok"
    tasks = (await user.get(f"{V1}/tasks")).json()
    assert [t["title"] for t in tasks] == ["Write report"]
