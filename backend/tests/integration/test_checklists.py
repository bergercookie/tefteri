"""Planning checklists: defined in the settings, ticked once per week, month or year."""

from httpx import AsyncClient

from tests.conftest import V1

LISTS = {
    "week": ["Review the calendar", "Clear the inbox", "Check the goals"],
    "month": ["Pay the bills"],
    "year": [],
}


async def _define(api: AsyncClient, lists: dict[str, list[str]] | None = None) -> None:
    r = await api.patch(f"{V1}/me/settings", json={"checklists": lists or LISTS})
    assert r.status_code == 200, r.text


async def _tick(api: AsyncClient, day: str, text: str, checked: bool = True, kind: str = "week"):  # type: ignore[no-untyped-def]
    return await api.put(
        f"{V1}/checklists/{kind}/{day}/items", json={"text": text, "checked": checked}
    )


async def test_no_checklist_is_defined_at_first(api: AsyncClient) -> None:
    assert (await api.get(f"{V1}/me/settings")).json()["checklists"] == {
        "week": [],
        "month": [],
        "year": [],
    }
    r = await api.get(f"{V1}/checklists/week/2026-11-04")
    assert r.status_code == 200
    assert r.json() == {
        "period_type": "week",
        "period_start": "2026-11-02",
        "items": [],
        "done": 0,
        "total": 0,
    }


async def test_the_lists_are_stored_cleaned_and_replaced_one_at_a_time(
    api: AsyncClient,
) -> None:
    await _define(
        api, {"week": ["  Review   the calendar ", "", "review the calendar", "Clear the inbox"]}
    )
    lists = (await api.get(f"{V1}/me/settings")).json()["checklists"]
    # Spaces are trimmed, the empty line and the repeat (case does not count) are dropped.
    assert lists["week"] == ["Review the calendar", "Clear the inbox"]
    await _define(api, {"month": ["Pay the bills"]})  # the week list stays
    lists = (await api.get(f"{V1}/me/settings")).json()["checklists"]
    assert lists["week"] == ["Review the calendar", "Clear the inbox"]
    assert lists["month"] == ["Pay the bills"]
    await _define(api, {"week": []})  # an empty list removes the checklist
    assert (await api.get(f"{V1}/me/settings")).json()["checklists"]["week"] == []
    # Changing another setting leaves the lists alone.
    await api.patch(f"{V1}/me/settings", json={"random_time_on_date_drop": True})
    assert (await api.get(f"{V1}/me/settings")).json()["checklists"]["month"] == ["Pay the bills"]


async def test_the_lists_have_limits(api: AsyncClient) -> None:
    too_many = await api.patch(
        f"{V1}/me/settings", json={"checklists": {"week": [f"Item {n}" for n in range(51)]}}
    )
    assert too_many.status_code == 422
    too_long = await api.patch(f"{V1}/me/settings", json={"checklists": {"week": ["x" * 201]}})
    assert too_long.status_code == 422
    unknown = await api.patch(f"{V1}/me/settings", json={"checklists": {"decade": ["x"]}})
    assert unknown.status_code == 422
    fifty = await api.patch(
        f"{V1}/me/settings", json={"checklists": {"week": [f"Item {n}" for n in range(50)]}}
    )
    assert fifty.status_code == 200


async def test_ticking_items_and_the_count(api: AsyncClient) -> None:
    await _define(api)
    got = (await api.get(f"{V1}/checklists/week/2026-11-04")).json()
    assert [(i["text"], i["checked"]) for i in got["items"]] == [
        ("Review the calendar", False),
        ("Clear the inbox", False),
        ("Check the goals", False),
    ]
    assert got["done"] == 0 and got["total"] == 3

    one = (await _tick(api, "2026-11-04", "Clear the inbox")).json()
    assert one["done"] == 1 and [i["checked"] for i in one["items"]] == [False, True, False]
    two = (await _tick(api, "2026-11-04", "Review the calendar")).json()
    assert two["done"] == 2
    again = (await _tick(api, "2026-11-04", "Review the calendar")).json()
    assert again["done"] == 2  # ticking twice changes nothing
    off = (await _tick(api, "2026-11-04", "Clear the inbox", False)).json()
    assert off["done"] == 1 and [i["checked"] for i in off["items"]] == [True, False, False]
    # It is stored: a new read shows the same.
    assert (await api.get(f"{V1}/checklists/week/2026-11-04")).json()["done"] == 1


async def test_any_day_of_the_period_gives_the_same_checklist(api: AsyncClient) -> None:
    await _define(api)
    await _tick(api, "2026-11-02", "Check the goals")  # the Monday
    for day in ("2026-11-04", "2026-11-08"):  # Wednesday and Sunday of that week
        r = (await api.get(f"{V1}/checklists/week/{day}")).json()
        assert r["period_start"] == "2026-11-02" and r["done"] == 1
    month = (await api.get(f"{V1}/checklists/month/2026-11-30")).json()
    assert month["period_start"] == "2026-11-01"
    year = (await api.get(f"{V1}/checklists/year/2026-06-15")).json()
    assert year["period_start"] == "2026-01-01" and year["total"] == 0


async def test_the_next_period_starts_with_a_clean_list(api: AsyncClient) -> None:
    await _define(api)
    for item in LISTS["week"]:
        await _tick(api, "2026-11-04", item)
    assert (await api.get(f"{V1}/checklists/week/2026-11-04")).json()["done"] == 3
    next_week = (await api.get(f"{V1}/checklists/week/2026-11-09")).json()
    assert next_week["done"] == 0 and next_week["total"] == 3
    # The week before keeps what was ticked in it.
    await _tick(api, "2026-11-11", "Clear the inbox")
    assert (await api.get(f"{V1}/checklists/week/2026-11-04")).json()["done"] == 3
    assert (await api.get(f"{V1}/checklists/week/2026-11-11")).json()["done"] == 1


async def test_the_three_kinds_are_separate(api: AsyncClient) -> None:
    await _define(api)
    await _tick(api, "2026-11-04", "Pay the bills", kind="month")
    assert (await api.get(f"{V1}/checklists/month/2026-11-04")).json()["done"] == 1
    assert (await api.get(f"{V1}/checklists/week/2026-11-04")).json()["done"] == 0


async def test_an_edited_list_keeps_the_ticks_of_the_items_that_stayed(
    api: AsyncClient,
) -> None:
    await _define(api)
    await _tick(api, "2026-11-04", "Clear the inbox")
    await _tick(api, "2026-11-04", "Check the goals")
    # Rename one item, remove another, add a new one.
    await _define(api, {"week": ["Clear the inbox", "Look at the goals", "Plan the meals"]})
    got = (await api.get(f"{V1}/checklists/week/2026-11-04")).json()
    assert [(i["text"], i["checked"]) for i in got["items"]] == [
        ("Clear the inbox", True),
        ("Look at the goals", False),  # a renamed item starts unticked
        ("Plan the meals", False),
    ]
    assert got["done"] == 1 and got["total"] == 3
    # The old tick does not come back if the old text is added again.
    await _tick(api, "2026-11-04", "Plan the meals")
    await _define(api, {"week": ["Clear the inbox", "Check the goals", "Plan the meals"]})
    got = (await api.get(f"{V1}/checklists/week/2026-11-04")).json()
    assert [i["checked"] for i in got["items"]] == [True, False, True]


async def test_an_unknown_item_cannot_be_ticked(api: AsyncClient) -> None:
    await _define(api)
    r = await _tick(api, "2026-11-04", "Something else")
    assert r.status_code == 422 and "not in the checklist" in r.json()["detail"]
    empty = await _tick(api, "2026-11-04", "")
    assert empty.status_code == 422
    nothing = await _tick(api, "2026-11-04", "Pay the bills", kind="year")
    assert nothing.status_code == 422  # it is a month item, not a year item


async def test_bad_period_or_day_is_refused(api: AsyncClient) -> None:
    assert (await api.get(f"{V1}/checklists/decade/2026-11-04")).status_code == 422
    assert (await api.get(f"{V1}/checklists/week/not-a-day")).status_code == 422


async def test_checklists_are_per_user_and_need_a_session(api: AsyncClient) -> None:
    await _define(api)
    await _tick(api, "2026-11-04", "Clear the inbox")
    created = await api.post(f"{V1}/users", json={"username": "sam", "password": "sam-password-1"})
    assert created.status_code == 201
    login = await api.post(
        f"{V1}/auth/login", json={"username": "sam", "password": "sam-password-1"}
    )
    sam = {"Authorization": f"Bearer {login.json()['token']}"}
    theirs = (await api.get(f"{V1}/checklists/week/2026-11-04", headers=sam)).json()
    assert theirs["total"] == 0 and theirs["done"] == 0
    settings = (await api.get(f"{V1}/me/settings", headers=sam)).json()
    assert settings["checklists"]["week"] == []

    api.headers.pop("Authorization", None)
    api.cookies.clear()
    assert (await api.get(f"{V1}/checklists/week/2026-11-04")).status_code == 401
