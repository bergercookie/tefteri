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
    assert (await client.get("/api/v1/auth/methods")).json() == {"password": True}
    assert (await client.get("/health")).json() == {"status": "ok"}
    assert "version" in (await client.get("/version")).json()


async def test_web_session_cookie_survives_a_reload(client: AsyncClient) -> None:
    r = await client.post(LOGIN, json={"username": "admin", "password": ADMIN_PASSWORD})
    cookie = r.headers["set-cookie"]
    assert cookie.startswith(f"tefteri_session={r.json()['token']};")
    for attribute in ("HttpOnly", "Path=/api", "SameSite=strict"):
        assert attribute in cookie
    assert "Secure" not in cookie  # plain http in tests; see the https test below
    # A reloaded page has no token in memory: the cookie alone signs it in.
    me = await client.get("/api/v1/auth/me")
    assert me.status_code == 200 and me.json()["username"] == "admin"


async def test_cookie_requests_that_change_data_need_the_client_header(
    client: AsyncClient,
) -> None:
    await client.post(LOGIN, json={"username": "admin", "password": ADMIN_PASSWORD})
    forged = await client.post("/api/v1/sync")
    assert forged.status_code == 403 and forged.json()["code"] == "missing_client_header"
    ok = await client.post("/api/v1/sync", headers={"X-Tefteri-Client": "web"})
    assert ok.status_code == 200


async def test_logout_clears_the_cookie(client: AsyncClient) -> None:
    await client.post(LOGIN, json={"username": "admin", "password": ADMIN_PASSWORD})
    out = await client.post("/api/v1/auth/logout", headers={"X-Tefteri-Client": "web"})
    assert out.status_code == 204 and 'tefteri_session=""' in out.headers["set-cookie"]
    assert (await client.get("/api/v1/auth/me")).status_code == 401


async def test_cookie_is_secure_behind_https(make_settings: Callable[..., Settings]) -> None:
    app = create_app(make_settings(public_url="https://tefteri.example.org"))
    async with (
        app.router.lifespan_context(app),
        AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as c,
    ):
        r = await c.post(LOGIN, json={"username": "admin", "password": ADMIN_PASSWORD})
        assert "Secure" in r.headers["set-cookie"]
