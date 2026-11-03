"""The daily flow end to end against fake backends: view day, add task, schedule, complete, note."""

from httpx import AsyncClient

from tests.conftest import V1, connect_all
from tests.fakes.world import FakeWorld


async def test_daily_flow(api: AsyncClient, world: FakeWorld) -> None:
    await world.seed()
    ids = await connect_all(api)
    assert all(r["outcome"] == "ok" for r in (await api.post(f"{V1}/sync")).json())

    view = (await api.get(f"{V1}/views/day/2026-11-02")).json()
    assert [e["title"] for e in view["entries"]] == ["Standup"]

    task = (
        await api.post(
            f"{V1}/tasks", json={"connection_id": ids["vikunja"], "title": "Prepare demo"}
        )
    ).json()
    scheduled = await api.put(
        f"{V1}/tasks/{task['id']}/schedule",
        json={"start": "2026-11-02T09:05:00+00:00"},
    )
    assert [e["title"] for e in scheduled.json()["overlaps"]] == ["Standup"]
    remote = next(t for t in world.tasks["default"].tasks.values() if t.title == "Prepare demo")
    assert remote.due_at is not None  # block 09:00-10:00, due 10:00
    assert [e.title for e in world.calendars["default"].entries.values()] == ["Standup"]

    await api.post(f"{V1}/tasks/{task['id']}/complete")
    await api.post(
        f"{V1}/notes/daily/2026-11-02/append", json={"text": "demo done", "task_id": task["id"]}
    )

    # after a sync the cache still matches the apps
    assert all(r["outcome"] == "ok" for r in (await api.post(f"{V1}/sync")).json())
    day = (await api.get(f"{V1}/views/day/2026-11-02")).json()
    assert [t["status"] for t in day["tasks"]] == ["done"]
    assert "demo done" in day["note"]["body"]
    calendar = (await api.get(f"{V1}/calendar")).json()
    assert {i["type"] for i in calendar} == {"entry", "task"}
