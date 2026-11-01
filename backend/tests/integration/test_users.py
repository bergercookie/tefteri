"""Admin-only user management and no self-registration."""

from collections.abc import Awaitable, Callable

from httpx import AsyncClient

from tests.conftest import V1

MakeUser = Callable[..., Awaitable[AsyncClient]]


async def test_admin_creates_lists_updates_and_deletes_users(api: AsyncClient) -> None:
    created = await api.post(
        f"{V1}/users",
        json={"username": "sam", "password": "long enough pw", "timezone": "Europe/London"},
    )
    assert created.status_code == 201
    user = created.json()
    assert (
        user["is_admin"] is False and "password" not in created.text and "hash" not in created.text
    )
    names = [u["username"] for u in (await api.get(f"{V1}/users")).json()]
    assert names == ["admin", "sam"]
    patched = await api.patch(f"{V1}/users/{user['id']}", json={"timezone": "Asia/Tokyo"})
    assert patched.json()["timezone"] == "Asia/Tokyo"
    assert (await api.delete(f"{V1}/users/{user['id']}")).status_code == 204
    assert [u["username"] for u in (await api.get(f"{V1}/users")).json()] == ["admin"]


async def test_validation_and_duplicates(api: AsyncClient) -> None:
    short = await api.post(f"{V1}/users", json={"username": "sam", "password": "short"})
    assert short.status_code == 422 and short.json()["code"] == "invalid"
    await api.post(f"{V1}/users", json={"username": "Sam", "password": "long enough pw"})
    dup = await api.post(f"{V1}/users", json={"username": "sam", "password": "long enough pw"})
    assert dup.status_code == 409 and dup.json()["code"] == "username_taken"  # case-insensitive


async def test_non_admins_are_refused_and_there_is_no_self_registration(
    api: AsyncClient, client: AsyncClient, make_user: MakeUser
) -> None:
    sam = await make_user("sam")
    for call in (
        sam.get(f"{V1}/users"),
        sam.post(f"{V1}/users", json={"username": "x", "password": "long enough pw"}),
        sam.patch(f"{V1}/users/00000000-0000-0000-0000-000000000000", json={"disabled": True}),
        sam.delete(f"{V1}/users/00000000-0000-0000-0000-000000000000"),
    ):
        r = await call
        assert r.status_code == 403 and r.json()["code"] == "forbidden"
    # a signed-out visitor cannot create accounts, and no public sign-up route exists
    anonymous = await client.post(
        f"{V1}/users", json={"username": "x", "password": "long enough pw"}
    )
    assert anonymous.status_code == 401
    paths = (await client.get("/openapi.json")).json()["paths"]
    assert not [p for p in paths if "register" in p or "signup" in p]


async def test_admin_cannot_lock_themselves_or_the_last_admin_out(api: AsyncClient) -> None:
    me = (await api.get(f"{V1}/auth/me")).json()
    for body in ({"disabled": True}, {"is_admin": False}):
        r = await api.patch(f"{V1}/users/{me['id']}", json=body)
        assert r.status_code == 409 and r.json()["code"] == "not_allowed"
    assert (await api.delete(f"{V1}/users/{me['id']}")).status_code == 409


async def test_second_admin_allows_demotion_of_the_first(
    api: AsyncClient, make_user: MakeUser
) -> None:
    other = await make_user("boss", is_admin=True)
    me = (await api.get(f"{V1}/auth/me")).json()
    demoted = await other.patch(f"{V1}/users/{me['id']}", json={"is_admin": False})
    assert demoted.status_code == 200 and demoted.json()["is_admin"] is False
    last = await other.patch(
        f"{V1}/users/{(await other.get(f'{V1}/auth/me')).json()['id']}", json={"is_admin": False}
    )
    assert last.status_code == 409  # now the only administrator
