"""Per-user settings: the random time for date-only drops and the default reminder."""

from httpx import AsyncClient

from tests.conftest import V1

OFF = {"random_time_on_date_drop": False, "default_reminder_minutes": 15}


async def test_default_is_off_and_patch_changes_it(api: AsyncClient) -> None:
    assert (await api.get(f"{V1}/me/settings")).json() == OFF
    on = await api.patch(f"{V1}/me/settings", json={"random_time_on_date_drop": True})
    assert on.json() == {**OFF, "random_time_on_date_drop": True}
    assert (await api.get(f"{V1}/me/settings")).json() == {**OFF, "random_time_on_date_drop": True}
    off = await api.patch(f"{V1}/me/settings", json={"random_time_on_date_drop": False})
    assert off.json() == OFF


async def test_empty_patch_changes_nothing_and_unknown_fields_are_refused(
    api: AsyncClient,
) -> None:
    await api.patch(f"{V1}/me/settings", json={"random_time_on_date_drop": True})
    assert (await api.patch(f"{V1}/me/settings", json={})).json() == {
        **OFF,
        "random_time_on_date_drop": True,
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
    assert (await api.get(f"{V1}/me/settings", headers=sam)).json() == OFF

    api.headers.pop("Authorization", None)
    api.cookies.clear()  # the web client also signs in with a session cookie
    assert (await api.get(f"{V1}/me/settings")).status_code == 401


async def test_default_reminder_is_15_minutes_and_can_be_changed(api: AsyncClient) -> None:
    assert (await api.get(f"{V1}/me/settings")).json()["default_reminder_minutes"] == 15
    changed = await api.patch(f"{V1}/me/settings", json={"default_reminder_minutes": 45})
    assert changed.json() == {**OFF, "default_reminder_minutes": 45}
    assert (await api.get(f"{V1}/me/settings")).json()["default_reminder_minutes"] == 45
    # Changing the other setting leaves it alone; 0 means "at the due time".
    await api.patch(f"{V1}/me/settings", json={"random_time_on_date_drop": True})
    assert (await api.get(f"{V1}/me/settings")).json()["default_reminder_minutes"] == 45
    zero = await api.patch(f"{V1}/me/settings", json={"default_reminder_minutes": 0})
    assert zero.json()["default_reminder_minutes"] == 0


async def test_default_reminder_must_be_within_a_week(api: AsyncClient) -> None:
    for bad in (-1, 7 * 24 * 60 + 1):
        r = await api.patch(f"{V1}/me/settings", json={"default_reminder_minutes": bad})
        assert r.status_code == 422
    ok = await api.patch(f"{V1}/me/settings", json={"default_reminder_minutes": 7 * 24 * 60})
    assert ok.status_code == 200
