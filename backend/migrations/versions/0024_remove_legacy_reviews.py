"""remove legacy plans and period reviews

Revision ID: 0024
Revises: 0023

The Reviews screen and the stored period reviews that fed it are gone. ``period_reviews``
depends on ``plans``, so it is dropped first. No other table points at either one.
"""

import sqlalchemy as sa
from alembic import op

revision = "0024"
down_revision = "0023"
branch_labels = None
depends_on = None


def upgrade() -> None:
    """Drop the legacy review tables."""
    with op.batch_alter_table("period_reviews", schema=None) as batch_op:
        batch_op.drop_index(batch_op.f("ix_period_reviews_user_id"))
    op.drop_table("period_reviews")

    with op.batch_alter_table("plans", schema=None) as batch_op:
        batch_op.drop_index(batch_op.f("ix_plans_user_id"))
    op.drop_table("plans")


def downgrade() -> None:
    """Recreate the empty legacy tables."""
    op.create_table(
        "plans",
        sa.Column("user_id", sa.Uuid(), nullable=False),
        sa.Column("period_type", sa.String(length=8), nullable=False),
        sa.Column("period_start", sa.Date(), nullable=False),
        sa.Column("title", sa.String(length=500), nullable=False),
        sa.Column("summary", sa.Text(), nullable=False),
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
    )
    with op.batch_alter_table("plans", schema=None) as batch_op:
        batch_op.create_index(batch_op.f("ix_plans_user_id"), ["user_id"], unique=False)

    op.create_table(
        "period_reviews",
        sa.Column("user_id", sa.Uuid(), nullable=False),
        sa.Column("plan_id", sa.Uuid(), nullable=False),
        sa.Column("generated_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("planned_count", sa.Integer(), nullable=False),
        sa.Column("completed_count", sa.Integer(), nullable=False),
        sa.Column("carried_over", sa.JSON(), nullable=False),
        sa.Column("items", sa.JSON(), nullable=False),
        sa.Column("retrospective_note_id", sa.Uuid(), nullable=True),
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.ForeignKeyConstraint(["plan_id"], ["plans.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["retrospective_note_id"], ["notes.id"], ondelete="SET NULL"),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("plan_id"),
    )
    with op.batch_alter_table("period_reviews", schema=None) as batch_op:
        batch_op.create_index(batch_op.f("ix_period_reviews_user_id"), ["user_id"], unique=False)
