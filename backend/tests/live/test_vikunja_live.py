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


async def test_a_project_can_be_renamed_and_keeps_its_id_and_parent(adapter: Adapter) -> None:
    """Vikunja resets the fields that a write leaves out: the rename sends the whole project."""
    backend = adapter("UTC")
    parent = await backend.create_container(_title("Parent"), None)
    child = await backend.create_container(_title("Child"), parent)
    new_name = _title("Renamed")
    renamed = await backend.rename_container(child, new_name)
    assert (renamed.remote_id, renamed.name, renamed.parent_id) == (
        child.remote_id,
        new_name,
        parent.remote_id,
    )
    listed = {c.remote_id: c for c in await backend.list_containers()}
    assert listed[child.remote_id].name == new_name
    assert listed[child.remote_id].parent_id == parent.remote_id


async def test_an_archived_project_can_be_restored(adapter: Adapter) -> None:
    """The project leaves Vikunja's list when archived and comes back, in place, when restored."""
    backend = adapter("UTC")
    parent = await backend.create_container(_title("Parent"), None)
    child = await backend.create_container(_title("Child"), parent)
    await backend.archive_container(child)
    assert child.remote_id not in {c.remote_id for c in await backend.list_containers()}
    await backend.restore_container(child)
    back = {c.remote_id: c for c in await backend.list_containers()}
    assert back[child.remote_id].parent_id == parent.remote_id
    # Archiving the parent takes the subproject along; restoring both brings both back.
    await backend.archive_container(parent)
    await backend.restore_container(parent)
    await backend.restore_container(child)
    listed_ids = {c.remote_id for c in await backend.list_containers()}
    assert {parent.remote_id, child.remote_id} <= listed_ids


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


async def test_a_task_moves_to_another_project_and_back_and_keeps_what_it_has(
    adapter: Adapter, real: RealVikunja
) -> None:
    """Vikunja moves a task with a normal update that has another ``project_id`` (spec 004)."""
    backend = adapter("UTC")
    one = await backend.create_container(_title("Move from"), None)
    two = await backend.create_container(_title("Move to"), None)
    created = await backend.create_task(
        TaskDraft(one.remote_id, _title("Mover"), due_at=_at(5, 14))
    )
    moved = await backend.move_task(created.remote_id, two, created.version)
    assert (moved.remote_id, moved.container_id, moved.title) == (
        created.remote_id,
        two.remote_id,
        created.title,
    )
    assert moved.due_at == _at(5, 14)  # the day stays
    assert [t.remote_id for t in (await backend.list_tasks(two, None)).items] == [created.remote_id]
    assert (await backend.list_tasks(one, None)).items == []
    raw = await real.get(created.remote_id)
    assert str(raw["project_id"]) == two.remote_id
    # The version that the move answered is the one the next write needs.
    back = await backend.move_task(created.remote_id, one, moved.version)
    assert back.container_id == one.remote_id
    with pytest.raises(RemoteConflict):
        await backend.move_task(created.remote_id, two, moved.version)  # it moved since


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


async def _label_inbox_as_theme(tefteri: AsyncClient) -> dict[str, Any]:
    """Label Inbox as a theme and return its entry of the weekly picker's parent list."""
    await _sync(tefteri)
    projects = await _projects_by_name(tefteri)
    r = await tefteri.put(
        f"{V1}/projects/labels",
        json={"changes": [{"id": projects["Inbox"]["id"], "label": "theme"}]},
    )
    assert r.status_code == 200, r.text
    themes = (await tefteri.get(f"{V1}/weekly/2030-03-04/themes")).json()["themes"]
    theme: dict[str, Any] = next(t for t in themes if t["name"] == "Inbox")
    return theme


async def test_weekly_planning_follows_a_new_milestone_in_vikunja(
    tefteri: AsyncClient, real: RealVikunja
) -> None:
    """A milestone made by tefteri is a real subproject, and tasks added in Vikunja show up."""
    parent = await _label_inbox_as_theme(tefteri)
    week = "2030-03-04"
    name = _title("Launch")
    made = await tefteri.post(
        f"{V1}/weekly/{week}/milestones",
        json={"parent_id": parent["container_id"], "name": name, "done_state": "Launched"},
    )
    assert made.status_code == 201, made.text
    project = made.json()["plan"]["projects"][0]
    assert project["name"] == name and project["open_tasks"] == 0
    assert (project["done_state"], project["milestone_state"]) == ("Launched", "active")
    assert project["theme"]["name"] == "Inbox"
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
    added = await tefteri.post(
        f"{V1}/weekly/{week}/projects/{project['id']}/tasks", json={"title": f"{name} new"}
    )
    assert added.status_code == 201, added.text
    assert f"{name} new" in {
        t["title"]
        for t in (
            await real.client.get(
                f"{real.base}/projects/{remote['id']}/tasks", headers=real.headers
            )
        ).json()
    }
    committed = (await tefteri.post(f"{V1}/weekly/{week}/commit")).json()
    assert committed["plan"]["status"] == "committed"
    assert len(committed["plan"]["projects"][0]["committed_tasks"]) == 3  # the new one has no day


async def test_closing_a_milestone_moves_its_tasks_in_vikunja_and_reopen_moves_them_back(
    tefteri: AsyncClient, real: RealVikunja
) -> None:
    """The move is a real update in Vikunja: tasks keep their ids and days, and come back."""
    parent = await _label_inbox_as_theme(tefteri)
    week = "2030-03-04"
    name = _title("Close me")
    made = await tefteri.post(
        f"{V1}/weekly/{week}/milestones",
        json={"parent_id": parent["container_id"], "name": name, "done_state": "Closed"},
    )
    assert made.status_code == 201, made.text
    milestone = made.json()["plan"]["projects"][0]["milestone_id"]
    remote = next(
        p
        for p in (await real.client.get(f"{real.base}/projects", headers=real.headers)).json()
        if p["title"] == name
    )
    ids = []
    for n in (1, 2, 3):
        r = await real.client.put(
            f"{real.base}/projects/{remote['id']}/tasks",
            headers=real.headers,
            json={"title": f"{name} task {n}", "due_date": "2030-03-06T00:00:00Z"},
        )
        assert r.status_code == 201, r.text
        ids.append(r.json()["id"])
    await tefteri.post(f"{V1}/weekly/{week}/refresh")
    preview = await tefteri.post(f"{V1}/milestones/{milestone}/close", json={"dry_run": True})
    assert preview.status_code == 200, preview.text
    assert preview.json()["message"] == "3 open tasks will move to Inbox."
    assert {(await real.get(i))["project_id"] for i in ids} == {remote["id"]}
    closed = await tefteri.post(f"{V1}/milestones/{milestone}/close", json={"confirm": True})
    assert closed.status_code == 200, closed.text
    assert closed.json()["moved"] == 3 and closed.json()["milestone"]["state"] == "closed"
    inbox = int(await real.inbox())
    for i in ids:
        moved = await real.get(i)
        assert moved["project_id"] == inbox
        assert moved["due_date"].startswith("2030-03-06")  # a moved task keeps its day
    await _sync(tefteri)  # the next sync agrees with the local copy
    assert (await tefteri.get(f"{V1}/milestones/{milestone}")).json()["state"] == "closed"
    reopened = await tefteri.post(f"{V1}/milestones/{milestone}/reopen")
    assert reopened.status_code == 200, reopened.text
    assert reopened.json()["moved_back"] == 3 and reopened.json()["not_moved_back"] == []
    assert {(await real.get(i))["project_id"] for i in ids} == {remote["id"]}


async def test_archiving_a_project_from_tefteri_archives_it_in_vikunja(
    tefteri: AsyncClient, real: RealVikunja
) -> None:
    """The project and its subproject disappear from Vikunja's list, and tefteri forgets them."""
    parent = await _label_inbox_as_theme(tefteri)
    week = "2030-03-04"
    name = _title("Archive me")
    made = await tefteri.post(
        f"{V1}/weekly/{week}/milestones",
        json={"parent_id": parent["container_id"], "name": name, "done_state": "Archived"},
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


async def test_a_task_created_with_labels_has_them_in_vikunja(
    tefteri: AsyncClient, real: RealVikunja
) -> None:
    """New labels are created, existing ones are reused whatever their case, and they list."""
    await _sync(tefteri)
    connection = (await tefteri.get(f"{V1}/connections")).json()[0]["id"]
    project = (await tefteri.get(f"{V1}/connections/{connection}/containers")).json()[0]["id"]
    one, two = _title("alpha"), _title("beta")

    async def create(title: str, labels: list[str]) -> dict[str, Any]:
        r = await tefteri.post(
            f"{V1}/tasks",
            json={
                "connection_id": connection,
                "container_id": project,
                "title": title,
                "labels": labels,
            },
        )
        assert r.status_code == 201, r.text
        body: dict[str, Any] = r.json()
        return body

    first = await create(_title("with labels"), [one, two])
    assert first["labels"] == [one, two]
    raw = await real.get(
        next(
            t["id"]
            for t in (await real.client.get(f"{real.base}/tasks", headers=real.headers)).json()
            if t["title"] == first["title"]
        )
    )
    assert sorted(label["title"] for label in raw["labels"]) == sorted([one, two])
    # The same label in another case is the same label.
    second = await create(_title("again"), [one.upper()])
    assert second["labels"] == [one]
    listed = (await tefteri.get(f"{V1}/connections/{connection}/labels")).json()
    assert one in listed and two in listed and listed.count(one) == 1


# --- project classification (spec 003) ---------------------------------------------------------


async def _projects_by_name(tefteri: AsyncClient) -> dict[str, dict[str, Any]]:
    r = await tefteri.get(f"{V1}/projects/classification")
    assert r.status_code == 200, r.text
    return {p["name"]: p for c in r.json()["connections"] for p in c["projects"]}


async def _titles(real: RealVikunja) -> set[str]:
    listed = await real.client.get(f"{real.base}/projects", headers=real.headers)
    return {p["title"] for p in listed.json()}


async def test_a_label_survives_a_rename_and_a_move_made_in_vikunja(
    tefteri: AsyncClient, real: RealVikunja, adapter: Adapter
) -> None:
    """Labels are keyed on the Vikunja project id, so a rename or a move never loses one."""
    backend = adapter("UTC")
    top = await backend.create_container(_title("Theme"), None)
    other = await backend.create_container(_title("Other"), None)
    inner = await backend.create_container(_title("Inner"), top)
    await _sync(tefteri)
    projects = await _projects_by_name(tefteri)
    assert projects[inner.name]["proposal"]["label"] == "milestone"  # nested
    assert projects[top.name]["proposal"]["label"] == "theme"
    saved = await tefteri.put(
        f"{V1}/projects/labels",
        json={"changes": [{"id": projects[inner.name]["id"], "label": "maintenance"}]},
    )
    assert saved.status_code == 200, saved.text
    # Another client renames the project and moves it under another project.
    project = (
        await real.client.get(f"{real.base}/projects/{inner.remote_id}", headers=real.headers)
    ).json()
    renamed = _title("Renamed")
    project |= {"title": renamed, "parent_project_id": int(other.remote_id)}
    written = await real.client.post(
        f"{real.base}/projects/{inner.remote_id}", headers=real.headers, json=project
    )
    assert written.status_code == 200, written.text
    await _sync(tefteri)
    moved = (await _projects_by_name(tefteri))[renamed]
    assert moved["id"] == projects[inner.name]["id"]
    assert (moved["label"], moved["orphaned"]) == ("maintenance", None)
    parent = next(
        p for p in (await _projects_by_name(tefteri)).values() if p["id"] == moved["parent_id"]
    )
    assert parent["name"] == other.name


async def test_a_project_deleted_in_vikunja_is_orphaned_and_keeps_its_label(
    tefteri: AsyncClient, real: RealVikunja, adapter: Adapter
) -> None:
    backend = adapter("UTC")
    doomed = await backend.create_container(_title("Doomed"), None)
    await _sync(tefteri)
    project = (await _projects_by_name(tefteri))[doomed.name]
    await tefteri.put(
        f"{V1}/projects/labels", json={"changes": [{"id": project["id"], "label": "theme"}]}
    )
    gone = await real.client.delete(
        f"{real.base}/projects/{doomed.remote_id}", headers=real.headers
    )
    assert gone.status_code == 200, gone.text
    await _sync(tefteri)
    orphan = (await _projects_by_name(tefteri))[doomed.name]
    assert orphan["orphaned"]["reason"] == "missing" and orphan["label"] == "theme"
    assert orphan["eligible"] is False
    # Every screen that reads projects still works.
    assert (await tefteri.get(f"{V1}/tasks", params={"due": "all"})).status_code == 200
    assert (await tefteri.get(f"{V1}/weekly/2030-03-04/candidates")).status_code == 200
    assert (await tefteri.get(f"{V1}/weekly/2030-03-04/themes")).status_code == 200


async def test_rename_archive_and_restore_from_tefteri_change_vikunja(
    tefteri: AsyncClient, real: RealVikunja, adapter: Adapter
) -> None:
    backend = adapter("UTC")
    top = await backend.create_container(_title("Top"), None)
    sub = await backend.create_container(_title("Sub"), top)
    await _sync(tefteri)
    projects = await _projects_by_name(tefteri)
    await tefteri.put(
        f"{V1}/projects/labels",
        json={"changes": [{"id": projects[top.name]["id"], "label": "theme"}]},
    )
    new_name = _title("Better")
    renamed = await tefteri.patch(
        f"{V1}/projects/{projects[top.name]['id']}", json={"name": new_name}
    )
    assert renamed.status_code == 200, renamed.text
    assert new_name in await _titles(real)
    assert top.name not in await _titles(real)

    archived = await tefteri.post(f"{V1}/projects/{projects[top.name]['id']}/archive")
    assert archived.status_code == 200, archived.text
    assert {new_name, sub.name}.isdisjoint(await _titles(real))
    await _sync(tefteri)  # a sync does not turn "archived" into "missing"
    after = await _projects_by_name(tefteri)
    assert after[new_name]["orphaned"]["reason"] == "archived"

    restored = await tefteri.post(f"{V1}/projects/{projects[top.name]['id']}/restore")
    assert restored.status_code == 200, restored.text
    assert {new_name, sub.name} <= await _titles(real)
    back = await _projects_by_name(tefteri)
    assert (back[new_name]["orphaned"], back[new_name]["label"]) == (None, "theme")
    assert back[sub.name]["orphaned"] is None


async def test_create_a_project_and_label_it_creates_it_in_vikunja(
    tefteri: AsyncClient, real: RealVikunja
) -> None:
    await _sync(tefteri)
    connection = (await tefteri.get(f"{V1}/connections")).json()[0]["id"]
    name = _title("Theme")
    made = await tefteri.post(
        f"{V1}/projects", json={"connection_id": connection, "name": name, "label": "theme"}
    )
    assert made.status_code == 201, made.text
    assert name in await _titles(real)
    assert made.json()["label"] == "theme"
    await _sync(tefteri)
    assert (await _projects_by_name(tefteri))[name]["label"] == "theme"
    # No label is ever written to the task app: Vikunja has no label with that name.
    labels = (await real.client.get(f"{real.base}/labels", headers=real.headers)).json() or []
    assert "theme" not in {label["title"] for label in labels}
