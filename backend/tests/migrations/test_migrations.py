"""Migration tests: pytest-alembic's built-in checks plus per-revision data checks."""

from datetime import date, datetime

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


def test_0016_adds_checklists_and_keeps_users(
    alembic_runner: MigrationContext, alembic_engine: Engine
) -> None:
    alembic_runner.migrate_up_to("0015")
    alembic_runner.insert_into("users", {"id": "11111111-1111-1111-1111-111111111111"} | _USER)
    alembic_runner.migrate_up_to("0016")
    columns = {c["name"] for c in inspect(alembic_engine).get_columns("users")}
    assert "checklists" in columns
    with alembic_engine.connect() as conn:
        assert conn.exec_driver_sql("select checklists from users").scalar() in ("{}", {})
    assert "checklist_progress" in inspect(alembic_engine).get_table_names()
    alembic_runner.migrate_down_one()
    assert "checklist_progress" not in inspect(alembic_engine).get_table_names()
    assert "checklists" not in {c["name"] for c in inspect(alembic_engine).get_columns("users")}
    with alembic_engine.connect() as conn:
        assert conn.exec_driver_sql("select count(*) from users").scalar() == 1


def test_0017_drops_the_note_copies_that_sync_made(
    alembic_runner: MigrationContext, alembic_engine: Engine
) -> None:
    alembic_runner.migrate_up_to("0016")
    user = "11111111-1111-1111-1111-111111111111"
    alembic_runner.insert_into("users", {"id": user} | _USER)
    conn = {
        "user_id": user,
        "provider": "x",
        "settings": {},
        "status": "ok",
        "created_at": datetime(2026, 11, 1),
    }
    tasks_conn, notes_conn = (
        "aaaaaaaa-0000-0000-0000-000000000001",
        "aaaaaaaa-0000-0000-0000-000000000002",
    )
    alembic_runner.insert_into(
        "connections", conn | {"id": tasks_conn, "kind": "tasks", "display_name": "T"}
    )
    alembic_runner.insert_into(
        "connections", conn | {"id": notes_conn, "kind": "notes", "display_name": "N"}
    )
    for n, owner_conn in ((1, tasks_conn), (2, notes_conn)):
        alembic_runner.insert_into(
            "source_containers",
            {
                "id": f"bbbbbbbb-0000-0000-0000-00000000000{n}",
                "user_id": user,
                "connection_id": owner_conn,
                "remote_id": f"c{n}",
                "name": f"C{n}",
            },
        )
    note = {"user_id": user, "connection_id": notes_conn, "body": "", "remote_version": "v1"}
    note |= {"sync_state": "synced"}
    for n, kind in ((1, "custom"), (2, "custom"), (3, "daily")):
        alembic_runner.insert_into(
            "notes",
            note
            | {
                "id": f"cccccccc-0000-0000-0000-00000000000{n}",
                "remote_id": f"n{n}",
                "kind": kind,
                "title": f"Note {n}",
            },
        )
    # Note 2 is the retrospective of a review, so something points at it.
    alembic_runner.insert_into(
        "plans",
        {
            "id": "dddddddd-0000-0000-0000-000000000001",
            "user_id": user,
            "period_type": "year",
            "period_start": date(2026, 1, 1),
            "title": "2026",
            "summary": "",
        },
    )
    alembic_runner.insert_into(
        "period_reviews",
        {
            "id": "eeeeeeee-0000-0000-0000-000000000001",
            "user_id": user,
            "plan_id": "dddddddd-0000-0000-0000-000000000001",
            "generated_at": datetime(2026, 11, 1),
            "planned_count": 0,
            "completed_count": 0,
            "carried_over": [],
            "items": [],
            "retrospective_note_id": "cccccccc-0000-0000-0000-000000000002",
        },
    )

    alembic_runner.migrate_up_to("0017")
    with alembic_engine.connect() as c:
        notes = {r[0] for r in c.exec_driver_sql("select remote_id from notes")}
        containers = {r[0] for r in c.exec_driver_sql("select remote_id from source_containers")}
        users = c.exec_driver_sql("select count(*) from users").scalar()
    assert notes == {"n2", "n3"}  # the unreferenced copy is gone; what tefteri points at stays
    assert containers == {"c1"}  # the containers of the note app are gone, those of tasks stay
    assert users == 1
    alembic_runner.migrate_down_one()  # nothing to undo: the copies were a cache
    with alembic_engine.connect() as c:
        assert c.exec_driver_sql("select count(*) from notes").scalar() == 2


_USER = {
    "username": "sam",
    "password_hash": None,
    "is_admin": False,
    "timezone": "UTC",
    "disabled": False,
    "created_at": datetime(2026, 11, 1),
}
