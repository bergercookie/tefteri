"""Integration tests of theme contributions and hints (spec 008, user story 2)."""

from datetime import UTC, date, datetime

from sqlalchemy import select

from tefteri.db.models.key_result import KeyResultTheme
from tests.integration.conftest import make_snapshot, store_snapshot
from tests.integration.monthly_review_helpers import add_key_result, setup_review

TODAY_AT = datetime(2026, 11, 13, 12, tzinfo=UTC)


def _kr(key_result_id, value: float, base: float, month: int) -> dict[str, object]:
    return {
        "key_result_id": key_result_id,
        "metric": "Stars",
        "update_source": "manual",
        "start_value": 0,
        "base_value": base,
        "latest_value": value,
        "latest_at": f"2025-{month:02d}-08T12:00:00Z",
        "target": 100,
        "deadline": "2025-12-31",
        "status": "active",
        "retired": False,
    }


def _theme(project_id, name: str, month: int, shipped: int = 1) -> dict[str, object]:
    return {
        "project_id": project_id,
        "name": name,
        "target": 1,
        "done": shipped,
        "status": "in_focus",
        "milestones": [
            {
                "milestone_id": f"{name}-{month}-{n}",
                "name": f"Ship {n}",
                "done_on": f"2025-{month:02d}-0{n + 1}",
            }
            for n in range(shipped)
        ],
    }


async def test_theme_contribution_and_hint(env) -> None:
    env.app.state.clock = lambda: TODAY_AT
    env.app.state.key_result_service._clock = lambda: TODAY_AT
    rows = await setup_review(env, "Open source", "Routine")
    key_result = await add_key_result(
        env,
        rows,
        metric="Stars",
        themes=("Open source", "Routine"),
        start_value=0,
        target=100,
        year=2025,
    )
    user_id = await env.user_id()
    async with env.db() as db:
        await store_snapshot(
            db,
            user_id,
            "2025-04",
            make_snapshot(
                "2025-04",
                themes=[
                    _theme(str(rows["Open source"].id), "Open source", 4),
                    _theme(str(rows["Routine"].id), "Routine", 4),
                ],
                key_results=[_kr(str(key_result.id), 10, 10, 4)],
            ),
        )
        await store_snapshot(
            db,
            user_id,
            "2025-05",
            make_snapshot(
                "2025-05",
                themes=[
                    _theme(str(rows["Open source"].id), "Open source", 5),
                    _theme(str(rows["Routine"].id), "Routine", 5),
                ],
                key_results=[_kr(str(key_result.id), 20, 15, 5)],
            ),
        )
        review = await env.app.state.annual_review_service.review(db, user_id, 2025)

    found = review["goals"][0]["key_results"][0]
    assert len(found["themes"]) == 2
    theme = next(item for item in found["themes"] if item["name"] == "Open source")
    assert theme["shipped"] == 2
    assert theme["target_sum"] == 2
    assert theme["movement"]["fraction"] == 0.1
    assert theme["hint"] == "much_shipped_little_movement"
    assert theme["ranges"][0]["from"] == date(2025, 1, 1)
    assert theme["ranges"][0]["to"] is None


async def test_a_link_that_ended_only_counts_its_dates(env) -> None:
    env.app.state.clock = lambda: TODAY_AT
    env.app.state.key_result_service._clock = lambda: TODAY_AT
    rows = await setup_review(env, "Open source")
    key_result = await add_key_result(
        env,
        rows,
        metric="Stars",
        themes=("Open source",),
        start_value=0,
        target=100,
        year=2025,
    )
    user_id = await env.user_id()
    async with env.db() as db:
        link = (
            await db.execute(
                select(KeyResultTheme).where(KeyResultTheme.key_result_id == key_result.id)
            )
        ).scalar_one()
        link.started_at = datetime(2025, 3, 1, tzinfo=UTC)
        link.ended_at = datetime(2025, 7, 31, 23, tzinfo=UTC)
        await db.flush()
        await store_snapshot(
            db,
            user_id,
            "2025-02",
            make_snapshot(
                "2025-02",
                themes=[
                    {
                        "project_id": str(rows["Open source"].id),
                        "name": "Open source",
                        "target": 1,
                        "done": 1,
                        "status": "in_focus",
                        "milestones": [
                            {"milestone_id": "before", "name": "Before", "done_on": "2025-02-10"}
                        ],
                    }
                ],
                key_results=[_kr(str(key_result.id), 10, 10, 2)],
            ),
        )
        await store_snapshot(
            db,
            user_id,
            "2025-04",
            make_snapshot(
                "2025-04",
                themes=[
                    {
                        "project_id": str(rows["Open source"].id),
                        "name": "Open source",
                        "target": 1,
                        "done": 1,
                        "status": "in_focus",
                        "milestones": [
                            {"milestone_id": "inside", "name": "Inside", "done_on": "2025-04-10"}
                        ],
                    }
                ],
                key_results=[_kr(str(key_result.id), 20, 10, 4)],
            ),
        )
        review = await env.app.state.annual_review_service.review(db, user_id, 2025)
    theme = review["goals"][0]["key_results"][0]["themes"][0]
    assert theme["shipped"] == 1
    assert theme["milestones"][0]["milestone_id"] == "inside"
    assert theme["ranges"][0]["months"] == ["2025-03", "2025-04", "2025-05", "2025-06", "2025-07"]
    assert review["milestones_shipped"]["count"] == 2


async def test_mirror_hint_and_no_hint_without_a_target(env) -> None:
    env.app.state.clock = lambda: TODAY_AT
    env.app.state.key_result_service._clock = lambda: TODAY_AT
    rows = await setup_review(env, "Open source")
    key_result = await add_key_result(
        env,
        rows,
        metric="Stars",
        themes=("Open source",),
        start_value=0,
        target=100,
        year=2025,
    )
    user_id = await env.user_id()
    async with env.db() as db:
        await store_snapshot(
            db,
            user_id,
            "2025-04",
            make_snapshot(
                "2025-04",
                themes=[
                    {
                        "project_id": str(rows["Open source"].id),
                        "name": "Open source",
                        "target": 1,
                        "done": 0,
                        "status": "in_focus",
                        "milestones": [],
                    }
                ],
                key_results=[_kr(str(key_result.id), 10, 10, 4)],
            ),
        )
        await store_snapshot(
            db,
            user_id,
            "2025-05",
            make_snapshot(
                "2025-05",
                themes=[
                    {
                        "project_id": str(rows["Open source"].id),
                        "name": "Open source",
                        "target": 1,
                        "done": 0,
                        "status": "in_focus",
                        "milestones": [],
                    }
                ],
                key_results=[_kr(str(key_result.id), 60, 20, 5)],
            ),
        )
        review = await env.app.state.annual_review_service.review(db, user_id, 2025)
    theme = review["goals"][0]["key_results"][0]["themes"][0]
    assert theme["hint"] == "movement_not_from_theme"
