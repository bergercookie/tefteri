"""Migration tests: pytest-alembic's built-in checks plus per-revision data checks."""

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
