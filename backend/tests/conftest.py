"""Shared fixtures."""

from collections.abc import AsyncIterator, Callable

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
