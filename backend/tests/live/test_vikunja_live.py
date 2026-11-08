"""Tefteri against a real Vikunja: planning a task, moving it and syncing.

Not part of `just test`. Run with `just backend::live-vikunja` (see ``conftest.py``).
Each test names the behavior that must hold on every Vikunja version; a failure here is a
difference between Vikunja and the fake that the automated tests use.
"""

import uuid
from collections.abc import Callable
from datetime import UTC, datetime
from typing import Any

import pytest
from httpx import AsyncClient

from tefteri.adapters.vikunja import VikunjaTaskBackend
from tefteri.domain.entities import Container, TaskDraft
from tefteri.domain.errors import RemoteConflict
from tests.conftest import V1
from tests.live.conftest import RealVikunja

pytestmark = pytest.mark.live

Adapter = Callable[[str], VikunjaTaskBackend]
ATHENS = "Europe/Athens"


def _title(prefix: str) -> str:
    return f"{prefix} {uuid.uuid4().hex[:8]}"


def _due(task: dict[str, Any]) -> datetime | None:
    """The due date of a raw Vikunja task as an aware datetime, or None when it has none."""
    value = task["due_date"]
    if value.startswith("0001-01-01"):
        return None
    return datetime.fromisoformat(value.replace("Z", "+00:00")).astimezone(UTC)


def _at_raw(value: str) -> datetime:
    """A time as Vikunja writes it (``Z`` or the offset of its server) as an aware datetime."""
    return datetime.fromisoformat(value.replace("Z", "+00:00")).astimezone(UTC)


def _at(day: int, hour: int, minute: int = 0, month: int = 11) -> datetime:
    return datetime(2026, month, day, hour, minute, tzinfo=UTC)


async def _sync(api: AsyncClient) -> None:
    results = (await api.post(f"{V1}/sync")).json()
    assert all(r["outcome"] == "ok" for r in results), results


async def _find(api: AsyncClient, title: str) -> dict[str, Any]:
    tasks = (await api.get(f"{V1}/tasks", params={"due": "all"})).json()
    return next(t for t in tasks if t["title"] == title)


def _cached_due(task: dict[str, Any]) -> datetime | None:
    value = task["due_at"]
    if value is None:
        return None
    return (
        datetime.fromisoformat(value).astimezone(UTC)
        if "+" in value or value.endswith("Z")
        else (datetime.fromisoformat(value).replace(tzinfo=UTC))
    )


# --- the adapter alone ------------------------------------------------------------------


async def test_a_task_that_tefteri_created_can_be_moved_twice_in_a_row(
    adapter: Adapter, real: RealVikunja
) -> None:
    """Vikunja answers a create with a nanosecond ``updated``; a read has whole seconds."""
    backend = adapter("UTC")
    created = await backend.create_task(
        TaskDraft(await real.inbox(), _title("created"), due_at=_at(4, 9))
    )
    first = await backend.set_planned_time(created.remote_id, _at(5, 14), False, created.version)
    second = await backend.set_planned_time(created.remote_id, _at(6, 15), False, first.version)
    assert second.due_at == _at(6, 15)
    assert _due(await real.get(created.remote_id)) == _at(6, 15)


async def test_the_version_of_a_task_is_the_same_in_every_answer(
    adapter: Adapter, real: RealVikunja
) -> None:
    backend = adapter("UTC")
    container = Container(await real.inbox(), "")
    created = await backend.create_task(TaskDraft(container.remote_id, _title("version")))
    read = await backend.get_task(created.remote_id)
    listed = next(
        t
        for t in (await backend.list_tasks(container, None)).items
        if t.remote_id == created.remote_id
    )
    assert created.version == read.version == listed.version
    written = await backend.set_planned_time(created.remote_id, _at(5, 10), False, read.version)
    assert written.version == (await backend.get_task(created.remote_id)).version


async def test_timed_all_day_and_cleared_due_dates_round_trip(
    adapter: Adapter, real: RealVikunja
) -> None:
    backend = adapter(ATHENS)  # UTC+2 in November
    created = await backend.create_task(TaskDraft(await real.inbox(), _title("round trip")))
    version = created.version

    day = await backend.set_planned_time(created.remote_id, _at(4, 12), True, version)
    assert day.all_day and day.due_at == _at(3, 22)  # 00:00 on 4 November, Athens
    assert _due(await real.get(created.remote_id)) == _at(3, 22)

    timed = await backend.set_planned_time(created.remote_id, _at(4, 12, 30), False, day.version)
    assert not timed.all_day and timed.due_at == _at(4, 12, 30)

    cleared = await backend.set_planned_time(created.remote_id, None, False, timed.version)
    assert cleared.due_at is None and _due(await real.get(created.remote_id)) is None


async def test_start_and_end_dates_of_a_task_are_left_alone(
    adapter: Adapter, real: RealVikunja
) -> None:
    raw = await real.create(
        _title("start end"),
        due_date="2026-11-04T09:00:00Z",
        start_date="2026-11-03T09:00:00Z",
        end_date="2026-11-04T10:00:00Z",
    )
    backend = adapter("UTC")
    current = await backend.get_task(str(raw["id"]))
    await backend.set_planned_time(str(raw["id"]), _at(6, 11), False, current.version)
    after = await real.get(raw["id"])
    assert _due(after) == _at(6, 11)
    assert _at_raw(after["start_date"]) == _at(3, 9)
    assert _at_raw(after["end_date"]) == _at(4, 10)


async def test_a_change_made_in_vikunja_is_a_conflict(adapter: Adapter, real: RealVikunja) -> None:
    raw = await real.create(_title("conflict"), due_date="2026-11-04T09:00:00Z")
    backend = adapter("UTC")
    seen = await backend.get_task(str(raw["id"]))
    await real.update(raw["id"], title=_title("renamed in Vikunja"))
    with pytest.raises(RemoteConflict):
        await backend.set_planned_time(str(raw["id"]), _at(6, 11), False, seen.version)


# --- the whole app: sync, move, sync ----------------------------------------------------

VARIANTS: dict[str, dict[str, Any]] = {
    "plain": {},
    "description": {"description": "<p>Hello</p>"},
    "relative reminder": {"reminders": [{"relative_period": -3600, "relative_to": "due_date"}]},
    "absolute reminder": {"reminders": [{"reminder": "2026-11-04T08:00:00Z"}]},
    "repeating daily": {"repeat_after": 86400},
    "repeating monthly": {"repeat_mode": 1},
    "start and end dates": {
        "start_date": "2026-11-03T09:00:00Z",
        "end_date": "2026-11-04T10:00:00Z",
    },
    "priority and colour": {"priority": 4, "percent_done": 0.5, "hex_color": "ff0000"},
}


@pytest.mark.parametrize("variant", list(VARIANTS))
async def test_move_then_sync_keeps_the_new_due_date(
    tefteri: AsyncClient, real: RealVikunja, variant: str
) -> None:
    """A task with a due date, moved twice in the calendar, then a sync: the date stays."""
    title = _title(variant)
    raw = await real.create(title, due_date="2026-11-04T09:00:00Z", **VARIANTS[variant])
    await _sync(tefteri)
    mine = await _find(tefteri, title)
    assert _cached_due(mine) == _at(4, 9)

    for start, expected_due in (
        (_at(5, 13), _at(5, 14)),
        (_at(6, 10), _at(6, 11)),
    ):
        moved = await tefteri.put(
            f"{V1}/tasks/{mine['id']}/schedule", json={"start": start.isoformat()}
        )
        assert moved.status_code == 200, moved.text
        assert _due(await real.get(raw["id"])) == expected_due

    await _sync(tefteri)
    after = (await tefteri.get(f"{V1}/tasks/{mine['id']}")).json()
    assert _cached_due(after) == _at(6, 11)
    assert _due(await real.get(raw["id"])) == _at(6, 11)


async def test_a_task_created_in_tefteri_moves_and_syncs(
    tefteri: AsyncClient, real: RealVikunja
) -> None:
    title = _title("from tefteri")
    connection = (await tefteri.get(f"{V1}/connections")).json()[0]["id"]
    await _sync(tefteri)
    created = await tefteri.post(f"{V1}/tasks", json={"connection_id": connection, "title": title})
    assert created.status_code == 201, created.text
    task_id = created.json()["id"]

    moved = await tefteri.put(
        f"{V1}/tasks/{task_id}/schedule", json={"start": _at(5, 13).isoformat()}
    )
    assert moved.status_code == 200, moved.text  # used to conflict: nanosecond stamp

    await _sync(tefteri)
    after = (await tefteri.get(f"{V1}/tasks/{task_id}")).json()
    assert _cached_due(after) == _at(5, 14)


async def test_a_date_only_drop_survives_a_sync(tefteri: AsyncClient, real: RealVikunja) -> None:
    admin = (await tefteri.get(f"{V1}/auth/me")).json()
    await tefteri.patch(f"{V1}/users/{admin['id']}", json={"timezone": ATHENS})
    title = _title("date only")
    raw = await real.create(title)
    await _sync(tefteri)
    mine = await _find(tefteri, title)

    dropped = await tefteri.put(f"{V1}/tasks/{mine['id']}/schedule", json={"date": "2026-11-06"})
    assert dropped.status_code == 200, dropped.text
    assert _due(await real.get(raw["id"])) == _at(5, 22)  # 00:00 on 6 November, Athens

    await _sync(tefteri)
    items = (await tefteri.get(f"{V1}/calendar")).json()
    mine_on_calendar = next(i for i in items if i["title"] == title)
    assert mine_on_calendar["all_day"] is True


async def test_a_change_in_vikunja_wins_at_the_next_sync(
    tefteri: AsyncClient, real: RealVikunja
) -> None:
    title = _title("changed in Vikunja")
    raw = await real.create(title, due_date="2026-11-04T09:00:00Z")
    await _sync(tefteri)
    mine = await _find(tefteri, title)
    await tefteri.put(f"{V1}/tasks/{mine['id']}/schedule", json={"start": _at(5, 13).isoformat()})

    await real.update(raw["id"], due_date="2026-11-09T08:00:00Z")  # the user, in Vikunja
    await _sync(tefteri)
    after = (await tefteri.get(f"{V1}/tasks/{mine['id']}")).json()
    assert _cached_due(after) == _at(9, 8, month=11)


async def test_a_move_after_a_change_in_vikunja_is_a_conflict_and_changes_nothing(
    tefteri: AsyncClient, real: RealVikunja
) -> None:
    title = _title("conflict")
    raw = await real.create(title, due_date="2026-11-04T09:00:00Z")
    await _sync(tefteri)
    mine = await _find(tefteri, title)

    await real.update(raw["id"], title=f"{title} (renamed)")  # not synced yet
    moved = await tefteri.put(
        f"{V1}/tasks/{mine['id']}/schedule", json={"start": _at(6, 10).isoformat()}
    )
    assert moved.status_code == 409 and moved.json()["code"] == "remote_conflict"
    assert _due(await real.get(raw["id"])) == _at(4, 9)  # Vikunja was not changed
    assert _cached_due((await tefteri.get(f"{V1}/tasks/{mine['id']}")).json()) == _at(4, 9)


# --- weekly planning --------------------------------------------------------------------


async def test_weekly_planning_follows_a_new_subproject_in_vikunja(
    tefteri: AsyncClient, real: RealVikunja
) -> None:
    """A subproject made by tefteri is a real subproject, and tasks added in Vikunja show up."""
    await _sync(tefteri)
    week = "2030-03-04"
    parent = next(
        c
        for c in (await tefteri.get(f"{V1}/weekly/{week}/candidates")).json()
        if c["name"] == "Inbox"
    )
    name = _title("Launch")
    made = await tefteri.post(
        f"{V1}/weekly/{week}/subprojects", json={"parent_id": parent["container_id"], "name": name}
    )
    assert made.status_code == 201, made.text
    project = made.json()["plan"]["projects"][0]
    assert project["name"] == name and project["open_tasks"] == 0
    remote = next(
        p
        for p in (await real.client.get(f"{real.base}/projects", headers=real.headers)).json()
        if p["title"] == name
    )
    assert str(remote["parent_project_id"]) == await real.inbox()
    assert project["url"].endswith(f"/projects/{remote['id']}")
    for n in (1, 2, 3):
        r = await real.client.put(
            f"{real.base}/projects/{remote['id']}/tasks",
            headers=real.headers,
            json={"title": f"{name} task {n}"},
        )
        assert r.status_code == 201, r.text
    refreshed = (await tefteri.post(f"{V1}/weekly/{week}/refresh")).json()
    assert refreshed["plan"]["projects"][0]["open_tasks"] == 3
    spread = (await tefteri.post(f"{V1}/weekly/{week}/spread")).json()
    days = [t["planned_day"] for t in spread["plan"]["projects"][0]["tasks"]]
    assert None not in days and len(set(days)) == 3
    again = (await tefteri.post(f"{V1}/weekly/{week}/refresh")).json()
    assert [t["planned_day"] for t in again["plan"]["projects"][0]["tasks"]] == days
    committed = (await tefteri.post(f"{V1}/weekly/{week}/commit")).json()
    assert committed["plan"]["status"] == "committed"


async def test_archiving_a_project_from_tefteri_archives_it_in_vikunja(
    tefteri: AsyncClient, real: RealVikunja
) -> None:
    """The project and its subproject disappear from Vikunja's list, and tefteri forgets them."""
    await _sync(tefteri)
    week = "2030-03-04"
    parent = next(
        c
        for c in (await tefteri.get(f"{V1}/weekly/{week}/candidates")).json()
        if c["name"] == "Inbox"
    )
    name = _title("Archive me")
    made = await tefteri.post(
        f"{V1}/weekly/{week}/subprojects", json={"parent_id": parent["container_id"], "name": name}
    )
    assert made.status_code == 201, made.text
    sub = made.json()["plan"]["projects"][0]["container_id"]
    connection = parent["connection_id"]
    archived = await tefteri.post(f"{V1}/connections/{connection}/containers/{sub}/archive")
    assert archived.status_code == 204, archived.text
    titles = [
        p["title"]
        for p in (await real.client.get(f"{real.base}/projects", headers=real.headers)).json()
    ]
    assert name not in titles
    listed = await tefteri.get(f"{V1}/connections/{connection}/containers")
    assert name not in {c["name"] for c in listed.json()}
    await _sync(tefteri)
    listed = await tefteri.get(f"{V1}/connections/{connection}/containers")
    assert name not in {c["name"] for c in listed.json()}
