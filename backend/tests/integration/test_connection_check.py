"""Test a connection now: ``POST /connections/{id}/check``."""

from collections.abc import AsyncIterator, Callable

from httpx import ASGITransport, AsyncClient

from tefteri.config import Settings
from tefteri.domain.entities import ConnectionHealth
from tefteri.domain.enums import ConnectionKind, ConnectionStatus
from tefteri.main import create_app
from tefteri.services.connections import AdapterRegistry
from tests.conftest import ADMIN_PASSWORD, V1
from tests.fakes.world import FakeWorld


async def _signed_in(app: object) -> AsyncIterator[AsyncClient]:
    async with (
        app.router.lifespan_context(app),  # type: ignore[attr-defined]
        AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as c,  # type: ignore[arg-type]
    ):
        r = await c.post(f"{V1}/auth/login", json={"username": "admin", "password": ADMIN_PASSWORD})
        c.headers["Authorization"] = f"Bearer {r.json()['token']}"
        yield c


async def _create(c: AsyncClient, provider: str = "trilium", **settings: str) -> str:
    r = await c.post(
        f"{V1}/connections",
        json={
            "provider": provider,
            "display_name": "Notes",
            "settings": settings,
            "credentials": {"token": "t"},
        },
    )
    assert r.status_code == 201, r.text
    return str(r.json()["id"])


async def test_a_working_connection_is_ok(api: AsyncClient) -> None:
    connection = await _create(api)
    r = await api.post(f"{V1}/connections/{connection}/check")
    assert r.status_code == 200
    assert r.json() == {
        "status": "ok",
        "reason": None,
        "message": None,
        "capabilities": {"missing_required": [], "optional": {}},  # a note app has none
    }


async def test_a_failure_gives_the_reason_and_is_stored(api: AsyncClient, world: FakeWorld) -> None:
    connection = await _create(api)
    world.notes["default"].unavailable = True
    r = await api.post(f"{V1}/connections/{connection}/check")
    assert r.json()["status"] == "error" and r.json()["reason"] == "unreachable"
    stored = [c for c in (await api.get(f"{V1}/connections")).json() if c["id"] == connection]
    assert stored[0]["status"] == "error"
    world.notes["default"].unavailable = False
    again = await api.post(f"{V1}/connections/{connection}/check")
    assert again.json()["status"] == "ok"
    stored = [c for c in (await api.get(f"{V1}/connections")).json() if c["id"] == connection]
    assert stored[0]["status"] == "ok"


async def test_a_missing_setting_is_a_message_not_a_crash(
    make_settings: Callable[..., Settings],
) -> None:
    class _Backend:
        def __init__(self, base_url: str) -> None:
            self.base_url = base_url

        async def check_connection(self) -> ConnectionHealth:
            return ConnectionHealth(ConnectionStatus.ERROR, "error", "The address is not Trilium.")

    registry = AdapterRegistry()
    # Like the real factories, this one needs the setting "base_url".
    registry.register(
        "trilium",
        ConnectionKind.NOTES,
        lambda s, _c: _Backend(s["base_url"]),  # type: ignore[arg-type,return-value]
    )
    async for c in _signed_in(create_app(make_settings(), registry=registry)):
        missing = await _create(c)  # no base_url in the settings
        r = await c.post(f"{V1}/connections/{missing}/check")
        assert r.status_code == 200
        assert r.json()["status"] == "error"
        assert r.json()["message"] == "The setting 'base_url' is missing."
        given = await _create(c, base_url="https://x.test")
        ok = await c.post(f"{V1}/connections/{given}/check")
        assert ok.json()["message"] == "The address is not Trilium."


async def test_a_connection_of_another_user_cannot_be_checked(
    api: AsyncClient, make_user: Callable[..., object]
) -> None:
    connection = await _create(api)
    other = await make_user("sam")  # type: ignore[misc]
    r = await other.post(f"{V1}/connections/{connection}/check")
    assert r.status_code == 404
    unknown = "00000000-0000-0000-0000-000000000000"
    assert (await api.post(f"{V1}/connections/{unknown}/check")).status_code == 404
