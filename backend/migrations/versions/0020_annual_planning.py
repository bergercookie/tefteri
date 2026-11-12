"""annual planning: key results, value series, theme links, plan history and the push token

Revision ID: 0020
Revises: 0019

Keeps every existing goal, task link and stored period review (spec 006, SC-004):

1. Add ``updated_at``, ``retired_at``, ``retired_reason`` and ``position`` to ``goals`` and the
   index ``ix_goals_user_period``. ``updated_at`` gets the migration time for existing rows.
2. Create the five new tables.
3. Year goals: the row, the title, the description, the criteria text, the id and every
   ``tasks.goal_id`` link stay. Status ``active`` stays ``active``; ``dropped`` becomes
   ``retired`` (with ``retired_at`` and the reason "Dropped before annual planning"); ``done``
   stays ``done``. Month and week goals change not at all.
4. For each year goal whose status changed or that has a criteria text, write one
   ``plan_changes`` row with ``kind = 'migrated'`` and ``source = 'migration'``.
5. No key result is created.

Downgrade drops the five tables and the four columns and sets ``retired`` year goals back to
``dropped``. Key results, values, links and history are lost on downgrade.
"""

import uuid
from datetime import UTC, date, datetime

import sqlalchemy as sa
from alembic import op

revision = "0020"
down_revision = "0019"
branch_labels = None
depends_on = None


def upgrade() -> None:
    # SQLite supports native ADD COLUMN; ``recreate='never'`` keeps the batch from copying
    # the table (a copy would fire the self-cascade on the parent links, spec 006 SC-004).
    # CURRENT_TIMESTAMP is not a legal default for ADD COLUMN on SQLite, so the migration
    # time is baked in as a constant: every existing row gets it (plan.md, step 1).
    with op.batch_alter_table("goals", recreate="never") as batch:
        batch.add_column(
            sa.Column(
                "updated_at",
                sa.DateTime(timezone=True),
                nullable=False,
                server_default=sa.text(f"'{datetime.now(UTC).isoformat()}'"),
            )
        )
        batch.add_column(sa.Column("retired_at", sa.DateTime(timezone=True), nullable=True))
        batch.add_column(sa.Column("retired_reason", sa.Text(), nullable=True))
        batch.add_column(
            sa.Column("position", sa.Integer(), nullable=False, server_default=sa.text("0"))
        )
        batch.create_index("ix_goals_user_period", ["user_id", "period_type", "period_start"])

    op.create_table(
        "key_results",
        sa.Column("id", sa.Uuid(), primary_key=True),
        sa.Column(
            "user_id", sa.Uuid(), sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False
        ),
        sa.Column(
            "goal_id", sa.Uuid(), sa.ForeignKey("goals.id", ondelete="CASCADE"), nullable=False
        ),
        sa.Column("year", sa.Integer(), nullable=False),
        sa.Column("metric", sa.String(500), nullable=False),
        sa.Column("start_value", sa.Float(), nullable=False),
        sa.Column("target", sa.Float(), nullable=False),
        sa.Column("deadline", sa.Date(), nullable=False),
        sa.Column("update_source", sa.String(9), nullable=False),
        sa.Column("status", sa.String(8), nullable=False),
        sa.Column("slot", sa.SmallInteger(), nullable=True),
        sa.Column("position", sa.Integer(), nullable=False),
        sa.Column("retired_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("retired_reason", sa.Text(), nullable=True),
        sa.Column(
            "seeded_from_id",
            sa.Uuid(),
            sa.ForeignKey("key_results.id", ondelete="SET NULL"),
            nullable=True,
        ),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.UniqueConstraint("goal_id", "slot", name="uq_key_results_goal_slot"),
        sa.CheckConstraint("target <> start_value", name="ck_key_results_target"),
        sa.CheckConstraint("slot IS NULL OR slot BETWEEN 1 AND 3", name="ck_key_results_slot"),
        sa.CheckConstraint(
            "(status = 'active') = (slot IS NOT NULL)", name="ck_key_results_slot_state"
        ),
    )
    op.create_index("ix_key_results_user_id", "key_results", ["user_id"])
    op.create_index("ix_key_results_goal_id", "key_results", ["goal_id"])

    op.create_table(
        "key_result_values",
        sa.Column("id", sa.Uuid(), primary_key=True),
        sa.Column(
            "user_id", sa.Uuid(), sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False
        ),
        sa.Column(
            "key_result_id",
            sa.Uuid(),
            sa.ForeignKey("key_results.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("value", sa.Float(), nullable=False),
        sa.Column("at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("on_date", sa.Date(), nullable=False),
        sa.Column("source", sa.String(9), nullable=False),
        sa.Column("seq", sa.Integer(), nullable=False),
        sa.Column("entered_at", sa.DateTime(timezone=True), nullable=False),
        sa.UniqueConstraint("key_result_id", "seq", name="uq_key_result_values_key_result_seq"),
    )
    op.create_index("ix_key_result_values_user_id", "key_result_values", ["user_id"])
    op.create_index("ix_key_result_values_key_result_id", "key_result_values", ["key_result_id"])
    op.create_index(
        "ix_key_result_values_series", "key_result_values", ["key_result_id", "on_date", "seq"]
    )

    op.create_table(
        "key_result_themes",
        sa.Column("id", sa.Uuid(), primary_key=True),
        sa.Column(
            "user_id", sa.Uuid(), sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False
        ),
        sa.Column(
            "key_result_id",
            sa.Uuid(),
            sa.ForeignKey("key_results.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column(
            "project_id",
            sa.Uuid(),
            sa.ForeignKey("project_labels.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("year", sa.Integer(), nullable=False),
        sa.Column("started_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("ended_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("end_reason", sa.String(20), nullable=True),
        sa.Column("batch_id", sa.Uuid(), nullable=True),
        sa.Index(
            "uq_key_result_themes_active",
            "key_result_id",
            "project_id",
            unique=True,
            sqlite_where=sa.text("ended_at IS NULL"),
            postgresql_where=sa.text("ended_at IS NULL"),
        ),
    )
    op.create_index("ix_key_result_themes_user_id", "key_result_themes", ["user_id"])
    op.create_index("ix_key_result_themes_key_result_id", "key_result_themes", ["key_result_id"])
    op.create_index("ix_key_result_themes_project_id", "key_result_themes", ["project_id"])
    op.create_index("ix_key_result_themes_batch_id", "key_result_themes", ["batch_id"])

    op.create_table(
        "plan_changes",
        sa.Column("id", sa.Uuid(), primary_key=True),
        sa.Column(
            "user_id", sa.Uuid(), sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False
        ),
        sa.Column("year", sa.Integer(), nullable=False),
        sa.Column(
            "goal_id", sa.Uuid(), sa.ForeignKey("goals.id", ondelete="CASCADE"), nullable=True
        ),
        sa.Column(
            "key_result_id",
            sa.Uuid(),
            sa.ForeignKey("key_results.id", ondelete="CASCADE"),
            nullable=True,
        ),
        sa.Column(
            "link_id",
            sa.Uuid(),
            sa.ForeignKey("key_result_themes.id", ondelete="SET NULL"),
            nullable=True,
        ),
        sa.Column("kind", sa.String(24), nullable=False),
        sa.Column("field", sa.String(16), nullable=True),
        sa.Column("old_value", sa.Text(), nullable=True),
        sa.Column("new_value", sa.Text(), nullable=True),
        sa.Column("reason", sa.Text(), nullable=True),
        sa.Column("batch_id", sa.Uuid(), nullable=True),
        sa.Column("source", sa.String(9), nullable=False),
        sa.Column("at", sa.DateTime(timezone=True), nullable=False),
        sa.CheckConstraint(
            "kind IN ('goal_created','goal_edited','goal_retired','goal_restored',"
            "'key_result_created','key_result_edited','key_result_retired','key_result_restored',"
            "'link_added','link_removed','migrated')",
            name="ck_plan_changes_kind",
        ),
    )
    op.create_index("ix_plan_changes_user_id", "plan_changes", ["user_id"])
    op.create_index("ix_plan_changes_year", "plan_changes", ["year"])
    op.create_index("ix_plan_changes_batch_id", "plan_changes", ["batch_id"])

    op.create_table(
        "value_push_tokens",
        sa.Column("id", sa.Uuid(), primary_key=True),
        sa.Column(
            "user_id", sa.Uuid(), sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False
        ),
        sa.Column("token_hash", sa.String(64), nullable=False),
        sa.Column("hint", sa.String(4), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("last_used_at", sa.DateTime(timezone=True), nullable=True),
        sa.UniqueConstraint("user_id", name="uq_value_push_tokens_user_id"),
        sa.UniqueConstraint("token_hash", name="uq_value_push_tokens_token_hash"),
    )

    _migrate_year_goals()


def _migrate_year_goals() -> None:
    """Turn ``dropped`` year goals into ``retired`` ones and record the move (R-01, step 3-4)."""
    conn = op.get_bind()
    now = datetime.now(UTC)
    changed = conn.execute(
        sa.text(
            "select id, user_id, period_start, status, criteria from goals "
            "where period_type = 'year' and (status = 'dropped' or criteria <> '')"
        )
    ).fetchall()
    conn.execute(
        sa.text(
            "update goals set status = 'retired', retired_at = :now, "
            "retired_reason = 'Dropped before annual planning' "
            "where period_type = 'year' and status = 'dropped'"
        ),
        {"now": now},
    )
    for goal_id, user_id, period_start, old_status, _criteria in changed:
        if isinstance(period_start, str):  # SQLite returns raw strings.
            period_start = date.fromisoformat(period_start)
        new_status = "retired" if old_status == "dropped" else old_status
        conn.execute(
            sa.text(
                "insert into plan_changes (id, user_id, year, goal_id, key_result_id, link_id, "
                "kind, field, old_value, new_value, reason, batch_id, source, at) "
                "values (:id, :user_id, :year, :goal_id, null, null, 'migrated', null, "
                ":old_value, :new_value, null, null, 'migration', :at)"
            ),
            {
                "id": str(uuid.uuid4()),
                "user_id": str(user_id),
                "year": period_start.year,
                "goal_id": str(goal_id),
                "old_value": old_status,
                "new_value": new_status,
                "at": now,
            },
        )


def downgrade() -> None:
    op.drop_table("value_push_tokens")
    op.drop_table("plan_changes")
    op.drop_table("key_result_themes")
    op.drop_table("key_result_values")
    op.drop_table("key_results")
    # Turn ``retired`` year goals back into ``dropped`` ones before the columns disappear.
    op.execute(
        "update goals set status = 'dropped', retired_at = null, retired_reason = null "
        "where period_type = 'year' and status = 'retired'"
    )
    with op.batch_alter_table("goals", recreate="never") as batch:
        batch.drop_index("ix_goals_user_period")
        batch.drop_column("position")
        batch.drop_column("retired_reason")
        batch.drop_column("retired_at")
        batch.drop_column("updated_at")
