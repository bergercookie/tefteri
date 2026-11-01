"""Password sign-in for admin-created users, disabled accounts and password changes."""

from collections.abc import Awaitable, Callable

from httpx import AsyncClient

from tests.conftest import V1

MakeUser = Callable[..., Awaitable[AsyncClient]]


async def test_methods_endpoint_lists_password_only(client: AsyncClient) -> None:
    assert (await client.get(f"{V1}/auth/methods")).json() == {"password": True}


async def test_created_user_signs_in_with_the_password_the_admin_set(
    api: AsyncClient, make_user: MakeUser
) -> None:
    sam = await make_user("sam", "sams own password")
    me = (await sam.get(f"{V1}/auth/me")).json()
    assert me["username"] == "sam" and me["is_admin"] is False
    wrong = await api.post(f"{V1}/auth/login", json={"username": "sam", "password": "nope nope"})
    assert wrong.status_code == 401


async def test_disabled_user_cannot_sign_in_and_sessions_end(
    api: AsyncClient, make_user: MakeUser
) -> None:
    sam = await make_user("sam", "sams own password")
    sam_id = (await sam.get(f"{V1}/auth/me")).json()["id"]
    await api.patch(f"{V1}/users/{sam_id}", json={"disabled": True})
    assert (await sam.get(f"{V1}/auth/me")).status_code == 401  # open session ends
    again = await api.post(
        f"{V1}/auth/login", json={"username": "sam", "password": "sams own password"}
    )
    assert again.status_code == 401
    await api.patch(f"{V1}/users/{sam_id}", json={"disabled": False})
    ok = await api.post(
        f"{V1}/auth/login", json={"username": "sam", "password": "sams own password"}
    )
    assert ok.status_code == 200


async def test_user_changes_own_password_and_other_sessions_end(
    api: AsyncClient, make_user: MakeUser
) -> None:
    sam = await make_user("sam", "sams own password")
    other = await api.post(
        f"{V1}/auth/login", json={"username": "sam", "password": "sams own password"}
    )
    other_headers = {"Authorization": f"Bearer {other.json()['token']}"}

    wrong = await sam.post(
        f"{V1}/auth/password", json={"current_password": "bad", "new_password": "a new password"}
    )
    assert wrong.status_code == 401 and wrong.json()["code"] == "invalid_credentials"
    short = await sam.post(
        f"{V1}/auth/password",
        json={"current_password": "sams own password", "new_password": "short"},
    )
    assert short.status_code == 422

    done = await sam.post(
        f"{V1}/auth/password",
        json={"current_password": "sams own password", "new_password": "a new password"},
    )
    assert done.status_code == 204
    assert (await sam.get(f"{V1}/auth/me")).status_code == 200  # this session stays
    assert (await api.get(f"{V1}/auth/me", headers=other_headers)).status_code == 401
    old = await api.post(
        f"{V1}/auth/login", json={"username": "sam", "password": "sams own password"}
    )
    assert old.status_code == 401
    new = await api.post(f"{V1}/auth/login", json={"username": "sam", "password": "a new password"})
    assert new.status_code == 200


async def test_admin_resets_a_forgotten_password(api: AsyncClient, make_user: MakeUser) -> None:
    sam = await make_user("sam", "sams own password")
    sam_id = (await sam.get(f"{V1}/auth/me")).json()["id"]
    reset = await api.patch(f"{V1}/users/{sam_id}", json={"password": "reset by admin"})
    assert reset.status_code == 200
    ok = await api.post(f"{V1}/auth/login", json={"username": "sam", "password": "reset by admin"})
    assert ok.status_code == 200
    too_short = await api.patch(f"{V1}/users/{sam_id}", json={"password": "short"})
    assert too_short.status_code == 422
