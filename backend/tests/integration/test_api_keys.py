"""API keys: make one, use it like a login, revoke it, and what it may not do."""

from datetime import UTC, datetime, timedelta

from httpx import ASGITransport, AsyncClient
from sqlalchemy import select

from tefteri.db.models.api_key import ApiKey
from tefteri.db.session import session_scope
from tests.conftest import ADMIN_PASSWORD, V1


async def _make(api: AsyncClient, name: str = "Claude Desktop") -> dict[str, str]:
    r = await api.post(f"{V1}/me/api-keys", json={"name": name})
    assert r.status_code == 201, r.text
    body: dict[str, str] = r.json()
    return body


def _as(api: AsyncClient, key: str | None) -> AsyncClient:
    """The same app, with no login of its own and, if given, this API key."""
    app = api.app  # type: ignore[attr-defined]
    headers = {"Authorization": f"Bearer {key}"} if key else {}
    return AsyncClient(transport=ASGITransport(app=app), base_url="http://test", headers=headers)


async def test_a_new_key_is_shown_once_and_listed_without_the_key(api: AsyncClient) -> None:
    created = await _make(api)
    assert created["key"].startswith("tft_") and len(created["key"]) > 30
    assert created["name"] == "Claude Desktop" and created["last_used_at"] is None
    assert created["prefix"] == created["key"][:10]
    listed = (await api.get(f"{V1}/me/api-keys")).json()
    assert [k["name"] for k in listed] == ["Claude Desktop"]
    assert "key" not in listed[0] and created["key"] not in str(listed)


async def test_only_the_digest_of_the_key_is_stored(api: AsyncClient) -> None:
    created = await _make(api)
    async with session_scope(api.app.state.session_factory) as db:  # type: ignore[attr-defined]
        row = (await db.execute(select(ApiKey))).scalar_one()
    assert row.token_hash != created["key"] and len(row.token_hash) == 64
    assert created["key"] not in (row.name, row.prefix, row.token_hash)


async def test_a_key_works_like_a_login_and_notes_when_it_was_used(api: AsyncClient) -> None:
    key = (await _make(api))["key"]
    async with _as(api, key) as tool:
        me = await tool.get(f"{V1}/auth/me")
        assert me.status_code == 200 and me.json()["username"] == "admin"
        assert (await tool.get(f"{V1}/tasks", params={"due": "all"})).status_code == 200
    used = (await api.get(f"{V1}/me/api-keys")).json()[0]["last_used_at"]
    assert used is not None


async def test_a_wrong_or_revoked_key_is_refused(api: AsyncClient) -> None:
    key = (await _make(api))["key"]
    async with _as(api, "tft_not-a-real-key") as tool:
        assert (await tool.get(f"{V1}/auth/me")).status_code == 401
    key_id = (await api.get(f"{V1}/me/api-keys")).json()[0]["id"]
    assert (await api.delete(f"{V1}/me/api-keys/{key_id}")).status_code == 204
    async with _as(api, key) as tool:
        assert (await tool.get(f"{V1}/auth/me")).status_code == 401  # signed out at once
    assert (await api.get(f"{V1}/me/api-keys")).json() == []
    assert (await api.delete(f"{V1}/me/api-keys/{key_id}")).status_code == 404


async def test_a_key_cannot_make_keys_change_the_password_or_export_credentials(
    api: AsyncClient,
) -> None:
    key = (await _make(api))["key"]
    async with _as(api, key) as tool:
        for call in (
            tool.get(f"{V1}/me/api-keys"),
            tool.post(f"{V1}/me/api-keys", json={"name": "More"}),
            tool.post(
                f"{V1}/auth/password",
                json={"current_password": ADMIN_PASSWORD, "new_password": "another good one 1"},
            ),
            tool.get(f"{V1}/me/settings/export", params={"include_connections": True}),
            tool.get(f"{V1}/users"),
        ):
            r = await call
            assert r.status_code == 403 and r.json()["code"] == "api_key_not_allowed", r.text
    assert len((await api.get(f"{V1}/me/api-keys")).json()) == 1


async def test_a_key_can_read_and_change_the_planning_data(api: AsyncClient) -> None:
    key = (await _make(api))["key"]
    async with _as(api, key) as tool:
        assert (await tool.get(f"{V1}/me/settings")).status_code == 200
        r = await tool.patch(f"{V1}/me/settings", json={"event_reminder_minutes": 25})
        assert r.status_code == 200 and r.json()["event_reminder_minutes"] == 25


async def test_keys_are_per_user_and_need_a_login_to_manage(api: AsyncClient) -> None:
    await _make(api, "Mine")
    async with _as(api, None) as nobody:
        assert (await nobody.get(f"{V1}/me/api-keys")).status_code == 401
        assert (await nobody.post(f"{V1}/me/api-keys", json={"name": "x"})).status_code == 401
    created = await api.post(
        f"{V1}/users", json={"username": "sam", "password": "a strong pass 12"}
    )
    assert created.status_code == 201, created.text
    login = await api.post(
        f"{V1}/auth/login", json={"username": "sam", "password": "a strong pass 12"}
    )
    async with _as(api, login.json()["token"]) as sam:
        assert (await sam.get(f"{V1}/me/api-keys")).json() == []
        other = (await api.get(f"{V1}/me/api-keys")).json()[0]["id"]
        assert (await sam.delete(f"{V1}/me/api-keys/{other}")).status_code == 404
    assert len((await api.get(f"{V1}/me/api-keys")).json()) == 1


async def test_a_disabled_user_cannot_use_their_key(api: AsyncClient) -> None:
    created = await api.post(
        f"{V1}/users", json={"username": "sam", "password": "a strong pass 12"}
    )
    login = await api.post(
        f"{V1}/auth/login", json={"username": "sam", "password": "a strong pass 12"}
    )
    async with _as(api, login.json()["token"]) as sam:
        key = (await sam.post(f"{V1}/me/api-keys", json={"name": "Sam's"})).json()["key"]
    patched = await api.patch(f"{V1}/users/{created.json()['id']}", json={"disabled": True})
    assert patched.status_code == 200, patched.text
    async with _as(api, key) as tool:
        assert (await tool.get(f"{V1}/auth/me")).status_code == 401


async def test_the_name_is_needed_and_the_number_of_keys_is_limited(api: AsyncClient) -> None:
    assert (await api.post(f"{V1}/me/api-keys", json={"name": "  "})).status_code == 422
    assert (await api.post(f"{V1}/me/api-keys", json={})).status_code == 422
    for n in range(20):
        await _make(api, f"Key {n}")
    over = await api.post(f"{V1}/me/api-keys", json={"name": "One too many"})
    assert over.status_code == 422 and over.json()["code"] == "too_many_keys"


async def test_the_last_use_is_written_at_most_once_a_minute(api: AsyncClient) -> None:
    key = (await _make(api))["key"]
    app = api.app  # type: ignore[attr-defined]
    start = datetime(2030, 3, 1, 9, tzinfo=UTC)
    auth = app.state.auth_service
    auth._clock = lambda: start  # noqa: SLF001
    async with _as(api, key) as tool:
        await tool.get(f"{V1}/auth/me")
        auth._clock = lambda: start + timedelta(seconds=20)  # noqa: SLF001
        await tool.get(f"{V1}/auth/me")
    auth._clock = lambda: datetime.now(UTC)  # noqa: SLF001 - the real clock again
    shown = (await api.get(f"{V1}/me/api-keys")).json()[0]["last_used_at"]
    assert shown.startswith("2030-03-01T09:00:00")  # the second use came too soon to write
