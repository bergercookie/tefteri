"""Connections and sync endpoints with fake backends."""

from urllib.parse import parse_qs, urlparse

import httpx
import respx
from httpx import AsyncClient

from tefteri.config import Settings
from tefteri.main import create_app
from tests.fakes.world import FakeWorld

V1 = "/api/v1"
NEW = {
    "provider": "vikunja",
    "display_name": "My Vikunja",
    "default_context": "work",
    "settings": {"base_url": "https://v.test"},
    "credentials": {"token": "super-secret"},
}


async def test_create_list_update_delete_never_returns_credentials(api: AsyncClient) -> None:
    created = await api.post(f"{V1}/connections", json=NEW)
    assert created.status_code == 201
    body = created.json()
    assert body["kind"] == "tasks" and body["default_context"] == "work"
    assert "super-secret" not in created.text and "credentials" not in body

    listed = (await api.get(f"{V1}/connections")).json()
    assert [c["display_name"] for c in listed] == ["My Vikunja"]
    patched = await api.patch(f"{V1}/connections/{body['id']}", json={"display_name": "Renamed"})
    assert patched.json()["display_name"] == "Renamed"
    assert (await api.delete(f"{V1}/connections/{body['id']}")).status_code == 204
    assert (await api.get(f"{V1}/connections")).json() == []


async def test_credentials_are_encrypted_in_the_database(api: AsyncClient) -> None:
    from sqlalchemy import select

    from tefteri.db.models.connection import Connection

    await api.post(f"{V1}/connections", json=NEW)
    factory = api.app.state.session_factory  # type: ignore[attr-defined]
    async with factory() as s:
        row = (await s.execute(select(Connection))).scalars().one()
        assert row.encrypted_credentials and "super-secret" not in row.encrypted_credentials


async def test_unknown_provider_and_missing_connection(api: AsyncClient) -> None:
    r = await api.post(f"{V1}/connections", json={**NEW, "provider": "nope"})
    assert r.status_code == 422 and r.json()["code"] == "unknown_provider"
    missing = await api.post(f"{V1}/connections/00000000-0000-0000-0000-000000000000/sync")
    assert missing.status_code == 404


async def test_sync_then_read_from_cache(api: AsyncClient, world: FakeWorld) -> None:
    await world.seed()
    for provider, name in (("vikunja", "T"), ("google_calendar", "C"), ("trilium", "N")):
        await api.post(
            f"{V1}/connections", json={**NEW, "provider": provider, "display_name": name}
        )
    results = (await api.post(f"{V1}/sync")).json()
    assert {r["name"]: r["outcome"] for r in results} == {"T": "ok", "C": "ok", "N": "ok"}
    assert [t["title"] for t in (await api.get(f"{V1}/tasks")).json()] == ["Write report"]
    assert [e["title"] for e in (await api.get(f"{V1}/calendar")).json()] == ["Standup"]
    assert [n["title"] for n in (await api.get(f"{V1}/notes")).json()] == ["Process"]

    status = (await api.get(f"{V1}/sync/status")).json()
    assert all(s["status"] == "ok" and s["last_sync_at"] for s in status)
    containers = (
        await api.get(f"{V1}/connections/{results[0]['connection_id']}/containers")
    ).json()
    assert [c["name"] for c in containers] == ["Inbox"]


async def test_failing_connection_is_named_and_others_still_sync(
    api: AsyncClient, world: FakeWorld
) -> None:
    await world.seed()
    world.tasks["default"].unavailable = True
    await api.post(f"{V1}/connections", json={**NEW, "display_name": "Tasks"})
    await api.post(
        f"{V1}/connections", json={**NEW, "provider": "trilium", "display_name": "Notes"}
    )
    results = {r["name"]: r for r in (await api.post(f"{V1}/sync")).json()}
    assert results["Tasks"]["outcome"] == "error" and results["Tasks"]["reason"] == "unreachable"
    assert results["Notes"]["outcome"] == "ok"
    assert (await api.get(f"{V1}/tasks")).json() == []  # nothing applied or queued


async def test_sync_requires_authentication(client: AsyncClient) -> None:
    assert (await client.post(f"{V1}/sync")).status_code == 401
    assert (await client.get(f"{V1}/connections")).status_code == 401


async def test_google_oauth_flow(make_settings, world: FakeWorld) -> None:  # type: ignore[no-untyped-def]
    settings: Settings = make_settings(google_client_id="gid", google_client_secret="gsecret")
    app = create_app(settings, registry=world.registry())
    async with app.router.lifespan_context(app):
        transport = httpx.ASGITransport(app=app)
        async with AsyncClient(transport=transport, base_url="http://test") as c:
            login = await c.post(
                f"{V1}/auth/login", json={"username": "admin", "password": "correct horse battery"}
            )
            c.headers["Authorization"] = f"Bearer {login.json()['token']}"
            url = (
                await c.get(f"{V1}/connections/google/authorize", params={"display_name": "Work"})
            ).json()["url"]
            query = parse_qs(urlparse(url).query)
            assert query["client_id"] == ["gid"] and query["access_type"] == ["offline"]
            with respx.mock:
                respx.post("https://oauth2.googleapis.com/token").respond(
                    json={"access_token": "a", "refresh_token": "r"}
                )
                cb = await c.get(
                    f"{V1}/connections/google/callback",
                    params={"code": "c", "state": query["state"][0]},
                )
            assert cb.status_code == 200 and cb.json()["provider"] == "google_calendar"
            bad = await c.get(
                f"{V1}/connections/google/callback", params={"code": "c", "state": "forged"}
            )
            assert bad.status_code == 400 and bad.json()["code"] == "invalid_state"


async def test_google_oauth_not_configured(api: AsyncClient) -> None:
    r = await api.get(f"{V1}/connections/google/authorize")
    assert r.status_code == 503 and r.json()["code"] == "google_not_configured"


async def test_google_redirect_uses_public_url_when_set(make_settings, world: FakeWorld) -> None:  # type: ignore[no-untyped-def]
    settings = make_settings(
        google_client_id="gid", google_client_secret="gs", public_url="https://tefteri.example.org/"
    )
    app = create_app(settings, registry=world.registry())
    async with (
        app.router.lifespan_context(app),
        AsyncClient(transport=httpx.ASGITransport(app=app), base_url="http://test") as c,
    ):
        login = await c.post(
            f"{V1}/auth/login", json={"username": "admin", "password": "correct horse battery"}
        )
        c.headers["Authorization"] = f"Bearer {login.json()['token']}"
        url = (await c.get(f"{V1}/connections/google/authorize")).json()["url"]
        redirect = parse_qs(urlparse(url).query)["redirect_uri"][0]
        assert redirect == "https://tefteri.example.org/api/v1/connections/google/callback"
