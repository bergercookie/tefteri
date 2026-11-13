"""Key-result creation, validation, editing and active-slot limits."""

import asyncio
from collections.abc import Callable
from datetime import date
from pathlib import Path
from typing import cast

from httpx import AsyncClient
from sqlalchemy import func, select

from tefteri.config import Settings
from tefteri.db.models.goal import Goal
from tefteri.db.models.key_result import KeyResult
from tefteri.db.models.user import User
from tefteri.db.session import session_scope
from tefteri.main import create_app
from tefteri.services.errors import Conflict
from tests.conftest import V1

YEAR = 2026


async def _goal(api: AsyncClient, title: str = "Goal") -> str:
    response = await api.post(f"{V1}/annual/{YEAR}/goals/bulk", json={"goals": [{"title": title}]})
    assert response.status_code == 201, response.text
    return cast(str, response.json()["goals"][0]["id"])


async def _key_result(
    api: AsyncClient,
    goal_id: str,
    *,
    metric: str = "Measure",
    start: float = 0,
    target: float = 10,
    deadline: str = "2026-12-31",
    source: str = "manual",
) -> dict[str, object]:
    response = await api.post(
        f"{V1}/annual/goals/{goal_id}/key-results",
        json={
            "metric": metric,
            "start_value": start,
            "target": target,
            "deadline": deadline,
            "update_source": source,
        },
    )
    assert response.status_code == 201, response.text
    return cast(dict[str, object], response.json())


async def test_new_key_result_has_an_empty_series_and_uses_start_value(
    api: AsyncClient,
) -> None:
    goal_id = await _goal(api)
    key_result = await _key_result(api, goal_id, start=12, target=50)

    assert key_result["current_value"] == 12
    assert key_result["current_at"] is None
    assert key_result["progress"] == 0
    assert (await api.get(f"{V1}/annual/key-results/{key_result['id']}/values")).json() == []
    history = (await api.get(f"{V1}/annual/{YEAR}/history")).json()["changes"]
    created = next(row for row in history if row["kind"] == "key_result_created")
    assert created["key_result_id"] == key_result["id"]
    assert created["batch_id"]


async def test_fourth_active_key_result_is_rejected_and_retirement_frees_slot(
    api: AsyncClient,
) -> None:
    goal_id = await _goal(api)
    key_results = [await _key_result(api, goal_id, metric=f"Measure {i}") for i in range(3)]

    full = await api.post(
        f"{V1}/annual/goals/{goal_id}/key-results",
        json={
            "metric": "Fourth",
            "start_value": 0,
            "target": 10,
            "deadline": "2026-12-31",
        },
    )
    assert full.status_code == 409
    assert full.json()["code"] == "key_result_limit"

    retired = await api.post(f"{V1}/annual/key-results/{key_results[0]['id']}/retire", json={})
    assert retired.status_code == 200, retired.text
    restored_capacity = await _key_result(api, goal_id, metric="Replacement")
    assert restored_capacity["status"] == "active"


async def test_key_result_validation_names_invalid_fields(api: AsyncClient) -> None:
    goal_id = await _goal(api)
    same_target = await api.post(
        f"{V1}/annual/goals/{goal_id}/key-results",
        json={
            "metric": "Measure",
            "start_value": 10,
            "target": 10,
            "deadline": "2026-12-31",
        },
    )
    outside_year = await api.post(
        f"{V1}/annual/goals/{goal_id}/key-results",
        json={
            "metric": "Measure",
            "start_value": 0,
            "target": 10,
            "deadline": "2027-01-01",
        },
    )

    assert same_target.status_code == 422
    assert "target" in same_target.json()["detail"].lower()
    assert outside_year.status_code == 422
    assert "deadline" in outside_year.json()["detail"].lower()


async def test_editing_fields_records_old_and_new_values_and_start_is_immutable(
    api: AsyncClient,
) -> None:
    goal_id = await _goal(api)
    key_result = await _key_result(api, goal_id)
    response = await api.patch(
        f"{V1}/annual/key-results/{key_result['id']}",
        json={
            "metric": "  New measure ",
            "target": 20,
            "deadline": "2026-11-30",
            "update_source": "automatic",
            "start_value": 7,
        },
    )
    assert response.status_code == 200, response.text
    assert response.json()["metric"] == "New measure"
    assert response.json()["target"] == 20
    assert response.json()["start_value"] == 0
    assert response.json()["update_source"] == "automatic"

    history = (await api.get(f"{V1}/annual/{YEAR}/history")).json()["changes"]
    edits = [row for row in history if row["kind"] == "key_result_edited"]
    assert {row["field"] for row in edits} == {"metric", "target", "deadline", "update_source"}
    values = {row["field"]: (row["old_value"], row["new_value"]) for row in edits}
    assert values == {
        "metric": ("Measure", "New measure"),
        "target": ("10.0", "20.0"),
        "deadline": ("2026-12-31", "2026-11-30"),
        "update_source": ("manual", "automatic"),
    }


async def test_two_simultaneous_adds_cannot_exceed_three_active_key_results(
    make_settings: Callable[..., Settings],
    tmp_path: Path,
) -> None:
    app = create_app(
        make_settings(database_url=f"sqlite+aiosqlite:///{tmp_path / 'concurrency.db'}")
    )
    async with app.router.lifespan_context(app):
        factory = app.state.session_factory
        service = app.state.key_result_service
        async with session_scope(factory) as db:
            user = (await db.execute(select(User).where(User.username == "admin"))).scalar_one()
            goal = Goal(
                user_id=user.id,
                period_type="year",
                period_start=date(YEAR, 1, 1),
                title="Concurrent goal",
            )
            db.add(goal)
            await db.flush()
            goal_id, user_id = goal.id, user.id
            for metric in ("First", "Second"):
                await service.create(
                    db,
                    user_id,
                    goal,
                    metric=metric,
                    start_value=0,
                    target=10,
                    deadline=date(YEAR, 12, 31),
                )

        async def add(metric: str) -> str:
            try:
                async with session_scope(factory) as db:
                    goal = await db.get(Goal, goal_id)
                    assert goal is not None
                    await service.create(
                        db,
                        user_id,
                        goal,
                        metric=metric,
                        start_value=0,
                        target=10,
                        deadline=date(YEAR, 12, 31),
                    )
            except Conflict as exc:
                return exc.code
            return "created"

        outcomes = await asyncio.gather(add("Third A"), add("Third B"))

        assert sorted(outcomes) == ["created", "key_result_limit"]
        async with session_scope(factory) as db:
            count = await db.scalar(
                select(func.count())
                .select_from(KeyResult)
                .where(KeyResult.goal_id == goal_id, KeyResult.status == "active")
            )
        assert count == 3
