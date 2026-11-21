"""the numbers of each finished week, kept so that a week can be compared with the earlier ones

Revision ID: 0035
Revises: 0034
"""

import sqlalchemy as sa
from alembic import op

revision = "0035"
down_revision = "0034"
branch_labels = None
depends_on = None


def upgrade() -> None:
    """Create the table. It fills itself the first time that the trends are read."""
    op.create_table(
        "weekly_metrics",
        sa.Column("id", sa.Uuid(), primary_key=True),
        sa.Column(
            "user_id", sa.Uuid(), sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False
        ),
        sa.Column("week_start", sa.Date(), nullable=False),
        sa.Column("reviewed", sa.Boolean(), nullable=False, server_default=sa.false()),
        sa.Column("committed_tasks", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("committed_done", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("milestones_committed", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("milestones_done", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("milestones_finished", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("tasks_done", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("goal_aligned", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("maintenance", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("off_plan", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("themes_active", sa.Integer(), nullable=False, server_default="0"),
        sa.UniqueConstraint("user_id", "week_start"),
    )
    op.create_index("ix_weekly_metrics_user_id", "weekly_metrics", ["user_id"])


def downgrade() -> None:
    """Drop the table."""
    op.drop_index("ix_weekly_metrics_user_id", table_name="weekly_metrics")
    op.drop_table("weekly_metrics")
