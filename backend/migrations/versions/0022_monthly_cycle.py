"""monthly focus and review snapshots

Revision ID: 0022
Revises: 0021

Adds the monthly focus, change history, and versioned review tables without changing old data.
"""

import sqlalchemy as sa
from alembic import op

revision = "0022"
down_revision = "0021"
branch_labels = None
depends_on = None

_FIRST_OF_MONTH = "CAST(substr(CAST(month AS VARCHAR), 9, 2) AS INTEGER) = 1"


def upgrade() -> None:
    """Create the five additive tables for monthly focus and review."""
    op.create_table(
        "monthly_focuses",
        sa.Column("id", sa.Uuid(), primary_key=True),
        sa.Column(
            "user_id", sa.Uuid(), sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False
        ),
        sa.Column("month", sa.Date(), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.UniqueConstraint("user_id", "month", name="uq_monthly_focuses_user_month"),
        sa.CheckConstraint(_FIRST_OF_MONTH, name="ck_monthly_focuses_first_of_month"),
    )
    op.create_index("ix_monthly_focuses_user_id", "monthly_focuses", ["user_id"])

    op.create_table(
        "monthly_focus_entries",
        sa.Column("id", sa.Uuid(), primary_key=True),
        sa.Column(
            "focus_id",
            sa.Uuid(),
            sa.ForeignKey("monthly_focuses.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column(
            "project_id",
            sa.Uuid(),
            sa.ForeignKey("project_labels.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("name", sa.String(255), nullable=False),
        sa.Column("target", sa.Integer(), nullable=True),
        sa.Column("counts_from", sa.Date(), nullable=False),
        sa.Column("left_on", sa.Date(), nullable=True),
        sa.Column("left_reason", sa.String(12), nullable=True),
        sa.Column("position", sa.Integer(), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.UniqueConstraint(
            "focus_id", "project_id", name="uq_monthly_focus_entries_focus_project"
        ),
        sa.CheckConstraint("target IS NULL OR target >= 0", name="ck_monthly_focus_entries_target"),
        sa.CheckConstraint(
            "(left_on IS NULL) = (left_reason IS NULL)",
            name="ck_monthly_focus_entries_left_state",
        ),
    )
    op.create_index("ix_monthly_focus_entries_focus_id", "monthly_focus_entries", ["focus_id"])
    op.create_index("ix_monthly_focus_entries_project_id", "monthly_focus_entries", ["project_id"])

    op.create_table(
        "focus_changes",
        sa.Column("id", sa.Uuid(), primary_key=True),
        sa.Column(
            "focus_id",
            sa.Uuid(),
            sa.ForeignKey("monthly_focuses.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("kind", sa.String(8), nullable=False),
        sa.Column("changed_on", sa.Date(), nullable=False),
        sa.Column(
            "out_entry_id",
            sa.Uuid(),
            sa.ForeignKey("monthly_focus_entries.id", ondelete="SET NULL"),
            nullable=True,
        ),
        sa.Column(
            "in_entry_id",
            sa.Uuid(),
            sa.ForeignKey("monthly_focus_entries.id", ondelete="SET NULL"),
            nullable=True,
        ),
        sa.Column(
            "out_project_id",
            sa.Uuid(),
            sa.ForeignKey("project_labels.id", ondelete="SET NULL"),
            nullable=True,
        ),
        sa.Column(
            "in_project_id",
            sa.Uuid(),
            sa.ForeignKey("project_labels.id", ondelete="SET NULL"),
            nullable=True,
        ),
        sa.Column("out_name", sa.String(255), nullable=True),
        sa.Column("in_name", sa.String(255), nullable=True),
        sa.Column("target_before", sa.Integer(), nullable=True),
        sa.Column("target_after", sa.Integer(), nullable=True),
        sa.Column("batch_id", sa.Uuid(), nullable=False),
        sa.Column("undoes_batch_id", sa.Uuid(), nullable=True),
        sa.Column("source", sa.String(8), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
    )
    op.create_index("ix_focus_changes_focus_id", "focus_changes", ["focus_id"])
    op.create_index("ix_focus_changes_batch_id", "focus_changes", ["batch_id"])
    op.create_index("ix_focus_changes_undoes_batch_id", "focus_changes", ["undoes_batch_id"])

    op.create_table(
        "monthly_reviews",
        sa.Column("id", sa.Uuid(), primary_key=True),
        sa.Column(
            "user_id", sa.Uuid(), sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False
        ),
        sa.Column("month", sa.Date(), nullable=False),
        sa.Column("current_version", sa.Integer(), nullable=False),
        sa.Column("current_changed_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.UniqueConstraint("user_id", "month", name="uq_monthly_reviews_user_month"),
        sa.CheckConstraint(_FIRST_OF_MONTH, name="ck_monthly_reviews_first_of_month"),
    )
    op.create_index("ix_monthly_reviews_user_id", "monthly_reviews", ["user_id"])

    op.create_table(
        "monthly_review_snapshots",
        sa.Column("id", sa.Uuid(), primary_key=True),
        sa.Column(
            "review_id",
            sa.Uuid(),
            sa.ForeignKey("monthly_reviews.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("version", sa.Integer(), nullable=False),
        sa.Column("schema_version", sa.Integer(), nullable=False),
        sa.Column("payload", sa.JSON(), nullable=False),
        sa.Column("values_written", sa.JSON(), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.UniqueConstraint(
            "review_id", "version", name="uq_monthly_review_snapshots_review_version"
        ),
    )
    op.create_index(
        "ix_monthly_review_snapshots_review_id", "monthly_review_snapshots", ["review_id"]
    )


def downgrade() -> None:
    """Drop only the five tables introduced by this revision."""
    op.drop_table("monthly_review_snapshots")
    op.drop_table("monthly_reviews")
    op.drop_table("focus_changes")
    op.drop_table("monthly_focus_entries")
    op.drop_table("monthly_focuses")
