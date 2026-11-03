"""Per-user settings: the random time for date-only drops."""

from httpx import AsyncClient

from tests.conftest import V1


async def test_default_is_off_and_patch_changes_it(api: AsyncClient) -> None:
    assert (await api.get(f"{V1}/me/settings")).json() == {"random_time_on_date_drop": False}
    on = await api.patch(f"{V1}/me/settings", json={"random_time_on_date_drop": True})
    assert on.json() == {"random_time_on_date_drop": True}
    assert (await api.get(f"{V1}/me/settings")).json() == {"random_time_on_date_drop": True}
    off = await api.patch(f"{V1}/me/settings", json={"random_time_on_date_drop": False})
    assert off.json() == {"random_time_on_date_drop": False}


async def test_empty_patch_changes_nothing_and_unknown_fields_are_refused(
    api: AsyncClient,
) -> None:
    await api.patch(f"{V1}/me/settings", json={"random_time_on_date_drop": True})
    assert (await api.patch(f"{V1}/me/settings", json={})).json() == {
        "random_time_on_date_drop": True
    }
    assert (await api.patch(f"{V1}/me/settings", json={"is_admin": True})).status_code == 422


async def test_settings_are_per_user_and_need_a_session(api: AsyncClient) -> None:
    created = await api.post(f"{V1}/users", json={"username": "sam", "password": "sam-password-1"})
    assert created.status_code == 201
    await api.patch(f"{V1}/me/settings", json={"random_time_on_date_drop": True})

    login = await api.post(
        f"{V1}/auth/login", json={"username": "sam", "password": "sam-password-1"}
    )
    token = login.json()["token"]
    sam = {"Authorization": f"Bearer {token}"}
    assert (await api.get(f"{V1}/me/settings", headers=sam)).json() == {
        "random_time_on_date_drop": False
    }

    api.headers.pop("Authorization", None)
    api.cookies.clear()  # the web client also signs in with a session cookie
    assert (await api.get(f"{V1}/me/settings")).status_code == 401
