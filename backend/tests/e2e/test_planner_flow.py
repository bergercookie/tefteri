"""The planner flow end to end (spec 002 quickstart): filters, drops, moves, app-set dates."""

from dataclasses import replace
from datetime import UTC, datetime

from httpx import AsyncClient

from tefteri.domain.entities import TaskDraft
from tests.conftest import V1, connect_all
from tests.fakes.world import FakeWorld

NOW = datetime(2026, 11, 4, 10, tzinfo=UTC)  # Wednesday, 12:00 in Athens


async def test_planner_flow(api: AsyncClient, world: FakeWorld) -> None:
    backend = world.tasks["default"]
    for title in ("Write report", "Plan trip", "Book tickets"):
        await backend.create_task(TaskDraft("p1", title))
    dated = await backend.create_task(
        TaskDraft("p1", "Call the bank", due_at=datetime(2026, 11, 4, 13, tzinfo=UTC))
    )
    await connect_all(api)
    admin = (await api.get(f"{V1}/auth/me")).json()
    await api.patch(f"{V1}/users/{admin['id']}", json={"timezone": "Europe/Athens"})
    api.app.state.clock = lambda: NOW  # type: ignore[attr-defined]
    assert all(r["outcome"] == "ok" for r in (await api.post(f"{V1}/sync")).json())

    # 1. filters and counts
    counts = (await api.get(f"{V1}/tasks/counts")).json()
    assert counts["today"] == 1 and counts["none"] == 3 and counts["all"] == 4
    none = (await api.get(f"{V1}/tasks", params={"due": "none"})).json()
    assert {t["title"] for t in none} == {"Write report", "Plan trip", "Book tickets"}
    found = (await api.get(f"{V1}/tasks", params={"q": "trip"})).json()
    assert [t["title"] for t in found] == ["Plan trip"]
    task = found[0]

    # 2. drop on Wednesday 14:00 (Athens = 12:00 UTC): block 14:00-15:00, due 15:00 local
    drop = await api.put(
        f"{V1}/tasks/{task['id']}/schedule", json={"start": "2026-11-04T12:00:00+00:00"}
    )
    assert drop.status_code == 200
    remote = next(t for t in backend.tasks.values() if t.title == "Plan trip")
    assert remote.due_at == datetime(2026, 11, 4, 13, tzinfo=UTC) and not remote.all_day
    items = {i["title"]: i for i in (await api.get(f"{V1}/calendar")).json()}
    assert items["Plan trip"]["start"].startswith("2026-11-04T12:00:00")
    assert items["Plan trip"]["end"].startswith("2026-11-04T13:00:00")
    assert "Plan trip" not in {
        t["title"] for t in (await api.get(f"{V1}/tasks", params={"due": "none"})).json()
    }

    # 3. move it to Thursday
    await api.put(f"{V1}/tasks/{task['id']}/schedule", json={"start": "2026-11-05T08:15:00+00:00"})
    remote = next(t for t in backend.tasks.values() if t.title == "Plan trip")
    assert remote.due_at == datetime(2026, 11, 5, 9, 15, tzinfo=UTC)

    # 4. drag it back to the list
    await api.delete(f"{V1}/tasks/{task['id']}/schedule")
    assert next(t for t in backend.tasks.values() if t.title == "Plan trip").due_at is None

    # 5. date-only drop: all-day by default, random time with the setting
    await api.put(f"{V1}/tasks/{task['id']}/schedule", json={"date": "2026-11-06"})
    remote = next(t for t in backend.tasks.values() if t.title == "Plan trip")
    assert remote.all_day and remote.due_at == datetime(2026, 11, 5, 22, tzinfo=UTC)
    await api.patch(f"{V1}/me/settings", json={"random_time_on_date_drop": True})
    await api.put(f"{V1}/tasks/{task['id']}/schedule", json={"date": "2026-11-06"})
    remote = next(t for t in backend.tasks.values() if t.title == "Plan trip")
    assert not remote.all_day

    # 6. a date set in the app shows after sync; a date without time is all-day
    backend.tasks[dated.remote_id] = replace(
        backend.tasks[dated.remote_id],
        due_at=datetime(2026, 11, 5, 22, tzinfo=UTC),
        all_day=True,
        version="v-app",
    )
    await api.post(f"{V1}/sync")
    items = {i["title"]: i for i in (await api.get(f"{V1}/calendar")).json()}
    assert items["Call the bank"]["all_day"] is True

    # 7. the app is down: a clear error and no change
    backend.unavailable = True
    down = await api.put(
        f"{V1}/tasks/{task['id']}/schedule", json={"start": "2026-11-04T07:00:00+00:00"}
    )
    backend.unavailable = False
    assert down.status_code == 502 and "Nothing was changed" in down.json()["detail"]
    assert next(t for t in backend.tasks.values() if t.title == "Plan trip").due_at == remote.due_at
