"""Plan reviews, retrospectives written to the note app, and plan history."""

from collections.abc import Awaitable, Callable

from httpx import AsyncClient

from tests.conftest import V1, connect_all
from tests.fakes.world import FakeWorld


async def _plan_with_goals(api: AsyncClient) -> dict[str, str]:
    """An October 2026 plan with one done goal and one goal with an open and a done task."""
    ids = await connect_all(api)
    await api.post(f"{V1}/sync")
    plan = (
        await api.post(
            f"{V1}/plans",
            json={"period_type": "month", "period_start": "2026-10-01", "title": "October"},
        )
    ).json()
    read = (
        await api.post(
            f"{V1}/goals",
            json={"period_type": "month", "period_start": "2026-10-01", "title": "Read"},
        )
    ).json()
    await api.patch(f"{V1}/goals/{read['id']}", json={"status": "done"})
    run = (
        await api.post(
            f"{V1}/goals",
            json={"period_type": "month", "period_start": "2026-10-01", "title": "Run"},
        )
    ).json()
    tasks = (
        await api.post(
            f"{V1}/goals/{run['id']}/breakdown",
            json={
                "tasks": [
                    {"connection_id": ids["vikunja"], "title": "Buy shoes"},
                    {"connection_id": ids["vikunja"], "title": "Run 25 km"},
                ]
            },
        )
    ).json()["tasks"]
    await api.post(f"{V1}/tasks/{tasks[0]['id']}/complete")
    return {"plan": plan["id"], "run": run["id"], "open_task": tasks[1]["id"]}


async def test_review_shows_planned_completed_and_carried_over(api: AsyncClient) -> None:
    ids = await _plan_with_goals(api)
    r = await api.get(f"{V1}/plans/{ids['plan']}/review")
    assert r.status_code == 200, r.text
    review = r.json()
    assert review["period_ended"] is True and review["period_end"] == "2026-11-01"
    # Single tasks are not part of a review: only the goals count.
    assert (review["planned_count"], review["completed_count"]) == (2, 1)
    assert {i["type"] for i in review["items"]} == {"goal"}
    assert set(review["carried_over"]) == {ids["run"]}
    assert review["retrospective"] is None


async def test_review_is_a_snapshot_until_refreshed(api: AsyncClient) -> None:
    ids = await _plan_with_goals(api)
    first = (await api.get(f"{V1}/plans/{ids['plan']}/review")).json()
    await api.post(f"{V1}/tasks/{ids['open_task']}/complete")
    again = (await api.get(f"{V1}/plans/{ids['plan']}/review")).json()
    assert again["completed_count"] == first["completed_count"] == 1
    fresh = (await api.get(f"{V1}/plans/{ids['plan']}/review", params={"refresh": True})).json()
    assert fresh["completed_count"] == 2 and fresh["carried_over"] == []


async def test_retrospective_is_written_to_the_note_app(api: AsyncClient, world: FakeWorld) -> None:
    ids = await _plan_with_goals(api)
    r = await api.put(
        f"{V1}/plans/{ids['plan']}/review/retrospective", json={"body": "Good month."}
    )
    assert r.status_code == 200, r.text
    retro = r.json()["retrospective"]
    assert retro["kind"] == "retrospective" and retro["body"] == "Good month."
    remote = [
        n for n in world.notes["default"].notes.values() if n.title == "Retrospective: October"
    ]
    assert len(remote) == 1 and remote[0].body == "Good month."

    r = await api.put(
        f"{V1}/plans/{ids['plan']}/review/retrospective", json={"body": "Good month, mostly."}
    )
    assert r.json()["retrospective"]["id"] == retro["id"]
    assert remote[0].remote_id in world.notes["default"].notes
    assert world.notes["default"].notes[remote[0].remote_id].body == "Good month, mostly."
    fetched = (await api.get(f"{V1}/plans/{ids['plan']}/review")).json()
    assert fetched["retrospective"]["body"] == "Good month, mostly."


async def test_retrospective_is_not_saved_when_the_note_app_is_down(
    api: AsyncClient, world: FakeWorld
) -> None:
    ids = await _plan_with_goals(api)
    world.notes["default"].unavailable = True
    r = await api.put(f"{V1}/plans/{ids['plan']}/review/retrospective", json={"body": "x"})
    assert r.status_code == 502 and r.json()["code"] == "backend_unavailable"
    world.notes["default"].unavailable = False
    assert (await api.get(f"{V1}/plans/{ids['plan']}/review")).json()["retrospective"] is None


async def test_plan_history_lists_plans_with_their_reviews(api: AsyncClient) -> None:
    ids = await _plan_with_goals(api)
    await api.post(
        f"{V1}/plans",
        json={"period_type": "year", "period_start": "2027-01-01", "title": "Next year"},
    )
    await api.put(f"{V1}/plans/{ids['plan']}/review/retrospective", json={"body": "ok"})
    history = (await api.get(f"{V1}/reviews/history")).json()
    assert [h["title"] for h in history] == ["Next year", "October"]
    assert history[0]["review"] is None and history[0]["period_ended"] is False
    assert history[1]["review"]["planned_count"] == 2
    assert history[1]["review"]["has_retrospective"] is True


async def test_reviews_are_per_user(
    api: AsyncClient, make_user: Callable[..., Awaitable[AsyncClient]]
) -> None:
    ids = await _plan_with_goals(api)
    other = await make_user("bob")
    assert (await other.get(f"{V1}/plans/{ids['plan']}/review")).status_code == 404
    assert (
        await other.put(f"{V1}/plans/{ids['plan']}/review/retrospective", json={"body": "x"})
    ).status_code == 404
    assert (await other.get(f"{V1}/reviews/history")).json() == []
