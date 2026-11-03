"""Daily note get-or-create, append and task link; the daily view."""

from httpx import AsyncClient

from tests.conftest import V1, connect_all
from tests.fakes.world import FakeWorld


async def test_daily_note_get_or_create_and_append(api: AsyncClient, world: FakeWorld) -> None:
    await connect_all(api)
    first = await api.get(f"{V1}/notes/daily/2026-11-02")
    again = await api.get(f"{V1}/notes/daily/2026-11-02")
    assert first.status_code == 200 and first.json()["id"] == again.json()["id"]
    assert first.json()["kind"] == "daily" and first.json()["note_date"] == "2026-11-02"
    assert len(world.notes["default"].notes) == 1

    appended = await api.post(f"{V1}/notes/daily/2026-11-02/append", json={"text": "met Sam"})
    assert "met Sam" in appended.json()["body"]
    assert "met Sam" in next(iter(world.notes["default"].notes.values())).body


async def test_append_links_note_to_task(api: AsyncClient, world: FakeWorld) -> None:
    ids = await connect_all(api)
    await api.post(f"{V1}/sync")
    task = (
        await api.post(f"{V1}/tasks", json={"connection_id": ids["vikunja"], "title": "T"})
    ).json()
    note = (
        await api.post(
            f"{V1}/notes/daily/2026-11-02/append", json={"text": "about T", "task_id": task["id"]}
        )
    ).json()
    assert note["kind"] == "daily"
    assert len(world.notes["default"].notes) == 1


async def test_daily_without_notes_connection_and_unreachable(
    api: AsyncClient, world: FakeWorld
) -> None:
    assert (await api.get(f"{V1}/notes/daily/2026-11-02")).status_code == 422
    await connect_all(api)
    world.notes["default"].unavailable = True
    failed = await api.get(f"{V1}/notes/daily/2026-11-02")
    assert failed.status_code == 502 and failed.json()["code"] == "backend_unavailable"


async def test_append_to_unsupported_app_is_reported(api: AsyncClient, world: FakeWorld) -> None:
    from tefteri.domain.enums import Capability

    await connect_all(api)
    await api.get(f"{V1}/notes/daily/2026-11-02")
    world.notes["default"].supported.discard(Capability.NOTE_APPEND)
    r = await api.post(f"{V1}/notes/daily/2026-11-02/append", json={"text": "x"})
    assert r.status_code == 409 and r.json()["code"] == "not_supported"


async def test_day_view_combines_entries_tasks_and_note(api: AsyncClient, world: FakeWorld) -> None:
    from datetime import UTC, datetime

    from tefteri.domain.entities import EntryDraft

    ids = await connect_all(api)
    await api.post(f"{V1}/sync")
    nine = datetime(2026, 11, 2, 9, tzinfo=UTC)
    await world.calendars["default"].create_entry(
        EntryDraft("cal1", "Standup", nine, nine.replace(minute=15))
    )
    other_day = datetime(2026, 11, 3, 9, tzinfo=UTC)
    await world.calendars["default"].create_entry(
        EntryDraft("cal1", "Tomorrow", other_day, other_day.replace(minute=15))
    )
    await api.post(f"{V1}/sync")
    task = (
        await api.post(f"{V1}/tasks", json={"connection_id": ids["vikunja"], "title": "Plan"})
    ).json()
    await api.put(f"{V1}/tasks/{task['id']}/schedule", json={"start": "2026-11-02T10:00:00+00:00"})
    await api.get(f"{V1}/notes/daily/2026-11-02")

    view = (await api.get(f"{V1}/views/day/2026-11-02")).json()
    assert [e["title"] for e in view["entries"]] == ["Standup"]
    assert [t["title"] for t in view["tasks"]] == ["Plan"]
    assert view["note"]["kind"] == "daily"
    empty = (await api.get(f"{V1}/views/day/2026-11-05")).json()
    assert empty["entries"] == [] and empty["tasks"] == [] and empty["note"] is None
