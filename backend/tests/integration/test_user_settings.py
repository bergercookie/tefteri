"""Per-user settings: the random time for date-only drops and the default reminder."""

from collections.abc import Awaitable, Callable

from httpx import AsyncClient

from tefteri.domain.entities import Container
from tests.conftest import V1
from tests.fakes.world import FakeWorld

OFF = {
    "random_time_on_date_drop": False,
    "default_reminder_minutes": 15,
    "checklists": {"week": [], "month": [], "year": []},
    "checklist_sources": {"week": "", "month": "", "year": ""},
    "default_event_container_id": None,
    "event_invitees": [],
}


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


async def test_checklist_sources_are_cleaned_and_can_be_cleared(api: AsyncClient) -> None:
    r = await api.patch(
        f"{V1}/me/settings",
        json={"checklist_sources": {"week": "  Checklists /  Weekly  "}},
    )
    assert r.status_code == 200, r.text
    assert r.json()["checklist_sources"] == {
        "week": "Checklists /  Weekly",
        "month": "",
        "year": "",
    }
    # A path for another kind leaves the first one alone.
    await api.patch(f"{V1}/me/settings", json={"checklist_sources": {"year": "Annual"}})
    got = (await api.get(f"{V1}/me/settings")).json()["checklist_sources"]
    assert got == {"week": "Checklists /  Weekly", "month": "", "year": "Annual"}
    # An empty path brings the local list back.
    cleared = await api.patch(f"{V1}/me/settings", json={"checklist_sources": {"week": ""}})
    assert cleared.json()["checklist_sources"]["week"] == ""
    too_long = await api.patch(f"{V1}/me/settings", json={"checklist_sources": {"week": "x" * 501}})
    assert too_long.status_code == 422
    unknown = await api.patch(f"{V1}/me/settings", json={"checklist_sources": {"decade": "x"}})
    assert unknown.status_code == 422


async def test_default_event_calendar_is_chosen_and_cleared(
    api: AsyncClient, world: FakeWorld
) -> None:
    world.calendars["default"].containers = [Container("work", "Work")]
    connection = await api.post(
        f"{V1}/connections",
        json={
            "provider": "google_calendar",
            "display_name": "G",
            "settings": {},
            "credentials": {"token": "t"},
        },
    )
    calendar = (await api.get(f"{V1}/connections/{connection.json()['id']}/containers")).json()[0]
    chosen = await api.patch(
        f"{V1}/me/settings", json={"default_event_container_id": calendar["id"]}
    )
    assert chosen.status_code == 200, chosen.text
    assert chosen.json()["default_event_container_id"] == calendar["id"]
    # Another setting leaves the choice alone; an explicit null clears it.
    await api.patch(f"{V1}/me/settings", json={"random_time_on_date_drop": True})
    assert (await api.get(f"{V1}/me/settings")).json()["default_event_container_id"] == (
        calendar["id"]
    )
    cleared = await api.patch(f"{V1}/me/settings", json={"default_event_container_id": None})
    assert cleared.json()["default_event_container_id"] is None


async def test_default_event_calendar_must_be_a_calendar_of_the_user(api: AsyncClient) -> None:
    unknown = await api.patch(
        f"{V1}/me/settings",
        json={"default_event_container_id": "00000000-0000-0000-0000-000000000001"},
    )
    assert unknown.status_code == 422
    assert unknown.json()["code"] == "unknown_calendar"


async def test_export_then_import_restores_the_settings(api: AsyncClient) -> None:
    await api.patch(
        f"{V1}/me/settings",
        json={
            "random_time_on_date_drop": True,
            "default_reminder_minutes": 45,
            "checklists": {"week": ["Review inbox", "Plan focus"], "year": ["Set goals"]},
            "checklist_sources": {"month": "Notes/Monthly"},
        },
    )
    exported = (await api.get(f"{V1}/me/settings/export")).json()
    assert exported["format"] == "tefteri-settings"
    assert exported["version"] == 1
    assert "default_event_container_id" not in exported["settings"]
    # Connections and their credentials are in the file only when the user asks for them.
    assert exported["connections"] is None
    assert exported["default_event_calendar"] is None
    assert exported["settings"]["checklists"] == {
        "week": ["Review inbox", "Plan focus"],
        "month": [],
        "year": ["Set goals"],
    }

    await api.patch(
        f"{V1}/me/settings",
        json={
            "random_time_on_date_drop": False,
            "default_reminder_minutes": 0,
            "checklists": {"week": ["Other"]},
            "checklist_sources": {"month": ""},
        },
    )
    imported = await api.post(f"{V1}/me/settings/import", json=exported)
    assert imported.status_code == 200
    restored = (await api.get(f"{V1}/me/settings")).json()
    assert imported.json() == {"settings": restored, "connections": None}
    assert restored["random_time_on_date_drop"] is True
    assert restored["default_reminder_minutes"] == 45
    assert restored["checklists"]["week"] == ["Review inbox", "Plan focus"]
    assert restored["checklist_sources"]["month"] == "Notes/Monthly"
    assert (await api.get(f"{V1}/me/settings/export")).json() == exported


async def test_import_into_another_account(api: AsyncClient) -> None:
    await api.patch(f"{V1}/me/settings", json={"default_reminder_minutes": 60})
    exported = (await api.get(f"{V1}/me/settings/export")).json()
    await api.post(f"{V1}/users", json={"username": "sam", "password": "sam-password-1"})
    token = (
        await api.post(f"{V1}/auth/login", json={"username": "sam", "password": "sam-password-1"})
    ).json()["token"]
    sam = {"Authorization": f"Bearer {token}"}
    done = await api.post(f"{V1}/me/settings/import", json=exported, headers=sam)
    assert done.json()["settings"]["default_reminder_minutes"] == 60


async def test_import_keeps_what_the_file_leaves_out(api: AsyncClient) -> None:
    await api.patch(
        f"{V1}/me/settings",
        json={"random_time_on_date_drop": True, "checklists": {"week": ["Keep me"]}},
    )
    file = {
        "format": "tefteri-settings",
        "version": 1,
        "settings": {"default_reminder_minutes": 30},
    }
    got = (await api.post(f"{V1}/me/settings/import", json=file)).json()["settings"]
    assert got["default_reminder_minutes"] == 30
    assert got["random_time_on_date_drop"] is True
    assert got["checklists"]["week"] == ["Keep me"]


async def test_import_refuses_a_wrong_or_invalid_file_and_changes_nothing(
    api: AsyncClient,
) -> None:
    await api.patch(f"{V1}/me/settings", json={"default_reminder_minutes": 45})
    bad_files = [
        {"format": "other", "version": 1, "settings": {}},
        {"format": "tefteri-settings", "version": 2, "settings": {}},
        {"format": "tefteri-settings", "version": 1},
        {"format": "tefteri-settings", "version": 1, "settings": {"is_admin": True}},
        {"format": "tefteri-settings", "version": 1, "settings": {"default_reminder_minutes": -1}},
        {
            "format": "tefteri-settings",
            "version": 1,
            "settings": {"random_time_on_date_drop": True, "default_reminder_minutes": 10**9},
        },
    ]
    for bad in bad_files:
        assert (await api.post(f"{V1}/me/settings/import", json=bad)).status_code == 422, bad
    after = (await api.get(f"{V1}/me/settings")).json()
    assert after["default_reminder_minutes"] == 45
    assert after["random_time_on_date_drop"] is False


async def test_export_and_import_need_a_session(api: AsyncClient) -> None:
    file = {"format": "tefteri-settings", "version": 1, "settings": {}}
    api.headers.pop("Authorization", None)
    api.cookies.clear()
    assert (await api.get(f"{V1}/me/settings/export")).status_code == 401
    assert (await api.post(f"{V1}/me/settings/import", json=file)).status_code == 401


async def _google(api: AsyncClient, name: str = "G") -> dict[str, str]:
    r = await api.post(
        f"{V1}/connections",
        json={
            "provider": "google_calendar",
            "display_name": name,
            "settings": {"k": "v"},
            "credentials": {"refresh_token": "secret-token"},
        },
    )
    assert r.status_code == 201, r.text
    return r.json()  # type: ignore[no-any-return]


async def test_export_holds_connections_only_when_asked(api: AsyncClient, world: FakeWorld) -> None:
    world.calendars["default"].containers = [Container("work", "Work")]
    connection = await _google(api)
    calendar = (await api.get(f"{V1}/connections/{connection['id']}/containers")).json()[0]
    await api.patch(f"{V1}/me/settings", json={"default_event_container_id": calendar["id"]})

    plain = (await api.get(f"{V1}/me/settings/export")).json()
    assert plain["connections"] is None
    assert "secret-token" not in str(plain)

    full = (await api.get(f"{V1}/me/settings/export", params={"include_connections": True})).json()
    assert full["connections"] == [
        {
            "provider": "google_calendar",
            "display_name": "G",
            "settings": {"k": "v"},
            "credentials": {"refresh_token": "secret-token"},
        }
    ]
    assert full["default_event_calendar"] == {"connection": "G", "remote_id": "work"}


async def test_import_adds_connections_and_restores_the_calendar(
    api: AsyncClient, world: FakeWorld, make_user: Callable[..., Awaitable[AsyncClient]]
) -> None:
    world.calendars["default"].containers = [Container("work", "Work")]
    connection = await _google(api)
    calendar = (await api.get(f"{V1}/connections/{connection['id']}/containers")).json()[0]
    await api.patch(f"{V1}/me/settings", json={"default_event_container_id": calendar["id"]})
    full = (await api.get(f"{V1}/me/settings/export", params={"include_connections": True})).json()

    sam = await make_user("sam")
    done = await sam.post(f"{V1}/me/settings/import", json=full)
    assert done.status_code == 200, done.text
    assert done.json()["connections"] == {
        "added": 1,
        "skipped": [],
        "failed": {},
        "default_event_calendar_restored": True,
    }
    mine = (await sam.get(f"{V1}/connections")).json()
    assert [(c["provider"], c["display_name"]) for c in mine] == [("google_calendar", "G")]
    sams = (await sam.get(f"{V1}/connections/{mine[0]['id']}/containers")).json()
    chosen = (await sam.get(f"{V1}/me/settings")).json()["default_event_container_id"]
    assert chosen == sams[0]["id"]
    assert chosen != calendar["id"]  # a calendar of Sam's own, not of the exporting account

    # A second import adds nothing: the connection is there already.
    again = (await sam.post(f"{V1}/me/settings/import", json=full)).json()["connections"]
    assert again["added"] == 0
    assert again["skipped"] == ["G"]
    assert len((await sam.get(f"{V1}/connections")).json()) == 1


async def test_import_reports_a_connection_that_cannot_be_added(api: AsyncClient) -> None:
    file = {
        "format": "tefteri-settings",
        "version": 1,
        "settings": {},
        "connections": [
            {"provider": "nope", "display_name": "Bad", "settings": {}, "credentials": {}},
            {"provider": "trilium", "display_name": "Notes", "settings": {}, "credentials": {}},
        ],
        "default_event_calendar": {"connection": "Notes", "remote_id": "gone"},
    }
    out = (await api.post(f"{V1}/me/settings/import", json=file)).json()["connections"]
    assert out["added"] == 1
    assert out["failed"] == {"Bad": "Unknown provider: nope"}
    assert out["default_event_calendar_restored"] is False
    names = [c["display_name"] for c in (await api.get(f"{V1}/connections")).json()]
    assert names == ["Notes"]
    assert (await api.get(f"{V1}/me/settings")).json()["default_event_container_id"] is None


async def test_import_without_connections_leaves_connections_alone(api: AsyncClient) -> None:
    await _google(api)
    file = {"format": "tefteri-settings", "version": 1, "settings": {"default_reminder_minutes": 5}}
    await api.post(f"{V1}/me/settings/import", json=file)
    assert len((await api.get(f"{V1}/connections")).json()) == 1


async def test_standard_invitees_are_cleaned_and_replace_the_old_list(api: AsyncClient) -> None:
    r = await api.patch(
        f"{V1}/me/settings",
        json={"event_invitees": [" Sam@Example.com ", "sam@example.com", "", "kim@example.org"]},
    )
    assert r.status_code == 200, r.text
    assert r.json()["event_invitees"] == ["Sam@Example.com", "kim@example.org"]
    assert (await api.get(f"{V1}/me/settings")).json()["event_invitees"] == [
        "Sam@Example.com",
        "kim@example.org",
    ]
    # A patch without the field keeps the list; an empty list clears it.
    kept = await api.patch(f"{V1}/me/settings", json={"random_time_on_date_drop": True})
    assert kept.json()["event_invitees"] == ["Sam@Example.com", "kim@example.org"]
    cleared = await api.patch(f"{V1}/me/settings", json={"event_invitees": []})
    assert cleared.json()["event_invitees"] == []


async def test_an_invitee_that_is_not_an_address_is_refused(api: AsyncClient) -> None:
    r = await api.patch(f"{V1}/me/settings", json={"event_invitees": ["sam@example.com", "sam"]})
    assert r.status_code == 422, r.text
    assert "sam is not an e-mail address" in r.text
    assert (await api.get(f"{V1}/me/settings")).json()["event_invitees"] == []
