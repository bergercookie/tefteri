"""Annual-plan retirement, restore, undo and immutable period-review history."""

import json
import uuid
from datetime import UTC, date, datetime, timedelta
from typing import Any

from httpx import AsyncClient
from sqlalchemy import select

from tefteri.db.models.goal import Plan
from tefteri.db.models.key_result import KeyResult, KeyResultTheme, KeyResultValue
from tefteri.db.models.review import PeriodReview
from tefteri.domain.entities import Container
from tests.conftest import V1
from tests.integration.conftest import ProjectsEnv

YEAR = 2030
NOW = datetime(2030, 6, 1, 12, tzinfo=UTC)


def _freeze(api: AsyncClient, now: datetime = NOW) -> None:
    app = api.app  # type: ignore[attr-defined]
    app.state.annual_service._clock = lambda: now
    app.state.key_result_service._clock = lambda: now


async def _theme(env: ProjectsEnv) -> str:
    await env.connect(Container("p2", "Open source"))
    project_id = (await env.rows())["Open source"].id
    response = await env.api.put(
        f"{V1}/projects/labels",
        json={"changes": [{"id": str(project_id), "label": "theme"}]},
    )
    assert response.status_code == 200, response.text
    return str(project_id)


async def _create_goal(
    api: AsyncClient,
    *,
    title: str = "Goal",
    key_results: list[dict[str, Any]] | None = None,
) -> dict[str, Any]:
    response = await api.post(
        f"{V1}/annual/{YEAR}/goals/bulk",
        json={
            "goals": [
                {
                    "title": title,
                    "key_results": key_results or [],
                }
            ]
        },
    )
    assert response.status_code == 201, response.text
    return response.json()["goals"][0]


def _key_result(metric: str = "Measure", *, themes: list[str] | None = None) -> dict[str, Any]:
    return {
        "metric": metric,
        "start_value": 0,
        "target": 10,
        "deadline": f"{YEAR}-12-31",
        "theme_ids": themes or [],
    }


async def _review_snapshot(env: ProjectsEnv) -> bytes:
    async with env.db() as db:
        rows = list((await db.execute(select(PeriodReview).order_by(PeriodReview.id))).scalars())
    serialized = [
        {
            column.name: (
                value.isoformat()
                if isinstance(value, (date, datetime))
                else str(value)
                if value is not None and not isinstance(value, (str, int, float, bool, list, dict))
                else value
            )
            for column in PeriodReview.__table__.columns
            for value in [getattr(row, column.name)]
        }
        for row in rows
    ]
    return json.dumps(serialized, sort_keys=True, separators=(",", ":")).encode()


async def _add_period_review(env: ProjectsEnv) -> None:
    user_id = await env.user_id()
    async with env.db() as db:
        plan = Plan(
            user_id=user_id,
            period_type="week",
            period_start=date(2030, 5, 27),
            title="Stored review plan",
            summary="unchanged",
        )
        db.add(plan)
        await db.flush()
        db.add(
            PeriodReview(
                user_id=user_id,
                plan_id=plan.id,
                generated_at=NOW,
                planned_count=2,
                completed_count=1,
                carried_over=["one"],
                items=[{"title": "kept", "state": "active"}],
            )
        )


async def test_key_result_retire_preview_matches_write_and_preserves_series_and_history(
    env: ProjectsEnv,
) -> None:
    _freeze(env.api)
    theme_id = await _theme(env)
    goal = await _create_goal(env.api, key_results=[_key_result()])
    key_result = goal["key_results"][0]
    linked = await env.api.put(
        f"{V1}/annual/key-results/{key_result['id']}/themes",
        json={"theme_ids": [theme_id]},
    )
    assert linked.status_code == 200, linked.text
    user_id = await env.user_id()
    async with env.db() as db:
        db.add(
            KeyResultValue(
                user_id=user_id,
                key_result_id=uuid.UUID(key_result["id"]),
                value=4,
                at=datetime(2030, 5, 30, 12, tzinfo=UTC),
                on_date=date(2030, 5, 30),
                source="manual",
                seq=1,
            )
        )

    before_history = (await env.api.get(f"{V1}/annual/{YEAR}/history")).json()
    preview = await env.api.post(
        f"{V1}/annual/key-results/{key_result['id']}/retire",
        json={"reason": "No longer relevant", "dry_run": True},
    )
    assert preview.status_code == 200, preview.text
    assert preview.json()["effect"]["key_results_retired"] == 1
    assert preview.json()["effect"]["links_ended"] == 1
    assert preview.json()["effect"]["history_kept"] is True
    assert (await env.api.get(f"{V1}/annual/{YEAR}/history")).json() == before_history

    retired = await env.api.post(
        f"{V1}/annual/key-results/{key_result['id']}/retire",
        json={"reason": "No longer relevant"},
    )
    assert retired.status_code == 200, retired.text
    assert retired.json()["effect"] == preview.json()["effect"]
    assert retired.json()["batch_id"]

    async with env.db() as db:
        stored = await db.get(KeyResult, uuid.UUID(key_result["id"]))
        series = list(
            (
                await db.execute(
                    select(KeyResultValue).where(
                        KeyResultValue.key_result_id == uuid.UUID(key_result["id"])
                    )
                )
            ).scalars()
        )
        links = list(
            (
                await db.execute(
                    select(KeyResultTheme).where(
                        KeyResultTheme.key_result_id == uuid.UUID(key_result["id"])
                    )
                )
            ).scalars()
        )
    assert stored is not None and stored.status == "retired" and stored.slot is None
    assert [(row.value, row.on_date) for row in series] == [(4, date(2030, 5, 30))]
    assert len(links) == 1
    assert links[0].ended_at is not None
    assert links[0].end_reason == "key_result_retired"

    replacement = await env.api.post(
        f"{V1}/annual/goals/{goal['id']}/key-results",
        json=_key_result("Replacement"),
    )
    assert replacement.status_code == 201, replacement.text
    changes = (await env.api.get(f"{V1}/annual/{YEAR}/history")).json()
    retire_rows = [row for row in changes if row["batch_id"] == retired.json()["batch_id"]]
    assert {row["kind"] for row in retire_rows} == {"key_result_retired", "link_removed"}
    retire_row = next(row for row in retire_rows if row["kind"] == "key_result_retired")
    assert retire_row["reason"] == "No longer relevant"
    assert next(row for row in retire_rows if row["kind"] == "link_removed")["reason"] is None


async def test_goal_retire_undo_restores_every_key_result_and_is_recorded_once(
    api: AsyncClient,
) -> None:
    _freeze(api)
    goal = await _create_goal(
        api,
        key_results=[_key_result("First"), _key_result("Second")],
    )
    preview = await api.post(
        f"{V1}/annual/goals/{goal['id']}/retire",
        json={"reason": "Changed direction", "dry_run": True},
    )
    assert preview.status_code == 200, preview.text
    assert preview.json()["effect"]["key_results_retired"] == 2
    assert preview.json()["effect"]["links_ended"] == 0

    retired = await api.post(
        f"{V1}/annual/goals/{goal['id']}/retire",
        json={"reason": "Changed direction"},
    )
    assert retired.status_code == 200, retired.text
    assert retired.json()["effect"] == preview.json()["effect"]
    batch_id = retired.json()["batch_id"]
    history = (await api.get(f"{V1}/annual/{YEAR}/history")).json()
    batch = [row for row in history if row["batch_id"] == batch_id]
    assert [row["kind"] for row in batch].count("goal_retired") == 1
    assert [row["kind"] for row in batch].count("key_result_retired") == 2
    assert all(row["reason"] == "Changed direction" for row in batch)

    undone = await api.post(f"{V1}/annual/undo", json={"batch_id": batch_id})
    assert undone.status_code == 200, undone.text
    assert undone.json()["restored"] == 3
    plan = (await api.get(f"{V1}/annual/{YEAR}")).json()
    restored_goal = next(row for row in plan["goals"] if row["id"] == goal["id"])
    assert restored_goal["status"] == "active"
    assert {row["status"] for row in restored_goal["key_results"]} == {"active"}
    undo_rows = [
        row
        for row in (await api.get(f"{V1}/annual/{YEAR}/history")).json()
        if row["batch_id"] == batch_id and row["source"] == "undo"
    ]
    assert {row["kind"] for row in undo_rows} == {"goal_restored", "key_result_restored"}
    assert len(undo_rows) == 3

    again = await api.post(f"{V1}/annual/undo", json={"batch_id": batch_id})
    assert again.status_code == 409
    assert again.json()["code"] == "already_undone"


async def test_restore_with_no_free_slot_changes_nothing(api: AsyncClient) -> None:
    _freeze(api)
    goal = await _create_goal(
        api,
        key_results=[_key_result(f"Measure {index}") for index in range(3)],
    )
    retired_kr = goal["key_results"][0]["id"]
    retired = await api.post(f"{V1}/annual/key-results/{retired_kr}/retire", json={})
    assert retired.status_code == 200, retired.text
    replacement = await api.post(
        f"{V1}/annual/goals/{goal['id']}/key-results",
        json=_key_result("Replacement"),
    )
    assert replacement.status_code == 201, replacement.text
    history_before = (await api.get(f"{V1}/annual/{YEAR}/history")).json()

    response = await api.post(f"{V1}/annual/key-results/{retired_kr}/restore")

    assert response.status_code == 409
    assert response.json()["code"] == "key_result_limit"
    assert (await api.get(f"{V1}/annual/{YEAR}/history")).json() == history_before
    async with api.app.state.session_factory() as db:  # type: ignore[attr-defined]
        stored = await db.get(KeyResult, uuid.UUID(retired_kr))
    assert stored is not None and stored.status == "retired" and stored.slot is None


async def test_restore_skips_a_theme_that_is_no_longer_eligible(env: ProjectsEnv) -> None:
    _freeze(env.api)
    theme_id = await _theme(env)
    goal = await _create_goal(env.api, key_results=[_key_result()])
    key_result_id = goal["key_results"][0]["id"]
    linked = await env.api.put(
        f"{V1}/annual/key-results/{key_result_id}/themes",
        json={"theme_ids": [theme_id]},
    )
    assert linked.status_code == 200, linked.text
    retired = await env.api.post(f"{V1}/annual/key-results/{key_result_id}/retire", json={})
    assert retired.status_code == 200, retired.text

    label = await env.api.put(
        f"{V1}/projects/labels",
        json={"changes": [{"id": theme_id, "label": "ignored"}]},
    )
    assert label.status_code == 200, label.text
    restored = await env.api.post(f"{V1}/annual/key-results/{key_result_id}/restore")
    assert restored.status_code == 200, restored.text
    assert restored.json()["links_restored"] == 0
    assert [entry["name"] for entry in restored.json()["links_skipped"]] == ["Open source"]


async def test_history_is_time_ordered_and_period_reviews_are_unchanged(
    env: ProjectsEnv,
) -> None:
    clock = {"now": NOW}
    _freeze(env.api)
    env.api.app.state.annual_service._clock = lambda: clock["now"]  # type: ignore[attr-defined]
    env.api.app.state.key_result_service._clock = lambda: clock["now"]  # type: ignore[attr-defined]
    theme_id = await _theme(env)
    goal = await _create_goal(
        env.api,
        title="Before",
        key_results=[_key_result()],
    )
    key_result_id = goal["key_results"][0]["id"]
    linked = await env.api.put(
        f"{V1}/annual/key-results/{key_result_id}/themes",
        json={"theme_ids": [theme_id]},
    )
    assert linked.status_code == 200, linked.text
    await _add_period_review(env)
    original_review = await _review_snapshot(env)

    clock["now"] += timedelta(seconds=1)
    edited = await env.api.patch(f"{V1}/annual/goals/{goal['id']}", json={"title": "After"})
    assert edited.status_code == 200, edited.text
    edited_at = clock["now"]
    clock["now"] += timedelta(seconds=1)
    retired = await env.api.post(
        f"{V1}/annual/key-results/{key_result_id}/retire",
        json={"reason": "Keep the review snapshot"},
    )
    assert retired.status_code == 200, retired.text
    clock["now"] += timedelta(seconds=1)
    restored = await env.api.post(f"{V1}/annual/key-results/{key_result_id}/restore")
    assert restored.status_code == 200, restored.text
    clock["now"] += timedelta(seconds=1)
    relinked = await env.api.put(
        f"{V1}/annual/key-results/{key_result_id}/themes",
        json={"theme_ids": []},
    )
    assert relinked.status_code == 200, relinked.text
    clock["now"] += timedelta(seconds=1)
    relinked = await env.api.put(
        f"{V1}/annual/key-results/{key_result_id}/themes",
        json={"theme_ids": [theme_id]},
    )
    assert relinked.status_code == 200, relinked.text

    history = (await env.api.get(f"{V1}/annual/{YEAR}/history")).json()
    instants = [datetime.fromisoformat(row["at"].replace("Z", "+00:00")) for row in history]
    assert instants == sorted(instants)
    edit_row = next(row for row in history if row["kind"] == "goal_edited")
    assert (edit_row["old_value"], edit_row["new_value"]) == ("Before", "After")
    edit_at = datetime.fromisoformat(edit_row["at"].replace("Z", "+00:00"))
    if edit_at.tzinfo is None:
        edit_at = edit_at.replace(tzinfo=UTC)
    assert edit_at == edited_at
    retire_row = next(row for row in history if row["kind"] == "key_result_retired")
    assert retire_row["reason"] == "Keep the review snapshot"
    assert await _review_snapshot(env) == original_review
