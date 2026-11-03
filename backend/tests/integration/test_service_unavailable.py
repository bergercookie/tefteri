"""An unreachable app or expired credentials: named, explained, nothing hidden or queued."""

from httpx import AsyncClient

from tests.fakes.world import FakeWorld

V1 = "/api/v1"


async def _connect(api: AsyncClient, name: str = "Vikunja") -> str:
    r = await api.post(
        f"{V1}/connections",
        json={"provider": "vikunja", "display_name": name, "settings": {}, "credentials": {}},
    )
    return str(r.json()["id"])


async def test_stopped_backend_names_connection_and_allows_retry(
    api: AsyncClient, world: FakeWorld
) -> None:
    await world.seed()
    cid = await _connect(api)
    world.tasks["default"].unavailable = True
    failed = (await api.post(f"{V1}/connections/{cid}/sync")).json()
    assert failed["name"] == "Vikunja" and failed["reason"] == "unreachable"
    assert failed["detail"] == "fake backend is down"  # the cause is shown, not just the reason
    status = (await api.get(f"{V1}/sync/status")).json()[0]
    assert status["status"] == "error" and status["last_sync_outcome"] == "unreachable"

    world.tasks["default"].unavailable = False  # Retry succeeds once the app is back
    retry = (await api.post(f"{V1}/connections/{cid}/sync")).json()
    assert retry["outcome"] == "ok" and retry["reason"] is None
    assert (await api.get(f"{V1}/sync/status")).json()[0]["status"] == "ok"


async def test_expired_credentials_then_reconnect_with_new_credentials(
    api: AsyncClient, world: FakeWorld
) -> None:
    cid = await _connect(api)
    world.tasks["default"].auth_expired = True
    failed = (await api.post(f"{V1}/connections/{cid}/sync")).json()
    assert failed["outcome"] == "needs_attention" and failed["reason"] == "auth_expired"

    world.tasks["default"].auth_expired = False
    patched = await api.patch(f"{V1}/connections/{cid}", json={"credentials": {"token": "new"}})
    assert patched.json()["status"] == "ok"  # new credentials reset the warning
    assert (await api.post(f"{V1}/connections/{cid}/sync")).json()["outcome"] == "ok"


async def test_failed_sync_keeps_cached_data_visible(api: AsyncClient, world: FakeWorld) -> None:
    await world.seed()
    cid = await _connect(api)
    await api.post(f"{V1}/connections/{cid}/sync")
    world.tasks["default"].unavailable = True
    await api.post(f"{V1}/connections/{cid}/sync")
    assert [t["title"] for t in (await api.get(f"{V1}/tasks")).json()] == ["Write report"]
