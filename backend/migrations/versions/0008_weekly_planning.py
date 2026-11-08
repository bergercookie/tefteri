"""weekly planning sessions, and the parent of a project

Revision ID: 0008
Revises: 0007
"""

import sqlalchemy as sa
from alembic import op

revision = "0008"
down_revision = "0007"
branch_labels = None
depends_on = None


def upgrade() -> None:
    with op.batch_alter_table("source_containers") as batch:
        batch.add_column(sa.Column("parent_remote_id", sa.String(length=255), nullable=True))
    op.create_table(
        "weekly_plans",
        sa.Column("user_id", sa.Uuid(), nullable=False),
        sa.Column("week_start", sa.Date(), nullable=False),
        sa.Column("status", sa.String(length=12), nullable=False),
        sa.Column("committed_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("retro_skipped", sa.Boolean(), nullable=False),
        sa.Column("reviewed_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("reflection", sa.Text(), nullable=False),
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("user_id", "week_start"),
    )
    with op.batch_alter_table("weekly_plans") as batch:
        batch.create_index(batch.f("ix_weekly_plans_user_id"), ["user_id"], unique=False)
    op.create_table(
        "weekly_plan_projects",
        sa.Column("plan_id", sa.Uuid(), nullable=False),
        sa.Column("container_id", sa.Uuid(), nullable=True),
        sa.Column("name", sa.String(length=255), nullable=False),
        sa.Column("position", sa.Integer(), nullable=False),
        sa.Column("created_here", sa.Boolean(), nullable=False),
        sa.Column("committed_task_ids", sa.JSON(), nullable=False),
        sa.Column("outcome", sa.String(length=12), nullable=True),
        sa.Column("leftover_action", sa.String(length=8), nullable=True),
        sa.Column("reviewed_committed", sa.Integer(), nullable=True),
        sa.Column("reviewed_done", sa.Integer(), nullable=True),
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.ForeignKeyConstraint(["plan_id"], ["weekly_plans.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["container_id"], ["source_containers.id"], ondelete="SET NULL"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("plan_id", "container_id"),
    )
    with op.batch_alter_table("weekly_plan_projects") as batch:
        batch.create_index(batch.f("ix_weekly_plan_projects_plan_id"), ["plan_id"], unique=False)


def downgrade() -> None:
    with op.batch_alter_table("weekly_plan_projects") as batch:
        batch.drop_index(batch.f("ix_weekly_plan_projects_plan_id"))
    op.drop_table("weekly_plan_projects")
    with op.batch_alter_table("weekly_plans") as batch:
        batch.drop_index(batch.f("ix_weekly_plans_user_id"))
    op.drop_table("weekly_plans")
    with op.batch_alter_table("source_containers") as batch:
        batch.drop_column("parent_remote_id")
