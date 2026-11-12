"""Run the migrations on a real PostgreSQL database (needs TEFTERI_TEST_POSTGRES_URL)."""

import os
from pathlib import Path

import pytest
from alembic import command
from alembic.config import Config

URL = os.environ.get("TEFTERI_TEST_POSTGRES_URL")

pytestmark = [
    pytest.mark.postgres,
    pytest.mark.skipif(URL is None, reason="TEFTERI_TEST_POSTGRES_URL is not set"),
]


def test_upgrade_head_then_downgrade_base(monkeypatch: pytest.MonkeyPatch) -> None:
    assert URL is not None
    monkeypatch.setenv("TEFTERI_DATABASE_URL", URL)
    config = Config(str(Path(__file__).parents[2] / "alembic.ini"))
    config.set_main_option("script_location", str(Path(__file__).parents[2] / "migrations"))
    command.upgrade(config, "head")
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
        from sqlalchemy import create_engine, inspect, text

        engine = create_engine(URL)
        insp = inspect(engine)
        active_links = {i["name"]: i for i in insp.get_indexes("key_result_themes")}
        assert active_links["uq_key_result_themes_active"]["unique"]
        with engine.connect() as conn:
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
        with engine.connect() as conn:
            rows = conn.execute(
                text(
                    "insert into users (id, username, password_hash, is_admin, timezone, disabled,"
                    " created_at) values (gen_random_uuid(), 'pgtest', null, false, 'UTC', false,"
                    " now()) returning id"
                )
            ).fetchone()
            user_id = rows[0]
            goal_id = conn.execute(
                text(
                    "insert into goals (id, user_id, period_type, period_start, title,"
                    " description, criteria, status) values (gen_random_uuid(), :u, 'year',"
                    " '2027-01-01', 'PG', '', '', 'active') returning id"
                ),
                {"u": user_id},
            ).fetchone()[0]
            key_result = {
                "id": None,
                "user_id": user_id,
                "goal_id": goal_id,
                "year": 2027,
                "metric": "m",
                "start_value": 0,
                "target": 1,
                "deadline": "2027-12-31",
                "update_source": "manual",
                "status": "active",
                "slot": 1,
                "position": 0,
                "created_at": "now()",
                "updated_at": "now()",
            }
            # Two active key results cannot share a slot on PostgreSQL (R-03).
            conn.execute(
                text(
                    "insert into key_results (id, user_id, goal_id, year, metric, start_value,"
                    " target, deadline, update_source, status, slot, position, created_at,"
                    " updated_at) values (gen_random_uuid(), :user_id, :goal_id, 2027, 'm', 0, 1,"
                    " '2027-12-31', 'manual', 'active', 1, 0, now(), now())"
                ),
                key_result,
            )
            from sqlalchemy.exc import IntegrityError

            try:
                conn.execute(
                    text(
                        "insert into key_results (id, user_id, goal_id, year, metric, start_value,"
                        " target, deadline, update_source, status, slot, position, created_at,"
                        " updated_at) values (gen_random_uuid(), :user_id, :goal_id, 2027, 'm', 0,"
                        " 1, '2027-12-31', 'manual', 'active', 1, 0, now(), now())"
                    ),
                    key_result,
                )
                conn.commit()
                raise AssertionError("the second key result in slot 1 was accepted")
            except IntegrityError:
                conn.rollback()
        engine.dispose()
    finally:
        command.downgrade(config, "base")
