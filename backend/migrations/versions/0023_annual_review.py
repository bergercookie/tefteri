"""annual review notes

Revision ID: 0023
Revises: 0022

Adds the one table that the annual review writes: one note for a year and one for each goal.
No existing table is changed.
"""

import sqlalchemy as sa
from alembic import op

revision = "0023"
down_revision = "0022"
branch_labels = None
depends_on = None


def upgrade() -> None:
    """Create ``review_notes`` with its partial unique indexes and length check."""
    op.create_table(
        "review_notes",
        sa.Column("id", sa.Uuid(), primary_key=True),
        sa.Column(
            "user_id", sa.Uuid(), sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False
        ),
        sa.Column("year", sa.Integer(), nullable=False),
        sa.Column(
            "goal_id", sa.Uuid(), sa.ForeignKey("goals.id", ondelete="CASCADE"), nullable=True
        ),
        sa.Column("body", sa.Text(), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.CheckConstraint(
            "length(body) BETWEEN 1 AND 2000", name="ck_review_notes_body_length"
        ),
        sa.CheckConstraint("year BETWEEN 2000 AND 2100", name="ck_review_notes_year"),
    )
    op.create_index("ix_review_notes_user_id", "review_notes", ["user_id"])
    op.create_index("ix_review_notes_user_year", "review_notes", ["user_id", "year"])
    op.create_index(
        "uq_review_notes_year",
        "review_notes",
        ["user_id", "year"],
        unique=True,
        sqlite_where=sa.text("goal_id IS NULL"),
        postgresql_where=sa.text("goal_id IS NULL"),
    )
    op.create_index(
        "uq_review_notes_goal",
        "review_notes",
        ["user_id", "goal_id"],
        unique=True,
        sqlite_where=sa.text("goal_id IS NOT NULL"),
        postgresql_where=sa.text("goal_id IS NOT NULL"),
    )


def downgrade() -> None:
    """Drop only ``review_notes``; the notes are lost."""
    op.drop_index("uq_review_notes_goal", table_name="review_notes")
    op.drop_index("uq_review_notes_year", table_name="review_notes")
    op.drop_index("ix_review_notes_user_year", table_name="review_notes")
    op.drop_index("ix_review_notes_user_id", table_name="review_notes")
    op.drop_table("review_notes")
