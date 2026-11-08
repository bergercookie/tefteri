"""The planner's task filters, counts and search (FR-018, FR-019)."""

from dataclasses import replace
from datetime import UTC, datetime

import pytest
from httpx import AsyncClient

from tefteri.domain.entities import TaskDraft
from tests.conftest import V1, connect_all
from tests.fakes.world import FakeWorld

# Wednesday 4 November 2026, 12:00 in Athens (UTC+2). The week is Monday 2 to Sunday 8 November.
NOW = datetime(2026, 11, 4, 10, tzinfo=UTC)
ATHENS = "Europe/Athens"


def utc(day: int, hour: int, minute: int = 0, month: int = 11) -> datetime:
    return datetime(2026, month, day, hour, minute, tzinfo=UTC)


async def _seed(api: AsyncClient, world: FakeWorld) -> None:
    backend = world.tasks["default"]

    async def add(
        title: str, due: datetime | None = None, *, all_day: bool = False, done: bool = False
    ) -> None:
        task = await backend.create_task(TaskDraft("p1", title, due_at=due))
        backend.tasks[task.remote_id] = replace(task, all_day=all_day, done=done)

    await add("today later", utc(4, 15))  # 17:00 local
    await add("today earlier", utc(4, 7))  # 09:00 local, already past
    await add("today all-day", utc(3, 22), all_day=True)  # local midnight of 4 Nov
    await add("tomorrow", utc(5, 9))
    await add("just after midnight", utc(4, 22, 30))  # 00:30 on 5 Nov local, still 4 Nov in UTC
    await add("friday", utc(6, 9))
    await add("yesterday all-day", utc(2, 22), all_day=True)  # local midnight of 3 Nov
    await add("last week", utc(30, 9, month=10))
    await add("next week", utc(10, 9))
    await add("no date")
    await add("done today", utc(4, 8), done=True)
    ids = await connect_all(api)
    assert ids
    admin = (await api.get(f"{V1}/auth/me")).json()
    patched = await api.patch(f"{V1}/users/{admin['id']}", json={"timezone": ATHENS})
    assert patched.status_code == 200
    api.app.state.clock = lambda: NOW  # type: ignore[attr-defined]
    assert all(r["outcome"] == "ok" for r in (await api.post(f"{V1}/sync")).json())


async def _titles(api: AsyncClient, **params: str) -> set[str]:
    r = await api.get(f"{V1}/tasks", params=params)
    assert r.status_code == 200
    return {t["title"] for t in r.json()}


@pytest.mark.parametrize(
    ("due", "expected"),
    [
        ("today", {"today later", "today earlier", "today all-day"}),
        ("tomorrow", {"tomorrow", "just after midnight"}),
        (
            "week",
            {
                "today later",
                "today earlier",
                "today all-day",
                "tomorrow",
                "just after midnight",
                "friday",
                "yesterday all-day",
            },
        ),
        ("none", {"no date"}),
        ("overdue", {"today earlier", "yesterday all-day", "last week"}),
    ],
)
async def test_each_filter_lists_the_matching_open_tasks(
    api: AsyncClient, world: FakeWorld, due: str, expected: set[str]
) -> None:
    await _seed(api, world)
    assert await _titles(api, due=due) == expected


async def test_all_lists_every_open_task_and_never_done_ones(
    api: AsyncClient, world: FakeWorld
) -> None:
    await _seed(api, world)
    everything = await _titles(api, due="all")
    assert len(everything) == 10 and "done today" not in everything
    assert "done today" in await _titles(api, status="done")


async def test_all_day_task_due_today_is_not_overdue(api: AsyncClient, world: FakeWorld) -> None:
    await _seed(api, world)
    assert "today all-day" not in await _titles(api, due="overdue")


async def test_counts_match_the_lists(api: AsyncClient, world: FakeWorld) -> None:
    await _seed(api, world)
    counts = (await api.get(f"{V1}/tasks/counts")).json()
    assert set(counts) == {"today", "tomorrow", "week", "all", "none", "overdue"}
    for name, value in counts.items():
        assert value == len(await _titles(api, due=name)), name
    assert counts == {"today": 3, "tomorrow": 2, "week": 7, "all": 10, "none": 1, "overdue": 3}


async def test_search_matches_titles_case_insensitively_over_all_open_tasks(
    api: AsyncClient, world: FakeWorld
) -> None:
    await _seed(api, world)
    assert await _titles(api, q="TODAY") == {"today later", "today earlier", "today all-day"}
    # ``due`` is ignored while a search is active (FR-019): "next week" is not due today
    assert await _titles(api, q="next", due="today") == {"next week"}
    assert await _titles(api, q="  Friday ") == {"friday"}
    assert await _titles(api, q="done") == set()  # done tasks are not open
    assert await _titles(api, q="zzz") == set()


async def test_empty_search_falls_back_to_the_filter(api: AsyncClient, world: FakeWorld) -> None:
    await _seed(api, world)
    assert await _titles(api, q="   ", due="none") == {"no date"}


async def test_a_dropped_task_moves_between_filters(api: AsyncClient, world: FakeWorld) -> None:
    await _seed(api, world)
    task = next(t for t in (await api.get(f"{V1}/tasks", params={"due": "none"})).json())
    drop = await api.put(f"{V1}/tasks/{task['id']}/schedule", json={"date": "2026-11-04"})
    assert drop.status_code == 200
    assert "no date" not in await _titles(api, due="none")
    assert "no date" in await _titles(api, due="today")
    assert (await api.get(f"{V1}/tasks/counts")).json()["none"] == 0
