"""Migration tests: pytest-alembic's built-in checks plus per-revision data checks."""

from datetime import datetime

from pytest_alembic import MigrationContext
from pytest_alembic.tests import (
    test_model_definitions_match_ddl,
    test_single_head_revision,
    test_up_down_consistency,
    test_upgrade,
)
from sqlalchemy import Engine, inspect

__all__ = [
    "test_model_definitions_match_ddl",
    "test_single_head_revision",
    "test_up_down_consistency",
    "test_upgrade",
]


def test_0001_creates_core_tables(alembic_runner: MigrationContext, alembic_engine: Engine) -> None:
    alembic_runner.migrate_up_to("0001")
    tables = set(inspect(alembic_engine).get_table_names())
    assert {
        "users",
        "auth_sessions",
        "connections",
        "source_containers",
        "sync_runs",
        "conflicts",
    } <= tables


def test_0001_downgrade_removes_tables(
    alembic_runner: MigrationContext, alembic_engine: Engine
) -> None:
    alembic_runner.migrate_up_to("0001")
    alembic_runner.migrate_down_to("base")
    assert set(inspect(alembic_engine).get_table_names()) <= {"alembic_version"}


def test_0002_creates_mirror_tables_and_unique_keys(
    alembic_runner: MigrationContext, alembic_engine: Engine
) -> None:
    alembic_runner.migrate_up_to("0002")
    insp = inspect(alembic_engine)
    assert {"tasks", "calendar_entries", "notes"} <= set(insp.get_table_names())
    for table in ("tasks", "calendar_entries", "notes"):
        uniques = [set(u["column_names"]) for u in insp.get_unique_constraints(table)]
        assert {"connection_id", "remote_id"} in uniques


def test_0002_downgrade_keeps_0001_tables(
    alembic_runner: MigrationContext, alembic_engine: Engine
) -> None:
    alembic_runner.migrate_up_to("0002")
    alembic_runner.migrate_down_one()
    tables = set(inspect(alembic_engine).get_table_names())
    assert "users" in tables and "tasks" not in tables


def test_0003_creates_task_note_links(
    alembic_runner: MigrationContext, alembic_engine: Engine
) -> None:
    alembic_runner.migrate_up_to("0003")
    insp = inspect(alembic_engine)
    assert "task_note_links" in insp.get_table_names()
    uniques = [set(u["column_names"]) for u in insp.get_unique_constraints("task_note_links")]
    assert {"task_id", "note_id"} in uniques
    alembic_runner.migrate_down_one()
    assert "task_note_links" not in inspect(alembic_engine).get_table_names()


def test_0004_creates_goals_plans_and_links_tasks(
    alembic_runner: MigrationContext, alembic_engine: Engine
) -> None:
    alembic_runner.migrate_up_to("0004")
    insp = inspect(alembic_engine)
    assert {"goals", "plans"} <= set(insp.get_table_names())
    assert "goal_id" in {c["name"] for c in insp.get_columns("tasks")}
    alembic_runner.migrate_down_one()
    insp = inspect(alembic_engine)
    assert "goals" not in insp.get_table_names()
    assert "goal_id" in {c["name"] for c in insp.get_columns("tasks")}  # column came from 0002


def test_0005_creates_period_reviews(
    alembic_runner: MigrationContext, alembic_engine: Engine
) -> None:
    alembic_runner.migrate_up_to("0005")
    insp = inspect(alembic_engine)
    assert "period_reviews" in insp.get_table_names()
    uniques = [set(u["column_names"]) for u in insp.get_unique_constraints("period_reviews")]
    assert {"plan_id"} in uniques
    alembic_runner.migrate_down_one()
    insp = inspect(alembic_engine)
    assert "period_reviews" not in insp.get_table_names()
    assert "plans" in insp.get_table_names()


def test_0006_adds_random_time_setting_and_keeps_users(
    alembic_runner: MigrationContext, alembic_engine: Engine
) -> None:
    alembic_runner.migrate_up_to("0005")
    alembic_runner.insert_into("users", {"id": "11111111-1111-1111-1111-111111111111"} | _USER)
    alembic_runner.migrate_up_to("0006")
    columns = {c["name"]: c for c in inspect(alembic_engine).get_columns("users")}
    assert "random_time_on_date_drop" in columns
    with alembic_engine.connect() as conn:
        value = conn.exec_driver_sql("select random_time_on_date_drop from users").scalar()
    assert not value  # existing users get the default: off
    alembic_runner.migrate_down_one()
    assert "random_time_on_date_drop" not in {
        c["name"] for c in inspect(alembic_engine).get_columns("users")
    }
    with alembic_engine.connect() as conn:
        assert conn.exec_driver_sql("select count(*) from users").scalar() == 1


_USER = {
    "username": "sam",
    "password_hash": None,
    "is_admin": False,
    "timezone": "UTC",
    "disabled": False,
    "created_at": datetime(2026, 11, 1),
}
