"""context=work|life|all filters tasks, entries, notes and views with zero leakage."""

from datetime import UTC, datetime

from httpx import AsyncClient

from tefteri.domain.entities import EntryDraft, NoteDraft
from tests.conftest import V1, connect_all
from tests.fakes.world import FakeWorld


async def _setup(api: AsyncClient, world: FakeWorld) -> dict[str, str]:
    ids = await connect_all(api, default_context="life")
    await api.post(f"{V1}/sync")
    nine = datetime(2026, 11, 2, 9, tzinfo=UTC)
    await world.calendars["default"].create_entry(
        EntryDraft("cal1", "Life event", nine, nine.replace(minute=30))
    )
    await world.calendars["default"].create_entry(
        EntryDraft("cal1", "Work event", nine.replace(hour=11), nine.replace(hour=12))
    )
    await world.notes["default"].create_note(NoteDraft("Plain note"))
    await api.post(f"{V1}/sync")
    return ids


async def test_filters_have_zero_leakage(api: AsyncClient, world: FakeWorld) -> None:
    ids = await _setup(api, world)
    life = (
        await api.post(f"{V1}/tasks", json={"connection_id": ids["vikunja"], "title": "Life task"})
    ).json()
    work = (
        await api.post(f"{V1}/tasks", json={"connection_id": ids["vikunja"], "title": "Work task"})
    ).json()
    await api.patch(f"{V1}/tasks/{work['id']}", json={"context": "work"})
    entries = (await api.get(f"{V1}/calendar")).json()
    work_entry = next(i for i in entries if i["title"] == "Work event")
    await api.patch(f"{V1}/calendar/entries/{work_entry['id']}", json={"context": "work"})
    note = (await api.get(f"{V1}/notes")).json()[0]
    assert note["effective_context"] == "life"

    def titles(items: list[dict[str, object]]) -> set[object]:
        return {i["title"] for i in items}

    for path in ("tasks", "calendar", "notes", "views/day/2026-11-02"):
        everything = (await api.get(f"{V1}/{path}", params={"context": "all"})).json()
        only_work = (await api.get(f"{V1}/{path}", params={"context": "work"})).json()
        only_life = (await api.get(f"{V1}/{path}", params={"context": "life"})).json()
        if path.startswith("views"):
            for key in ("entries", "tasks"):
                assert not titles(only_work[key]) & titles(only_life[key])
                assert titles(only_work[key]) | titles(only_life[key]) == titles(everything[key])
            continue
        assert not titles(only_work) & titles(only_life)
        assert titles(only_work) | titles(only_life) == titles(everything)
    assert titles((await api.get(f"{V1}/tasks", params={"context": "work"})).json()) == {
        "Work task"
    }
    assert life["context"] is None


async def test_container_label_applies_and_item_override_wins(
    api: AsyncClient, world: FakeWorld
) -> None:
    ids = await _setup(api, world)
    containers = (await api.get(f"{V1}/connections/{ids['vikunja']}/containers")).json()
    cid = containers[0]["id"]
    labelled = await api.patch(
        f"{V1}/connections/{ids['vikunja']}/containers/{cid}", json={"context": "work"}
    )
    assert labelled.json()["context"] == "work"
    t = (await api.post(f"{V1}/tasks", json={"connection_id": ids["vikunja"], "title": "T"})).json()
    assert t["effective_context"] == "work" and t["context"] is None  # unclassified item
    overridden = await api.patch(f"{V1}/tasks/{t['id']}", json={"context": "life"})
    assert overridden.json()["effective_context"] == "life"
    cleared = await api.patch(f"{V1}/tasks/{t['id']}", json={"context": None})
    assert cleared.json()["effective_context"] == "work"
    missing = await api.patch(
        f"{V1}/connections/{ids['vikunja']}/containers/00000000-0000-0000-0000-000000000000",
        json={"context": "work"},
    )
    assert missing.status_code == 404
