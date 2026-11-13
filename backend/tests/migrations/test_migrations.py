"""Migration tests: pytest-alembic's built-in checks plus per-revision data checks."""

from datetime import date, datetime
from pathlib import Path

import pytest
from pytest_alembic import MigrationContext
from pytest_alembic.tests import (
    test_model_definitions_match_ddl,
    test_single_head_revision,
    test_up_down_consistency,
    test_upgrade,
)
from sqlalchemy import Engine, inspect
from sqlalchemy.exc import IntegrityError

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


def test_0018_creates_the_project_label_tables(
    alembic_runner: MigrationContext, alembic_engine: Engine
) -> None:
    alembic_runner.migrate_up_to("0017")
    user = "11111111-1111-1111-1111-111111111111"
    connection = "aaaaaaaa-0000-0000-0000-000000000001"
    alembic_runner.insert_into("users", {"id": user} | _USER)
    alembic_runner.insert_into(
        "connections",
        {
            "id": connection,
            "user_id": user,
            "kind": "tasks",
            "provider": "x",
            "display_name": "T",
            "settings": {},
            "status": "ok",
            "created_at": datetime(2026, 11, 1),
        },
    )
    alembic_runner.migrate_up_to("0018")
    insp = inspect(alembic_engine)
    assert {"project_labels", "project_label_history"} <= set(insp.get_table_names())
    uniques = [set(u["column_names"]) for u in insp.get_unique_constraints("project_labels")]
    assert {"connection_id", "remote_id"} in uniques
    for table, column, target in (
        ("project_labels", "connection_id", "connections"),
        ("project_labels", "user_id", "users"),
        ("project_label_history", "project_id", "project_labels"),
    ):
        keys = [k for k in insp.get_foreign_keys(table) if k["constrained_columns"] == [column]]
        assert [k["referred_table"] for k in keys] == [target]
        assert keys[0]["options"].get("ondelete") == "CASCADE"
    columns = {c["name"]: c for c in insp.get_columns("project_labels")}
    assert columns["label"]["nullable"] and columns["orphaned_reason"]["nullable"]
    assert columns["parent_remote_id"]["nullable"]

    row = {
        "user_id": user,
        "connection_id": connection,
        "remote_id": "p1",
        "name": "Open source",
        "created_at": datetime(2026, 11, 1),
    }
    alembic_runner.insert_into(
        "project_labels", row | {"id": "dddddddd-0000-0000-0000-000000000001"}
    )
    with pytest.raises(IntegrityError):
        alembic_runner.insert_into(
            "project_labels", row | {"id": "dddddddd-0000-0000-0000-000000000002"}
        )

    alembic_runner.migrate_down_one()
    tables = set(inspect(alembic_engine).get_table_names())
    assert not {"project_labels", "project_label_history"} & tables
    with alembic_engine.connect() as conn:
        assert conn.exec_driver_sql("select count(*) from connections").scalar() == 1


def test_0019_adds_the_milestone_tables_and_keeps_the_old_weekly_rows(
    alembic_runner: MigrationContext, alembic_engine: Engine
) -> None:
    alembic_runner.migrate_up_to("0018")
    user = "11111111-1111-1111-1111-111111111111"
    alembic_runner.insert_into("users", {"id": user} | _USER)
    plan = "22222222-0000-0000-0000-000000000001"
    alembic_runner.insert_into(
        "weekly_plans",
        {
            "id": plan,
            "user_id": user,
            "week_start": date(2026, 11, 2),
            "status": "committed",
            "retro_skipped": False,
            "reflection": "Kept it small.",
            "reviewed_at": datetime(2026, 11, 9),
        },
    )
    old = {
        "plan_id": plan,
        "committed_task_ids": ["t1"],
        "parked_task_ids": [],
        "position": 0,
        "created_here": False,
        "reviewed_committed": 2,
        "reviewed_done": 1,
    }
    rows = [
        old
        | {
            "id": "33333333-0000-0000-0000-000000000001",
            "name": "A",
            "outcome": "not_done",
            "leftover_action": "carry",
        },
        old
        | {
            "id": "33333333-0000-0000-0000-000000000002",
            "name": "B",
            "outcome": "done",
            "leftover_action": "backlog",
        },
        old
        | {
            "id": "33333333-0000-0000-0000-000000000003",
            "name": "C",
            "outcome": "done",
            "leftover_action": None,
        },
    ]
    for row in rows:
        alembic_runner.insert_into("weekly_plan_projects", row)
    columns = (
        "id, plan_id, container_id, name, position, created_here, committed_task_ids, "
        "parked_task_ids, outcome, leftover_action, reviewed_committed, reviewed_done"
    )
    with alembic_engine.connect() as conn:
        before = conn.exec_driver_sql(
            f"select {columns} from weekly_plan_projects order by name"
        ).fetchall()

    alembic_runner.migrate_up_to("0019")
    insp = inspect(alembic_engine)
    assert {"milestones", "milestone_rollovers", "milestone_closures"} <= set(
        insp.get_table_names()
    )
    new_columns = {c["name"]: c for c in insp.get_columns("weekly_plan_projects")}
    for name in (
        "milestone_id",
        "theme_project_id",
        "theme_name",
        "decision",
        "expected_rollover",
        "decided_at",
    ):
        assert new_columns[name]["nullable"], name
        assert new_columns[name]["default"] is None, name
    uniques = [set(u["column_names"]) for u in insp.get_unique_constraints("milestones")]
    assert {"project_id"} in uniques
    plan_uniques = [
        set(u["column_names"]) for u in insp.get_unique_constraints("weekly_plan_projects")
    ]
    assert {"plan_id", "milestone_id"} in plan_uniques
    assert {"plan_id", "container_id"} in plan_uniques
    milestone_columns = {c["name"]: c for c in insp.get_columns("milestones")}
    assert milestone_columns["done_state"]["nullable"] and milestone_columns["done_on"]["nullable"]
    assert not milestone_columns["state"]["nullable"]
    assert not {c["name"]: c for c in insp.get_columns("milestone_rollovers")}["expected"][
        "nullable"
    ]

    with alembic_engine.connect() as conn:
        after = conn.exec_driver_sql(
            f"select {columns} from weekly_plan_projects order by name"
        ).fetchall()
        fresh = conn.exec_driver_sql(
            "select milestone_id, theme_project_id, theme_name, decision, expected_rollover, "
            "decided_at from weekly_plan_projects"
        ).fetchall()
    assert after == before  # no old column of an old row changed
    assert fresh == [(None,) * 6] * 3  # and the new ones are empty: no backfill

    alembic_runner.migrate_down_one()
    insp = inspect(alembic_engine)
    assert not {"milestones", "milestone_rollovers", "milestone_closures"} & set(
        insp.get_table_names()
    )
    assert "decision" not in {c["name"] for c in insp.get_columns("weekly_plan_projects")}
    with alembic_engine.connect() as conn:
        assert (
            conn.exec_driver_sql(
                f"select {columns} from weekly_plan_projects order by name"
            ).fetchall()
            == before
        )


_USER = {
    "username": "sam",
    "password_hash": None,
    "is_admin": False,
    "timezone": "UTC",
    "disabled": False,
    "created_at": datetime(2026, 11, 1),
}


_U1 = "11111111-1111-1111-1111-111111111111"
_CONN = "aaaaaaaa-0000-0000-0000-000000000001"
_TASK = "bbbbbbbb-0000-0000-0000-000000000001"
_LABEL = "cccccccc-0000-0000-0000-000000000001"


def _seed_0019(alembic_runner: MigrationContext) -> None:
    """A user, a task connection, a project and one done task, as 0019 leaves them."""
    alembic_runner.insert_into("users", {"id": _U1} | _USER)
    alembic_runner.insert_into(
        "connections",
        {
            "id": _CONN,
            "user_id": _U1,
            "kind": "tasks",
            "provider": "x",
            "display_name": "T",
            "settings": {},
            "status": "ok",
            "created_at": datetime(2026, 11, 1),
        },
    )
    alembic_runner.insert_into(
        "project_labels",
        {
            "id": _LABEL,
            "user_id": _U1,
            "connection_id": _CONN,
            "remote_id": "p1",
            "name": "Home",
            "created_at": datetime(2026, 11, 1),
        },
    )
    alembic_runner.insert_into(
        "tasks",
        {
            "id": _TASK,
            "user_id": _U1,
            "connection_id": _CONN,
            "remote_id": "t1",
            "title": "Done long ago",
            "description": "",
            "status": "done",
            "completed_at": datetime(2026, 10, 1, 9),
            "all_day": False,
            "labels": [],
            "remote_version": "v1",
            "sync_state": "synced",
        },
    )


def _category(**over: object) -> dict[str, object]:
    return {
        "id": "dddddddd-0000-0000-0000-000000000001",
        "user_id": _U1,
        "task_id": _TASK,
        "completed_at": datetime(2026, 10, 1, 9),
        "completed_on": date(2026, 10, 1),
        "category": "off_plan",
        "reason": "theme",
        "unsorted": False,
        "project_id": _LABEL,
        "project_name": "Home",
        "project_label": "theme",
        "plan_id": None,
        "decided_via": "sync",
        "decided_at": datetime(2026, 11, 1),
    } | over


def test_0021_creates_task_categories_and_adds_no_row_for_old_done_tasks(
    alembic_runner: MigrationContext, alembic_engine: Engine
) -> None:
    alembic_runner.migrate_up_to("0019")
    _seed_0019(alembic_runner)
    alembic_runner.migrate_up_to("0021")
    insp = inspect(alembic_engine)
    assert "task_categories" in insp.get_table_names()
    uniques = [set(u["column_names"]) for u in insp.get_unique_constraints("task_categories")]
    assert {"task_id"} in uniques
    indexes = {i["name"]: i["column_names"] for i in insp.get_indexes("task_categories")}
    assert indexes["ix_task_categories_user_day_category"] == [
        "user_id",
        "completed_on",
        "category",
    ]
    assert indexes["ix_task_categories_user_category_completed"] == [
        "user_id",
        "category",
        "completed_at",
    ]
    assert indexes["ix_task_categories_project_id"] == ["project_id"]
    with alembic_engine.connect() as conn:
        assert conn.exec_driver_sql("select count(*) from task_categories").scalar() == 0
        assert conn.exec_driver_sql("select count(*) from tasks").scalar() == 1  # untouched
    ondelete = {
        k["constrained_columns"][0]: k["options"].get("ondelete")
        for k in insp.get_foreign_keys("task_categories")
    }
    assert ondelete == {
        "user_id": "CASCADE",
        "task_id": "CASCADE",
        "project_id": "SET NULL",
        "plan_id": "SET NULL",
    }
    alembic_runner.migrate_down_one()
    assert "task_categories" not in inspect(alembic_engine).get_table_names()
    with alembic_engine.connect() as conn:
        assert conn.exec_driver_sql("select count(*) from tasks").scalar() == 1


def test_0021_refuses_a_duplicate_task_and_a_category_that_is_not_known(
    alembic_runner: MigrationContext,
) -> None:
    alembic_runner.migrate_up_to("0019")
    _seed_0019(alembic_runner)
    alembic_runner.migrate_up_to("0021")
    alembic_runner.insert_into("task_categories", _category())
    with pytest.raises(IntegrityError):
        alembic_runner.insert_into(
            "task_categories", _category(id="dddddddd-0000-0000-0000-000000000002")
        )
    with pytest.raises(IntegrityError):
        alembic_runner.insert_into(
            "task_categories",
            _category(
                id="dddddddd-0000-0000-0000-000000000003",
                task_id="bbbbbbbb-0000-0000-0000-000000000002",
                category="other",
            ),
        )


def test_0021_deletes_cascade_and_a_deleted_project_label_sets_project_null(
    alembic_runner: MigrationContext, alembic_engine: Engine
) -> None:
    alembic_runner.migrate_up_to("0019")
    _seed_0019(alembic_runner)
    alembic_runner.migrate_up_to("0021")
    alembic_runner.insert_into("task_categories", _category())
    with alembic_engine.connect() as conn:
        conn.exec_driver_sql("PRAGMA foreign_keys=ON")
        conn.exec_driver_sql("delete from project_labels")
        conn.commit()
        assert conn.exec_driver_sql("select project_id from task_categories").scalar() is None
        conn.exec_driver_sql("delete from tasks")
        conn.commit()
        assert conn.exec_driver_sql("select count(*) from task_categories").scalar() == 0
    alembic_runner.insert_into(
        "tasks",
        {
            "id": _TASK,
            "user_id": _U1,
            "connection_id": _CONN,
            "remote_id": "t1",
            "title": "Again",
            "description": "",
            "status": "done",
            "all_day": False,
            "labels": [],
            "remote_version": "v1",
            "sync_state": "synced",
        },
    )
    alembic_runner.insert_into("task_categories", _category(project_id=None))
    with alembic_engine.connect() as conn:
        conn.exec_driver_sql("PRAGMA foreign_keys=ON")
        conn.exec_driver_sql("delete from users")
        conn.commit()
        assert conn.exec_driver_sql("select count(*) from task_categories").scalar() == 0


def test_0020_adds_the_annual_planning_tables(
    alembic_runner: MigrationContext, alembic_engine: Engine
) -> None:
    alembic_runner.migrate_up_to("0020")
    insp = inspect(alembic_engine)
    assert {
        "key_results",
        "key_result_values",
        "key_result_themes",
        "plan_changes",
        "value_push_tokens",
    } <= set(insp.get_table_names())
    goals_columns = {c["name"]: c for c in insp.get_columns("goals")}
    for name in ("updated_at", "retired_at", "retired_reason", "position"):
        assert name in goals_columns, name
    assert not goals_columns["updated_at"]["nullable"]
    assert goals_columns["retired_at"]["nullable"] and goals_columns["retired_reason"]["nullable"]
    indexes = {i["name"]: i["column_names"] for i in insp.get_indexes("goals")}
    assert indexes["ix_goals_user_period"] == ["user_id", "period_type", "period_start"]

    uniques = [set(u["column_names"]) for u in insp.get_unique_constraints("key_results")]
    assert {"goal_id", "slot"} in uniques
    checks = {c["name"] for c in insp.get_check_constraints("key_results")}
    # The behaviour of the checks is proven in
    # test_0020_refuses_two_active_key_results_in_one_slot.
    assert {"ck_key_results_target", "ck_key_results_slot_state", "ck_key_results_slot"} <= checks
    seq_uniques = [set(u["column_names"]) for u in insp.get_unique_constraints("key_result_values")]
    assert {"key_result_id", "seq"} in seq_uniques
    active_links = {i["name"]: i for i in insp.get_indexes("key_result_themes")}
    assert active_links["uq_key_result_themes_active"]["unique"]
    assert active_links["uq_key_result_themes_active"]["column_names"] == [
        "key_result_id",
        "project_id",
    ]
    token_uniques = [
        set(u["column_names"]) for u in insp.get_unique_constraints("value_push_tokens")
    ]
    assert {"user_id"} in token_uniques and {"token_hash"} in token_uniques

    cascades = {
        (table, k["constrained_columns"][0]): k["options"].get("ondelete")
        for table in (
            "key_results",
            "key_result_values",
            "key_result_themes",
            "plan_changes",
            "value_push_tokens",
        )
        for k in insp.get_foreign_keys(table)
    }
    for table in (
        "key_results",
        "key_result_values",
        "key_result_themes",
        "plan_changes",
        "value_push_tokens",
    ):
        assert cascades[(table, "user_id")] == "CASCADE", table
    assert cascades[("key_results", "goal_id")] == "CASCADE"
    assert cascades[("key_result_values", "key_result_id")] == "CASCADE"
    assert cascades[("key_result_themes", "key_result_id")] == "CASCADE"
    assert cascades[("key_result_themes", "project_id")] == "CASCADE"
    assert cascades[("plan_changes", "goal_id")] == "CASCADE"
    assert cascades[("plan_changes", "key_result_id")] == "CASCADE"
    assert cascades[("plan_changes", "link_id")] == "SET NULL"


def test_0020_refuses_two_active_key_results_in_one_slot(
    alembic_runner: MigrationContext,
) -> None:
    alembic_runner.migrate_up_to("0020")
    user = "11111111-1111-1111-1111-111111111111"
    alembic_runner.insert_into("users", {"id": user} | _USER)
    goal = "eeeeeeee-0000-0000-0000-000000000001"
    alembic_runner.insert_into(
        "goals",
        {
            "id": goal,
            "user_id": user,
            "period_type": "year",
            "period_start": date(2027, 1, 1),
            "title": "Get better at open source",
            "description": "",
            "criteria": "",
            "status": "active",
        },
    )
    key_result = {
        "id": "ffffffff-0000-0000-0000-000000000001",
        "user_id": user,
        "goal_id": goal,
        "year": 2027,
        "metric": "Stars on one repository",
        "start_value": 120,
        "target": 500,
        "deadline": date(2027, 12, 31),
        "update_source": "manual",
        "status": "active",
        "slot": 1,
        "position": 0,
        "created_at": datetime(2026, 11, 1),
        "updated_at": datetime(2026, 11, 1),
    }
    alembic_runner.insert_into("key_results", key_result)
    with pytest.raises(IntegrityError):
        alembic_runner.insert_into(
            "key_results", key_result | {"id": "ffffffff-0000-0000-0000-000000000002"}
        )
    # A retired key result has no slot and frees its place.
    alembic_runner.insert_into(
        "key_results",
        key_result
        | {"id": "ffffffff-0000-0000-0000-000000000004", "status": "retired", "slot": None},
    )
    # The target must differ from the start value.
    with pytest.raises(IntegrityError):
        alembic_runner.insert_into(
            "key_results",
            key_result | {"id": "ffffffff-0000-0000-0000-000000000003", "target": 120},
        )
    # An active key result without a slot breaks the pair rule.
    with pytest.raises(IntegrityError):
        alembic_runner.insert_into(
            "key_results",
            key_result | {"id": "ffffffff-0000-0000-0000-000000000005", "slot": None},
        )


_MONTHLY_TABLES = {
    "monthly_focuses",
    "monthly_focus_entries",
    "focus_changes",
    "monthly_reviews",
    "monthly_review_snapshots",
}


def _monthly_focus_rows(alembic_runner: MigrationContext) -> None:
    """Insert a valid saved focus and entries to exercise constraints and cascades."""
    focus = "eeeeeeee-0000-0000-0000-000000000011"
    alembic_runner.insert_into(
        "monthly_focuses",
        {
            "id": focus,
            "user_id": _U1,
            "month": date(2030, 3, 1),
            "created_at": datetime(2030, 2, 1),
            "updated_at": datetime(2030, 2, 1),
        },
    )
    alembic_runner.insert_into(
        "monthly_focus_entries",
        {
            "id": "eeeeeeee-0000-0000-0000-000000000012",
            "focus_id": focus,
            "project_id": _LABEL,
            "name": "Home",
            "target": 0,
            "counts_from": date(2030, 3, 1),
            "position": 0,
            "created_at": datetime(2030, 2, 1),
        },
    )
    alembic_runner.insert_into(
        "monthly_reviews",
        {
            "id": "eeeeeeee-0000-0000-0000-000000000013",
            "user_id": _U1,
            "month": date(2030, 3, 1),
            "current_version": 1,
            "current_changed_at": datetime(2030, 4, 1),
            "created_at": datetime(2030, 4, 1),
        },
    )
    alembic_runner.insert_into(
        "monthly_review_snapshots",
        {
            "id": "eeeeeeee-0000-0000-0000-000000000014",
            "review_id": "eeeeeeee-0000-0000-0000-000000000013",
            "version": 1,
            "schema_version": 1,
            "payload": {},
            "values_written": [],
            "created_at": datetime(2030, 4, 1),
        },
    )
    alembic_runner.insert_into(
        "focus_changes",
        {
            "id": "eeeeeeee-0000-0000-0000-000000000020",
            "focus_id": focus,
            "kind": "add",
            "changed_on": date(2030, 3, 10),
            "batch_id": "eeeeeeee-0000-0000-0000-000000000021",
            "source": "user",
            "created_at": datetime(2030, 3, 10),
        },
    )


def test_0022_creates_only_monthly_tables_with_constraints_and_user_cascade(
    alembic_runner: MigrationContext, alembic_engine: Engine
) -> None:
    alembic_runner.migrate_up_to("0019")
    _seed_0019(alembic_runner)
    alembic_runner.migrate_up_to("0021")
    for n in (2, 3):
        alembic_runner.insert_into(
            "project_labels",
            {
                "id": f"cccccccc-0000-0000-0000-00000000000{n}",
                "user_id": _U1,
                "connection_id": _CONN,
                "remote_id": f"p{n}",
                "name": f"Theme {n}",
                "created_at": datetime(2030, 2, 1),
            },
        )
    before = set(inspect(alembic_engine).get_table_names())
    alembic_runner.migrate_up_to("0022")
    insp = inspect(alembic_engine)
    assert set(insp.get_table_names()) >= _MONTHLY_TABLES
    assert set(insp.get_table_names()) - before == _MONTHLY_TABLES

    for table in ("monthly_focuses", "monthly_reviews"):
        uniques = [set(u["column_names"]) for u in insp.get_unique_constraints(table)]
        assert {"user_id", "month"} in uniques
    entry_uniques = [
        set(u["column_names"]) for u in insp.get_unique_constraints("monthly_focus_entries")
    ]
    assert {"focus_id", "project_id"} in entry_uniques
    snapshot_uniques = [
        set(u["column_names"]) for u in insp.get_unique_constraints("monthly_review_snapshots")
    ]
    assert {"review_id", "version"} in snapshot_uniques
    user_cascades = [
        key
        for table in ("monthly_focuses", "monthly_reviews")
        for key in insp.get_foreign_keys(table)
        if key["constrained_columns"] == ["user_id"]
    ]
    assert len(user_cascades) == 2
    assert all(key["options"].get("ondelete") == "CASCADE" for key in user_cascades)

    _monthly_focus_rows(alembic_runner)
    with pytest.raises(IntegrityError):
        alembic_runner.insert_into(
            "monthly_focuses",
            {
                "id": "eeeeeeee-0000-0000-0000-000000000022",
                "user_id": _U1,
                "month": date(2030, 3, 1),
                "created_at": datetime(2030, 2, 1),
                "updated_at": datetime(2030, 2, 1),
            },
        )
    with pytest.raises(IntegrityError):
        alembic_runner.insert_into(
            "monthly_reviews",
            {
                "id": "eeeeeeee-0000-0000-0000-000000000023",
                "user_id": _U1,
                "month": date(2030, 3, 1),
                "current_version": 1,
                "current_changed_at": datetime(2030, 4, 1),
                "created_at": datetime(2030, 4, 1),
            },
        )
    invalid_entry = {
        "id": "eeeeeeee-0000-0000-0000-000000000015",
        "focus_id": "eeeeeeee-0000-0000-0000-000000000011",
        "project_id": _LABEL,
        "name": "Duplicate",
        "counts_from": date(2030, 3, 1),
        "position": 1,
        "created_at": datetime(2030, 2, 1),
    }
    with pytest.raises(IntegrityError):
        alembic_runner.insert_into("monthly_focus_entries", invalid_entry | {"target": -1})
    with pytest.raises(IntegrityError):
        alembic_runner.insert_into("monthly_focus_entries", invalid_entry | {"target": None})
    for n, target, project_number in ((16, None, 2), (17, 0, 3)):
        alembic_runner.insert_into(
            "monthly_focus_entries",
            invalid_entry
            | {
                "id": f"eeeeeeee-0000-0000-0000-0000000000{n}",
                "project_id": f"cccccccc-0000-0000-0000-00000000000{project_number}",
                "target": target,
            },
        )
    with pytest.raises(IntegrityError):
        alembic_runner.insert_into(
            "monthly_focus_entries",
            invalid_entry
            | {
                "id": "eeeeeeee-0000-0000-0000-000000000018",
                "project_id": "cccccccc-0000-0000-0000-000000000003",
                "left_on": date(2030, 3, 20),
                "left_reason": None,
            },
        )
    with pytest.raises(IntegrityError):
        alembic_runner.insert_into(
            "monthly_review_snapshots",
            {
                "id": "eeeeeeee-0000-0000-0000-000000000019",
                "review_id": "eeeeeeee-0000-0000-0000-000000000013",
                "version": 1,
                "schema_version": 1,
                "payload": {},
                "values_written": [],
                "created_at": datetime(2030, 4, 1),
            },
        )

    with alembic_engine.connect() as conn:
        conn.exec_driver_sql("PRAGMA foreign_keys=ON")
        conn.exec_driver_sql(f"delete from users where id = '{_U1}'")
        conn.commit()
        for table in _MONTHLY_TABLES:
            assert conn.exec_driver_sql(f"select count(*) from {table}").scalar() == 0


def test_0022_preserves_existing_month_data_and_downgrade_drops_only_new_tables(
    alembic_runner: MigrationContext, alembic_engine: Engine
) -> None:
    alembic_runner.migrate_up_to("0019")
    _seed_0019(alembic_runner)
    alembic_runner.migrate_up_to("0021")
    month_goal = "eeeeeeee-0000-0000-0000-000000000024"
    plan_id = "eeeeeeee-0000-0000-0000-000000000025"
    review_id = "eeeeeeee-0000-0000-0000-000000000026"
    alembic_runner.insert_into(
        "goals",
        _goal(
            month_goal,
            period_type="month",
            period_start=date(2030, 3, 1),
            title="Old monthly goal",
        ),
    )
    alembic_runner.insert_into(
        "plans",
        {
            "id": plan_id,
            "user_id": _U1,
            "period_type": "month",
            "period_start": date(2030, 3, 1),
            "title": "March",
            "summary": "",
        },
    )
    alembic_runner.insert_into(
        "period_reviews",
        {
            "id": review_id,
            "user_id": _U1,
            "plan_id": plan_id,
            "generated_at": datetime(2030, 4, 1),
            "planned_count": 1,
            "completed_count": 1,
            "carried_over": [{"name": "A"}],
            "items": [{"name": "B"}],
        },
    )
    with alembic_engine.connect() as conn:
        conn.exec_driver_sql(
            "update users set checklists = ? where id = ?",
            ('{"month":"kept"}', _U1),
        )
        conn.commit()
    before_tables = set(inspect(alembic_engine).get_table_names())
    with alembic_engine.connect() as conn:
        before = {
            "goal": conn.exec_driver_sql(
                "select id, period_start, title from goals where id = ?", (month_goal,)
            ).fetchone(),
            "review": conn.exec_driver_sql(
                "select id, plan_id, items from period_reviews where id = ?", (review_id,)
            ).fetchone(),
            "checklists": conn.exec_driver_sql(
                "select checklists from users where id = ?", (_U1,)
            ).scalar(),
        }

    alembic_runner.migrate_up_to("0022")
    with alembic_engine.connect() as conn:
        assert (
            conn.exec_driver_sql(
                "select id, period_start, title from goals where id = ?", (month_goal,)
            ).fetchone()
            == before["goal"]
        )
        assert (
            conn.exec_driver_sql(
                "select id, plan_id, items from period_reviews where id = ?", (review_id,)
            ).fetchone()
            == before["review"]
        )
        assert (
            conn.exec_driver_sql("select checklists from users where id = ?", (_U1,)).scalar()
            == before["checklists"]
        )
    alembic_runner.migrate_down_one()
    assert set(inspect(alembic_engine).get_table_names()) == before_tables
    with alembic_engine.connect() as conn:
        assert (
            conn.exec_driver_sql(
                "select id, period_start, title from goals where id = ?", (month_goal,)
            ).fetchone()
            == before["goal"]
        )
        assert (
            conn.exec_driver_sql(
                "select id, plan_id, items from period_reviews where id = ?", (review_id,)
            ).fetchone()
            == before["review"]
        )


_OLD_GOAL_COLUMNS = (
    "id, user_id, parent_id, period_type, period_start, title, description, criteria, status"
)


def _goal(goal_id: str, **over: object) -> dict[str, object]:
    return {
        "id": goal_id,
        "user_id": _U1,
        "parent_id": None,
        "period_type": "year",
        "period_start": date(2026, 1, 1),
        "title": f"Goal {goal_id[-1]}",
        "description": "",
        "criteria": "",
        "status": "active",
    } | over


def _seed_0020(alembic_runner: MigrationContext) -> None:
    """Year, month and week goals, linked tasks, a plan and a stored review, as 0019 leaves them."""
    alembic_runner.insert_into("users", {"id": _U1} | _USER)
    year_active = "eeeeeeee-0000-0000-0000-000000000001"
    year_dropped = "eeeeeeee-0000-0000-0000-000000000002"
    year_done = "eeeeeeee-0000-0000-0000-000000000003"
    month_goal = "eeeeeeee-0000-0000-0000-000000000004"
    week_goal = "eeeeeeee-0000-0000-0000-000000000005"
    alembic_runner.insert_into(
        "goals", _goal(year_active, title="Open source", criteria="Two talks and 100 stars")
    )
    alembic_runner.insert_into(
        "goals", _goal(year_dropped, title="Give up running", status="dropped")
    )
    alembic_runner.insert_into("goals", _goal(year_done, title="Read books", status="done"))
    alembic_runner.insert_into(
        "goals",
        _goal(
            month_goal,
            period_type="month",
            period_start=date(2026, 3, 1),
            title="Run 25 km",
            parent_id=year_active,
        ),
    )
    alembic_runner.insert_into(
        "goals",
        _goal(
            week_goal,
            period_type="week",
            period_start=date(2026, 3, 2),
            title="Run twice",
            parent_id=month_goal,
        ),
    )
    for n, goal in ((1, year_active), (2, month_goal)):
        alembic_runner.insert_into(
            "tasks",
            {
                "id": f"{_TASK[:-1]}{n}",
                "user_id": _U1,
                "connection_id": _CONN,
                "remote_id": f"t{n}",
                "title": f"Task {n}",
                "description": "",
                "status": "open",
                "all_day": False,
                "labels": [],
                "remote_version": "v1",
                "sync_state": "synced",
                "goal_id": goal,
            },
        )
    plan = "22222222-0000-0000-0000-000000000009"
    alembic_runner.insert_into(
        "plans",
        {
            "id": plan,
            "user_id": _U1,
            "period_type": "month",
            "period_start": date(2026, 3, 1),
            "title": "March",
            "summary": "",
        },
    )
    alembic_runner.insert_into(
        "period_reviews",
        {
            "id": "eeeeeeee-0000-0000-0000-000000000009",
            "user_id": _U1,
            "plan_id": plan,
            "generated_at": datetime(2026, 4, 1),
            "planned_count": 1,
            "completed_count": 0,
            "carried_over": [],
            "items": [],
        },
    )


def test_0020_keeps_every_existing_goal_and_review(
    alembic_runner: MigrationContext, alembic_engine: Engine
) -> None:
    alembic_runner.migrate_up_to("0019")
    _seed_0020(alembic_runner)
    with alembic_engine.connect() as conn:
        conn.exec_driver_sql("PRAGMA foreign_keys=ON")
        goals_before = conn.exec_driver_sql(
            f"select {_OLD_GOAL_COLUMNS} from goals order by id"
        ).fetchall()
        month_week_before = conn.exec_driver_sql(
            f"select {_OLD_GOAL_COLUMNS} from goals where period_type in ('month', 'week') "
            "order by id"
        ).fetchall()
        links_before = conn.exec_driver_sql(
            "select id, goal_id from tasks where goal_id is not null order by id"
        ).fetchall()
        reviews_before = conn.exec_driver_sql(
            "select id, plan_id, planned_count, completed_count, carried_over, items "
            "from period_reviews order by id"
        ).fetchall()

    alembic_runner.migrate_up_to("0020")

    with alembic_engine.connect() as conn:
        conn.exec_driver_sql("PRAGMA foreign_keys=ON")
        assert conn.exec_driver_sql("select count(*) from goals").scalar() == 5
        assert conn.exec_driver_sql("select count(*) from key_results").scalar() == 0
        goals_after = conn.exec_driver_sql(
            f"select {_OLD_GOAL_COLUMNS} from goals order by id"
        ).fetchall()
        month_week_after = conn.exec_driver_sql(
            f"select {_OLD_GOAL_COLUMNS} from goals where period_type in ('month', 'week') "
            "order by id"
        ).fetchall()
        links_after = conn.exec_driver_sql(
            "select id, goal_id from tasks where goal_id is not null order by id"
        ).fetchall()
        reviews_after = conn.exec_driver_sql(
            "select id, plan_id, planned_count, completed_count, carried_over, items "
            "from period_reviews order by id"
        ).fetchall()
    # The ids, titles, criteria, parents and task links are all kept ...
    assert links_after == links_before
    assert reviews_after == reviews_before
    # ... the month and week rows are byte-equal ...
    assert month_week_after == month_week_before
    # ... the year rows keep everything but the dropped status.
    assert goals_after == [
        row if row[8] != "dropped" else row[:8] + ("retired",) for row in goals_before
    ]
    with alembic_engine.connect() as conn:
        retired = conn.exec_driver_sql(
            "select status, retired_at, retired_reason from goals where period_type = 'year' "
            "order by id"
        ).fetchall()
    assert retired == [
        ("active", None, None),
        ("retired", retired[1][1], "Dropped before annual planning"),
        ("done", None, None),
    ]
    assert retired[1][1] is not None  # retired_at is set
    # One migrated history row per changed or criteria-bearing year goal.
    with alembic_engine.connect() as conn:
        changes = conn.exec_driver_sql(
            "select goal_id, kind, source, old_value, new_value from plan_changes order by goal_id"
        ).fetchall()
    year_active = "eeeeeeee-0000-0000-0000-000000000001"
    year_dropped = "eeeeeeee-0000-0000-0000-000000000002"
    assert changes == [
        (year_active, "migrated", "migration", "active", "active"),
        (year_dropped, "migrated", "migration", "dropped", "retired"),
    ]


def test_0020_downgrade_restores_the_old_schema(
    alembic_runner: MigrationContext, alembic_engine: Engine
) -> None:
    alembic_runner.migrate_up_to("0019")
    _seed_0020(alembic_runner)
    alembic_runner.migrate_up_to("0020")
    alembic_runner.migrate_down_one()
    insp = inspect(alembic_engine)
    assert not {
        "key_results",
        "key_result_values",
        "key_result_themes",
        "plan_changes",
        "value_push_tokens",
    } & set(insp.get_table_names())
    columns = {c["name"] for c in insp.get_columns("goals")}
    assert not {"updated_at", "retired_at", "retired_reason", "position"} & columns
    with alembic_engine.connect() as conn:
        conn.exec_driver_sql("PRAGMA foreign_keys=ON")
        statuses = conn.exec_driver_sql(
            "select id, status from goals where period_type = 'year' order by id"
        ).fetchall()
        links = conn.exec_driver_sql(
            "select count(*) from tasks where goal_id is not null"
        ).scalar()
    assert statuses == [
        ("eeeeeeee-0000-0000-0000-000000000001", "active"),
        ("eeeeeeee-0000-0000-0000-000000000002", "dropped"),
        ("eeeeeeee-0000-0000-0000-000000000003", "done"),
    ]
    assert links == 2  # the goals and the task links are kept


def test_0024_drops_the_legacy_plan_and_review_tables(
    alembic_runner: MigrationContext, alembic_engine: Engine
) -> None:
    alembic_runner.migrate_up_to("0023")
    alembic_runner.insert_into("users", {"id": _U1} | _USER)
    alembic_runner.insert_into(
        "goals",
        {
            "id": "eeeeeeee-0000-0000-0000-000000000030",
            "user_id": _U1,
            "parent_id": None,
            "period_type": "year",
            "period_start": date(2026, 1, 1),
            "title": "Kept goal",
            "description": "",
            "criteria": "",
            "status": "active",
            "updated_at": datetime(2026, 1, 1),
            "retired_at": None,
            "retired_reason": None,
            "position": 0,
        },
    )
    plan = "eeeeeeee-0000-0000-0000-000000000031"
    alembic_runner.insert_into(
        "plans",
        {
            "id": plan,
            "user_id": _U1,
            "period_type": "month",
            "period_start": date(2026, 3, 1),
            "title": "Old plan",
            "summary": "",
        },
    )
    alembic_runner.insert_into(
        "period_reviews",
        {
            "id": "eeeeeeee-0000-0000-0000-000000000032",
            "user_id": _U1,
            "plan_id": plan,
            "generated_at": datetime(2026, 4, 1),
            "planned_count": 1,
            "completed_count": 0,
            "carried_over": [],
            "items": [],
        },
    )

    alembic_runner.migrate_up_to("0024")
    insp = inspect(alembic_engine)
    assert "plans" not in insp.get_table_names()
    assert "period_reviews" not in insp.get_table_names()
    with alembic_engine.connect() as conn:
        assert conn.exec_driver_sql("select count(*) from goals").scalar() == 1

    alembic_runner.migrate_down_one()
    insp = inspect(alembic_engine)
    assert {"plans", "period_reviews"} <= set(insp.get_table_names())
    with alembic_engine.connect() as conn:
        assert conn.exec_driver_sql("select count(*) from plans").scalar() == 0
        assert conn.exec_driver_sql("select count(*) from period_reviews").scalar() == 0


def test_0025_adds_the_key_result_kind_and_keeps_rows(
    alembic_runner: MigrationContext, alembic_engine: Engine
) -> None:
    alembic_runner.migrate_up_to("0024")
    alembic_runner.insert_into("users", {"id": _U1} | _USER)
    goal = "eeeeeeee-0000-0000-0000-000000000040"
    alembic_runner.insert_into(
        "goals",
        {
            "id": goal,
            "user_id": _U1,
            "parent_id": None,
            "period_type": "year",
            "period_start": date(2026, 1, 1),
            "title": "Goal",
            "description": "",
            "criteria": "",
            "status": "active",
            "updated_at": datetime(2026, 1, 1),
            "retired_at": None,
            "retired_reason": None,
            "position": 0,
        },
    )
    result = "ffffffff-0000-0000-0000-000000000040"
    alembic_runner.insert_into(
        "key_results",
        {
            "id": result,
            "user_id": _U1,
            "goal_id": goal,
            "year": 2026,
            "metric": "Existing",
            "start_value": 0,
            "target": 10,
            "deadline": date(2026, 12, 31),
            "update_source": "manual",
            "status": "active",
            "slot": 1,
            "position": 0,
            "created_at": datetime(2026, 1, 1),
            "updated_at": datetime(2026, 1, 1),
        },
    )

    alembic_runner.migrate_up_to("0025")
    columns = {c["name"] for c in inspect(alembic_engine).get_columns("key_results")}
    assert "kind" in columns
    checks = {c["name"] for c in inspect(alembic_engine).get_check_constraints("key_results")}
    assert "ck_key_results_kind" in checks
    with alembic_engine.connect() as conn:
        assert (
            conn.exec_driver_sql(f"select kind from key_results where id = '{result}'").scalar()
            == "number"
        )
        conn.exec_driver_sql(f"update key_results set kind = 'yes_no' where id = '{result}'")
        conn.commit()
        assert (
            conn.exec_driver_sql(f"select kind from key_results where id = '{result}'").scalar()
            == "yes_no"
        )
    with pytest.raises(IntegrityError), alembic_engine.connect() as conn:
        conn.exec_driver_sql(f"update key_results set kind = 'other' where id = '{result}'")
        conn.commit()

    alembic_runner.migrate_down_one()
    assert "kind" not in {c["name"] for c in inspect(alembic_engine).get_columns("key_results")}


def test_the_head_revision_follows_0024() -> None:
    from alembic.config import Config
    from alembic.script import ScriptDirectory

    config = Config()
    config.set_main_option("script_location", str(Path(__file__).parents[2] / "migrations"))
    script = ScriptDirectory.from_config(config)
    assert script.get_current_head() == "0025"
    revision = script.get_revision("0025")
    assert revision is not None
    assert revision.down_revision == "0024"
    assert script.get_revision("0024").down_revision == "0023"
    assert script.get_revision("0023").down_revision == "0022"
    assert script.get_revision("0022").down_revision == "0021"
    assert script.get_revision("0021").down_revision == "0020"
    # Feature 006 owns 0020, and 0020 follows 0019.
    assert script.get_revision("0020").down_revision == "0019"


def test_0023_creates_review_notes_with_scope_indexes(
    alembic_runner: MigrationContext, alembic_engine: Engine
) -> None:
    alembic_runner.migrate_up_to("0019")
    _seed_0019(alembic_runner)
    alembic_runner.migrate_up_to("0022")
    before = set(inspect(alembic_engine).get_table_names())
    alembic_runner.migrate_up_to("0023")
    insp = inspect(alembic_engine)
    assert set(insp.get_table_names()) - before == {"review_notes"}
    indexes = {i["name"]: i for i in insp.get_indexes("review_notes")}
    assert indexes["uq_review_notes_year"]["unique"] == 1
    assert indexes["uq_review_notes_year"]["column_names"] == ["user_id", "year"]
    assert indexes["uq_review_notes_goal"]["unique"] == 1
    assert indexes["uq_review_notes_goal"]["column_names"] == ["user_id", "goal_id"]
    ondelete = {
        key["constrained_columns"][0]: key["options"].get("ondelete")
        for key in insp.get_foreign_keys("review_notes")
    }
    assert ondelete == {"user_id": "CASCADE", "goal_id": "CASCADE"}

    goal = "eeeeeeee-0000-0000-0000-000000000023"
    alembic_runner.insert_into(
        "goals",
        {
            "id": goal,
            "user_id": _U1,
            "parent_id": None,
            "period_type": "year",
            "period_start": date(2025, 1, 1),
            "title": "A goal",
            "description": "",
            "criteria": "",
            "status": "active",
            "updated_at": datetime(2025, 1, 1),
            "retired_at": None,
            "retired_reason": None,
            "position": 0,
        },
    )
    note = {
        "user_id": _U1,
        "year": 2025,
        "body": "A year.",
        "created_at": datetime(2026, 1, 1),
        "updated_at": datetime(2026, 1, 1),
    }
    alembic_runner.insert_into(
        "review_notes", note | {"id": "eeeeeeee-0000-0000-0000-000000000024", "goal_id": None}
    )
    with pytest.raises(IntegrityError):
        alembic_runner.insert_into(
            "review_notes",
            note | {"id": "eeeeeeee-0000-0000-0000-000000000025", "goal_id": None},
        )
    alembic_runner.insert_into(
        "review_notes",
        note | {"id": "eeeeeeee-0000-0000-0000-000000000026", "goal_id": goal},
    )
    with pytest.raises(IntegrityError):
        alembic_runner.insert_into(
            "review_notes",
            note | {"id": "eeeeeeee-0000-0000-0000-000000000027", "goal_id": goal},
        )
    for n, body in ((28, ""), (29, "x" * 2001)):
        with pytest.raises(IntegrityError):
            alembic_runner.insert_into(
                "review_notes",
                note
                | {
                    "id": f"eeeeeeee-0000-0000-0000-0000000000{n}",
                    "goal_id": None,
                    "year": 2024,
                    "body": body,
                },
            )
    with alembic_engine.connect() as conn:
        conn.exec_driver_sql("PRAGMA foreign_keys=ON")
        conn.exec_driver_sql(f"delete from goals where id = '{goal}'")
        conn.commit()
        assert conn.exec_driver_sql("select count(*) from review_notes").scalar() == 1
        conn.exec_driver_sql(f"delete from users where id = '{_U1}'")
        conn.commit()
        assert conn.exec_driver_sql("select count(*) from review_notes").scalar() == 0
    alembic_runner.migrate_down_one()
    assert "review_notes" not in inspect(alembic_engine).get_table_names()


def test_the_head_revision_is_0025_and_it_follows_0024() -> None:
    from alembic.config import Config
    from alembic.script import ScriptDirectory

    config = Config()
    config.set_main_option("script_location", str(Path(__file__).parents[2] / "migrations"))
    script = ScriptDirectory.from_config(config)
    assert script.get_current_head() == "0025"
    revision = script.get_revision("0025")
    assert revision is not None
    assert revision.down_revision == "0024"
