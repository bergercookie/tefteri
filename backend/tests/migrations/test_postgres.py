"""Run the migrations on a real PostgreSQL database (needs TEFTERI_TEST_POSTGRES_URL)."""

import asyncio
import os
from collections.abc import Callable
from pathlib import Path
from typing import Any

import pytest
from alembic import command
from alembic.config import Config

URL = os.environ.get("TEFTERI_TEST_POSTGRES_URL")

pytestmark = [
    pytest.mark.postgres,
    pytest.mark.skipif(URL is None, reason="TEFTERI_TEST_POSTGRES_URL is not set"),
]


def _with_connection[T](check: Callable[[Any], T]) -> T:
    """Run ``check`` with a sync connection on the asyncpg URL (there is no sync driver)."""
    from sqlalchemy.ext.asyncio import create_async_engine

    async def run() -> T:
        assert URL is not None
        engine = create_async_engine(URL)
        try:
            async with engine.connect() as conn:
                return await conn.run_sync(check)
        finally:
            await engine.dispose()

    return asyncio.run(run())


def test_upgrade_head_then_downgrade_base(monkeypatch: pytest.MonkeyPatch) -> None:
    assert URL is not None
    monkeypatch.setenv("TEFTERI_DATABASE_URL", URL)
    config = Config(str(Path(__file__).parents[2] / "alembic.ini"))
    config.set_main_option("script_location", str(Path(__file__).parents[2] / "migrations"))
    command.upgrade(config, "head")
    command.downgrade(config, "base")


def test_0022_creates_the_monthly_cycle_tables(monkeypatch: pytest.MonkeyPatch) -> None:
    """The monthly migration creates each table needed by focus and immutable reviews."""
    assert URL is not None
    monkeypatch.setenv("TEFTERI_DATABASE_URL", URL)
    config = Config(str(Path(__file__).parents[2] / "alembic.ini"))
    config.set_main_option("script_location", str(Path(__file__).parents[2] / "migrations"))
    command.upgrade(config, "head")
    try:
        from sqlalchemy import inspect

        tables = set(_with_connection(lambda conn: inspect(conn).get_table_names()))
        assert {
            "monthly_focuses",
            "monthly_focus_entries",
            "focus_changes",
            "monthly_reviews",
            "monthly_review_snapshots",
        } <= tables
    finally:
        command.downgrade(config, "base")


def test_0020_has_the_partial_index_and_checks_on_postgres(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    assert URL is not None
    monkeypatch.setenv("TEFTERI_DATABASE_URL", URL)
    config = Config(str(Path(__file__).parents[2] / "alembic.ini"))
    config.set_main_option("script_location", str(Path(__file__).parents[2] / "migrations"))
    command.upgrade(config, "head")
    try:
        _with_connection(_check_0020)
    finally:
        command.downgrade(config, "base")


def _check_0020(conn: Any) -> None:
    """The partial index, the checks and the slot rule of migration 0020 (R-03, R-04)."""
    from sqlalchemy import inspect, text
    from sqlalchemy.exc import IntegrityError

    active_links = {i["name"]: i for i in inspect(conn).get_indexes("key_result_themes")}
    assert active_links["uq_key_result_themes_active"]["unique"]
    checks = {
        row[0]: row[1]
        for row in conn.execute(
            text(
                "select conname, pg_get_constraintdef(oid) from pg_constraint "
                "where conrelid = 'key_results'::regclass and contype = 'c'"
            )
        )
    }
    assert "ck_key_results_target" in checks
    assert "start_value" in checks["ck_key_results_target"]
    assert "slot IS NOT NULL" in checks["ck_key_results_slot_state"]
    assert "ck_key_results_slot" in checks
    user_id = conn.execute(
        text(
            "insert into users (id, username, password_hash, is_admin, timezone, disabled,"
            " created_at) values (gen_random_uuid(), 'pgtest', null, false, 'UTC', false,"
            " now()) returning id"
        )
    ).scalar_one()
    goal_id = conn.execute(
        text(
            "insert into goals (id, user_id, period_type, period_start, title,"
            " description, criteria, status) values (gen_random_uuid(), :u, 'year',"
            " '2027-01-01', 'PG', '', '', 'active') returning id"
        ),
        {"u": user_id},
    ).scalar_one()
    insert = text(
        "insert into key_results (id, user_id, goal_id, year, metric, start_value,"
        " target, deadline, update_source, status, slot, position, created_at,"
        " updated_at) values (gen_random_uuid(), :user_id, :goal_id, 2027, 'm', 0, 1,"
        " '2027-12-31', 'manual', 'active', 1, 0, now(), now())"
    )
    key_result = {"user_id": user_id, "goal_id": goal_id}
    # Two active key results cannot share a slot on PostgreSQL (R-03).
    conn.execute(insert, key_result)
    try:
        conn.execute(insert, key_result)
        conn.commit()
        raise AssertionError("the second key result in slot 1 was accepted")
    except IntegrityError:
        conn.rollback()
