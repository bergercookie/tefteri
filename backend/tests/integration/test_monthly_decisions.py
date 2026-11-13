"""Review decisions are versioned and drive only computed next-month suggestions."""

from datetime import date, timedelta
from typing import Any

import pytest

from tefteri.services.errors import NotAFocusTheme
from tests.integration.conftest import ProjectsEnv
from tests.integration.monthly_review_helpers import MONTH, setup_review


async def test_decisions_snapshot_effects_and_next_month_suggestions(env: ProjectsEnv) -> None:
    rows = await setup_review(env, "Carry", "Drop", "Replace", "Later", "New")
    service = env.app.state.monthly_review_service
    decisions = [
        {"project_id": rows["Carry"].id, "decision": "carry"},
        {"project_id": rows["Drop"].id, "decision": "drop"},
        {
            "project_id": rows["Replace"].id,
            "decision": "replace",
            "replacement_project_id": rows["New"].id,
        },
        {"project_id": rows["Later"].id, "decision": "later"},
    ]
    async with env.db() as db:
        preview = await service.draft(db, await env.user_id(), MONTH, tz="UTC", decisions=decisions)
    assert len(preview.effects) == len(rows) - 1
    assert all(effect.message for effect in preview.effects)
    assert {item["decision"] for item in preview.snapshot["decisions"]} == {
        "carry",
        "drop",
        "replace",
        "later",
    }

    with pytest.raises(NotAFocusTheme) as invalid:
        async with env.db() as db:
            await service.draft(
                db,
                await env.user_id(),
                MONTH,
                tz="UTC",
                decisions=[
                    {
                        "project_id": rows["Carry"].id,
                        "decision": "replace",
                        "replacement_project_id": rows["Carry"].id,
                    }
                ],
            )
    assert invalid.value.code == "not_a_theme"

    async with env.db() as db:
        saved = await service.store(db, await env.user_id(), MONTH, tz="UTC", decisions=decisions)
    next_month = MONTH.replace(day=28) + timedelta(days=4)
    next_month = next_month.replace(day=1)
    suggestions = await _suggestions(env, service, next_month)
    assert suggestions.from_month == MONTH
    assert {(item["name"], item["target"], item["reason"]) for item in suggestions.suggestions} == {
        ("Carry", None, "carry"),
        ("New", None, "replace"),
    }
    async with env.db() as db:
        plan = await env.app.state.monthly_focus_service.plan(
            db, await env.user_id(), next_month, tz="UTC"
        )
    assert plan.focus_known is False
    assert saved.version == 1


async def test_decision_change_requires_new_version_and_uses_current_version(
    env: ProjectsEnv,
) -> None:
    rows = await setup_review(env, "Theme", "Replacement")
    service = env.app.state.monthly_review_service
    first = [{"project_id": rows["Theme"].id, "decision": "carry"}]
    second = [{"project_id": rows["Theme"].id, "decision": "drop"}]
    async with env.db() as db:
        await service.store(db, await env.user_id(), MONTH, tz="UTC", decisions=first)
    with pytest.raises(Exception) as required:
        async with env.db() as db:
            await service.store(db, await env.user_id(), MONTH, tz="UTC", decisions=second)
    assert getattr(required.value, "code", None) == "confirm_required"
    async with env.db() as db:
        saved = await service.store(
            db,
            await env.user_id(),
            MONTH,
            tz="UTC",
            decisions=second,
            confirm_new_version=True,
        )
    assert saved.version == 2
    next_month = MONTH.replace(day=28) + timedelta(days=4)
    next_month = next_month.replace(day=1)
    suggestions = await _suggestions(env, service, next_month)
    assert suggestions.suggestions == ()


async def _suggestions(env: ProjectsEnv, service: Any, month: date) -> Any:
    async with env.db() as db:
        return await service.suggestions(db, await env.user_id(), month)
