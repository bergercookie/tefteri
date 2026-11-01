"""Login, admin bootstrap, throttling and session expiry through HTTP."""

from collections.abc import Callable
from datetime import UTC, datetime, timedelta

from httpx import ASGITransport, AsyncClient

from tefteri.config import Settings
from tefteri.main import create_app
from tests.conftest import ADMIN_PASSWORD

LOGIN = "/api/v1/auth/login"


async def _login(c: AsyncClient, password: str = ADMIN_PASSWORD) -> str:
    r = await c.post(LOGIN, json={"username": "admin", "password": password})
    assert r.status_code == 200, r.text
    return str(r.json()["token"])


async def test_admin_bootstrap_and_me(client: AsyncClient) -> None:
    token = await _login(client)
    r = await client.get("/api/v1/auth/me", headers={"Authorization": f"Bearer {token}"})
    assert r.status_code == 200
    assert r.json()["username"] == "admin" and r.json()["is_admin"] is True


async def test_bad_password_uses_error_model(client: AsyncClient) -> None:
    r = await client.post(LOGIN, json={"username": "admin", "password": "nope"})
    assert r.status_code == 401
    assert r.json() == {"detail": "Invalid username or password", "code": "invalid_credentials"}


async def test_requires_authentication(client: AsyncClient) -> None:
    r = await client.get("/api/v1/auth/me")
    assert r.status_code == 401 and r.json()["code"] == "not_authenticated"


async def test_logout_invalidates_token(client: AsyncClient) -> None:
    token = await _login(client)
    h = {"Authorization": f"Bearer {token}"}
    assert (await client.post("/api/v1/auth/logout", headers=h)).status_code == 204
    assert (await client.get("/api/v1/auth/me", headers=h)).status_code == 401


async def test_throttling_after_five_failures(client: AsyncClient) -> None:
    for _ in range(5):
        r = await client.post(LOGIN, json={"username": "admin", "password": "bad"})
        assert r.status_code == 401
    r = await client.post(LOGIN, json={"username": "admin", "password": ADMIN_PASSWORD})
    assert r.status_code == 429
    assert r.json()["code"] == "login_throttled" and "retry-after" in r.headers


async def test_session_expires_after_lifetime(make_settings: Callable[..., Settings]) -> None:
    app = create_app(make_settings(session_lifetime_seconds=60))
    clock = {"now": datetime.now(UTC)}
    app.state.auth_service._clock = lambda: clock["now"]
    async with (
        app.router.lifespan_context(app),
        AsyncClient(transport=ASGITransport(app=app), base_url="http://t") as c,
    ):
        token = await _login(c)
        h = {"Authorization": f"Bearer {token}"}
        assert (await c.get("/api/v1/auth/me", headers=h)).status_code == 200
        clock["now"] += timedelta(seconds=61)
        assert (await c.get("/api/v1/auth/me", headers=h)).status_code == 401


async def test_methods_health_version(client: AsyncClient) -> None:
    assert (await client.get("/api/v1/auth/methods")).json() == {"password": True, "oidc": False}
    assert (await client.get("/health")).json() == {"status": "ok"}
    assert "version" in (await client.get("/version")).json()
