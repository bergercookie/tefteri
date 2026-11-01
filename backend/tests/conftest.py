"""Shared fixtures."""

from collections.abc import AsyncIterator, Awaitable, Callable

import pytest
from httpx import ASGITransport, AsyncClient

from tefteri.auth.passwords import hash_password
from tefteri.config import Settings
from tefteri.main import create_app
from tests.fakes.world import FakeWorld

ADMIN_PASSWORD = "correct horse battery"


@pytest.fixture(scope="session")
def admin_hash() -> str:
    return hash_password(ADMIN_PASSWORD)


@pytest.fixture
def make_settings(admin_hash: str) -> Callable[..., Settings]:
    def _make(**overrides: object) -> Settings:
        values: dict[str, object] = {
            "database_url": "sqlite+aiosqlite:///:memory:",
            "admin_username": "admin",
            "admin_password_hash": admin_hash,
            "secret_key": "test-secret-key-0123456789",
            "create_schema": True,
        }
        values.update(overrides)
        return Settings(_env_file=None, **values)  # type: ignore[arg-type]

    return _make


@pytest.fixture
async def client(make_settings: Callable[..., Settings]) -> AsyncIterator[AsyncClient]:
    app = create_app(make_settings())
    async with app.router.lifespan_context(app):
        transport = ASGITransport(app=app)
        async with AsyncClient(transport=transport, base_url="http://test") as c:
            yield c


@pytest.fixture
def world() -> FakeWorld:
    return FakeWorld()


@pytest.fixture
async def api(
    make_settings: Callable[..., Settings], world: FakeWorld
) -> AsyncIterator[AsyncClient]:
    """Signed-in admin client for an app wired to the fake world."""
    app = create_app(make_settings(), registry=world.registry())
    async with (
        app.router.lifespan_context(app),
        AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as c,
    ):
        r = await c.post(
            "/api/v1/auth/login", json={"username": "admin", "password": ADMIN_PASSWORD}
        )
        c.headers["Authorization"] = f"Bearer {r.json()['token']}"
        c.app = app  # type: ignore[attr-defined]
        yield c


V1 = "/api/v1"


async def connect_all(api: AsyncClient, default_context: str = "life") -> dict[str, str]:
    """Create one connection of each kind (fake backends) and return their ids by provider."""
    ids: dict[str, str] = {}
    for provider in ("vikunja", "google_calendar", "trilium"):
        r = await api.post(
            f"{V1}/connections",
            json={
                "provider": provider,
                "display_name": provider,
                "default_context": default_context,
                "settings": {},
                "credentials": {"token": "t"},
            },
        )
        ids[provider] = r.json()["id"]
    return ids


@pytest.fixture
async def make_user(api: AsyncClient) -> AsyncIterator[Callable[..., Awaitable[AsyncClient]]]:
    """Create users through the admin API and return a signed-in client for each."""
    clients: list[AsyncClient] = []

    async def _make(
        username: str, password: str = "another good pw", **extra: object
    ) -> AsyncClient:
        r = await api.post(
            f"{V1}/users", json={"username": username, "password": password, **extra}
        )
        assert r.status_code == 201, r.text
        client = AsyncClient(
            transport=ASGITransport(app=api.app),  # type: ignore[attr-defined]
            base_url="http://test",
        )
        login = await client.post(
            f"{V1}/auth/login", json={"username": username, "password": password}
        )
        client.headers["Authorization"] = f"Bearer {login.json()['token']}"
        clients.append(client)
        return client

    yield _make
    for client in clients:
        await client.aclose()
