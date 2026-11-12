"""Monthly reviews read key-result history and write only explicitly typed values."""

from datetime import UTC, date, datetime, time, timedelta
from typing import Any

import pytest
from sqlalchemy import func, select

from tefteri.db.models.key_result import KeyResult, KeyResultTheme, KeyResultValue
from tefteri.db.models.monthly import MonthlyFocus, MonthlyFocusEntry
from tefteri.domain.enums import ValueSource
from tefteri.services.errors import Conflict
from tests.integration.conftest import ProjectsEnv
from tests.integration.monthly_review_helpers import (
    MONTH,
    TODAY,
    add_key_result,
    add_milestone,
    setup_review,
)


async def test_review_values_are_read_only_until_store_and_are_retry_safe(
    env: ProjectsEnv,
    monkeypatch,
) -> None:
    rows = await setup_review(env, "Theme")
    key_result = await add_key_result(
        env,
        rows,
        metric="Automatic metric",
        themes=("Theme",),
        source="automatic",
        values=((MONTH - timedelta(days=2), 14), (MONTH + timedelta(days=3), 21)),
    )
    service = env.app.state.monthly_review_service
    backend_calls = []

    def forbidden_source_call(*args, **kwargs):
        backend_calls.append((args, kwargs))
        raise AssertionError("review attempted to pull an automatic value")

    monkeypatch.setattr(env.app.state.connection_service, "backend_for", forbidden_source_call)
    async with env.db() as db:
        draft = await service.draft(db, await env.user_id(), MONTH, tz="UTC")
    result = next(
        item
        for item in draft.snapshot["key_results"]
        if item["key_result_id"] == str(key_result.id)
    )
    assert result["latest_value"] == 21
    assert result["status"] == "updated"
    assert result["latest_at"].startswith((MONTH + timedelta(days=3)).isoformat())
    assert backend_calls == []

    manual = await add_key_result(
        env,
        rows,
        metric="Manual metric",
        themes=("Theme",),
        values=((MONTH - timedelta(days=1), 12),),
    )
    async with env.db() as db:
        skipped = await service.draft(db, await env.user_id(), MONTH, tz="UTC")
    skipped_value = next(
        item for item in skipped.snapshot["key_results"] if item["key_result_id"] == str(manual.id)
    )
    assert skipped_value["latest_value"] == 12
    assert skipped_value["status"] == "not_updated"
    assert manual.id in skipped.value_prompts
    async with env.db() as db:
        preview = await service.draft(
            db, await env.user_id(), MONTH, tz="UTC", key_result_values={manual.id: 18}
        )
    manual_preview = next(
        item for item in preview.snapshot["key_results"] if item["key_result_id"] == str(manual.id)
    )
    assert manual_preview["latest_value"] == 18
    assert manual_preview["status"] == "updated"
    async with env.db() as db:
        count = await db.scalar(
            select(func.count())
            .select_from(KeyResultValue)
            .where(KeyResultValue.key_result_id == manual.id)
        )
    assert count == 1
    async with env.db() as db:
        dry_run = await service.store(
            db,
            await env.user_id(),
            MONTH,
            tz="UTC",
            key_result_values={manual.id: 18},
            dry_run=True,
        )
    assert dry_run.snapshot["key_results"]
    assert dry_run.version == 1
    manual_dry_run = next(
        item for item in dry_run.snapshot["key_results"] if item["key_result_id"] == str(manual.id)
    )
    assert manual_dry_run["latest_value"] == 18
    async with env.db() as db:
        assert (
            await db.scalar(
                select(func.count())
                .select_from(KeyResultValue)
                .where(KeyResultValue.key_result_id == manual.id)
            )
            == 1
        )

    saved = await _store(env, service, {manual.id: 18})
    assert saved.version == 1
    saved_manual = next(
        item for item in saved.snapshot["key_results"] if item["key_result_id"] == str(manual.id)
    )
    assert saved_manual["latest_value"] == 18 and saved_manual["entered_in_review"] is True
    written = saved.values_written
    assert len(written) == 1 and written[0]["key_result_id"] == str(manual.id)
    async with env.db() as db:
        row = (
            (
                await db.execute(
                    select(KeyResultValue).where(
                        KeyResultValue.key_result_id == manual.id,
                        KeyResultValue.on_date == TODAY,
                    )
                )
            )
            .scalars()
            .one()
        )
        assert row.source == ValueSource.MANUAL.value and row.on_date == TODAY
        count = await db.scalar(
            select(func.count())
            .select_from(KeyResultValue)
            .where(KeyResultValue.key_result_id == manual.id)
        )
    assert count == 2
    await _store(env, service, {manual.id: 18}, confirm=True)
    async with env.db() as db:
        count = await db.scalar(
            select(func.count())
            .select_from(KeyResultValue)
            .where(KeyResultValue.key_result_id == manual.id)
        )
    assert count == 2
    assert backend_calls == []


async def test_shared_key_result_is_listed_once_with_month_base_and_gap(env: ProjectsEnv) -> None:
    rows = await setup_review(env, "Theme one", "Theme two")
    key_result = await add_key_result(
        env,
        rows,
        metric="Shared metric",
        themes=("Theme one", "Theme two"),
        start_value=2,
        values=((MONTH - timedelta(days=1), 5), (MONTH + timedelta(days=1), 9)),
    )
    await add_milestone(
        env, "Shipped milestone", done_on=MONTH + timedelta(days=2), theme_name="Theme one"
    )
    async with env.db() as db:
        draft = await env.app.state.monthly_review_service.draft(
            db, await env.user_id(), MONTH, tz="UTC"
        )
    (result,) = [
        item
        for item in draft.snapshot["key_results"]
        if item["key_result_id"] == str(key_result.id)
    ]
    assert (result["base_value"], result["latest_value"], result["change"], result["shared"]) == (
        5,
        9,
        4,
        True,
    )
    assert "score" not in result
    themes = {item["name"]: item for item in draft.snapshot["themes"]}
    assert themes["Theme one"]["key_result_ids"] == [str(key_result.id)]
    assert themes["Theme one"]["done"] == 1
    assert themes["Theme two"]["key_result_ids"] == [str(key_result.id)]


async def test_key_result_links_are_selected_by_their_historical_month_window(
    env: ProjectsEnv,
) -> None:
    rows = await setup_review(env, "Too early", "Too late", "Valid")
    key_result = await add_key_result(
        env,
        rows,
        metric="Historical links",
        themes=("Too early", "Too late", "Valid"),
    )
    next_month = MONTH.replace(day=28) + timedelta(days=4)
    next_month = next_month.replace(day=1)
    async with env.db() as db:
        links = list(
            (
                await db.execute(
                    select(KeyResultTheme).where(KeyResultTheme.key_result_id == key_result.id)
                )
            ).scalars()
        )
        by_project = {link.project_id: link for link in links}
        by_project[rows["Too early"].id].started_at = datetime.combine(next_month, time.min, UTC)
        by_project[rows["Too late"].id].ended_at = datetime.combine(
            MONTH - timedelta(days=1), time.min, UTC
        )
        by_project[rows["Valid"].id].started_at = datetime.combine(
            MONTH + timedelta(days=3), time.min, UTC
        )
        by_project[rows["Valid"].id].ended_at = datetime.combine(
            MONTH + timedelta(days=20), time.min, UTC
        )
    async with env.db() as db:
        draft = await env.app.state.monthly_review_service.draft(
            db, await env.user_id(), MONTH, tz="UTC"
        )
    result = next(
        item
        for item in draft.snapshot["key_results"]
        if item["key_result_id"] == str(key_result.id)
    )
    assert result["theme_ids"] == [str(rows["Valid"].id)]
    themes = {item["name"]: item for item in draft.snapshot["themes"]}
    assert themes["Valid"]["key_result_ids"] == [str(key_result.id)]
    assert themes["Too early"]["key_result_ids"] == []
    assert themes["Too late"]["key_result_ids"] == []


async def test_review_values_use_month_base_and_past_year_is_value_only(env: ProjectsEnv) -> None:
    rows = await setup_review(env, "Theme")
    key_result = await add_key_result(
        env,
        rows,
        metric="Series base",
        themes=("Theme",),
        start_value=5,
        values=((MONTH - timedelta(days=3), 8), (MONTH + timedelta(days=2), 14)),
    )
    async with env.db() as db:
        result = await env.app.state.monthly_review_service.draft(
            db, await env.user_id(), MONTH, tz="UTC"
        )
    payload = next(
        item
        for item in result.snapshot["key_results"]
        if item["key_result_id"] == str(key_result.id)
    )
    assert (payload["base_value"], payload["latest_value"], payload["change"]) == (8, 14, 6)

    past = await add_key_result(
        env,
        rows,
        metric="Past planning year",
        themes=("Theme",),
        year=MONTH.year - 1,
        status="active",
    )
    before = (past.metric, past.year, past.target, past.deadline)
    past_month = date(MONTH.year - 1, 12, 1)
    async with env.db() as db:
        focus = MonthlyFocus(user_id=await env.user_id(), month=past_month)
        db.add(focus)
        await db.flush()
        db.add(
            MonthlyFocusEntry(
                focus_id=focus.id,
                project_id=rows["Theme"].id,
                name="Theme",
                target=None,
                counts_from=past_month,
                position=0,
            )
        )
    saved = await _store(env, env.app.state.monthly_review_service, {past.id: 40}, month=past_month)
    assert saved.version == 1
    async with env.db() as db:
        saved_key_result = await db.get(KeyResult, past.id)
        assert saved_key_result is not None
        assert (
            saved_key_result.metric,
            saved_key_result.year,
            saved_key_result.target,
            saved_key_result.deadline,
        ) == before


async def test_retired_key_result_cannot_take_a_review_value(env: ProjectsEnv) -> None:
    rows = await setup_review(env, "Theme")
    retired = await add_key_result(env, rows, metric="Retired", themes=("Theme",), status="retired")
    service = env.app.state.monthly_review_service
    async with env.db() as db:
        draft = await service.draft(db, await env.user_id(), MONTH, tz="UTC")
    result = next(
        item for item in draft.snapshot["key_results"] if item["key_result_id"] == str(retired.id)
    )
    assert result["retired"] is True
    assert retired.id not in draft.value_prompts
    with pytest.raises(Conflict) as error:
        await _store(env, service, {retired.id: 20})
    assert error.value.code == "retired"


async def _store(
    env: ProjectsEnv,
    service: Any,
    values: dict,
    *,
    confirm: bool = False,
    month=MONTH,
):
    async with env.db() as db:
        return await service.store(
            db,
            await env.user_id(),
            month,
            tz="UTC",
            key_result_values=values,
            confirm_new_version=confirm,
        )
