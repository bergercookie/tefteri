"""work categories: the stored category of each completed task

Revision ID: 0021
Revises: 0019

Adds one table. It copies no data and runs no UPDATE: the first sync after the upgrade records
every completed task (spec 005, research R-15).

The plan numbers this revision after 0020, which feature 006 reserves. Feature 006 is not built
yet, so this revision follows 0019. When feature 006 adds 0020, it must make 0020 revise 0019
and this revision revise 0020 (change ``down_revision`` below).
"""

import sqlalchemy as sa
from alembic import op

revision = "0021"
down_revision = "0019"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "task_categories",
        sa.Column("id", sa.Uuid(), primary_key=True),
        sa.Column(
            "user_id", sa.Uuid(), sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False
        ),
        sa.Column(
            "task_id", sa.Uuid(), sa.ForeignKey("tasks.id", ondelete="CASCADE"), nullable=False
        ),
        sa.Column("completed_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("completed_on", sa.Date(), nullable=False),
        sa.Column("category", sa.String(12), nullable=False),
        sa.Column("reason", sa.String(24), nullable=False),
        sa.Column("unsorted", sa.Boolean(), nullable=False),
        sa.Column(
            "project_id",
            sa.Uuid(),
            sa.ForeignKey("project_labels.id", ondelete="SET NULL"),
            nullable=True,
        ),
        sa.Column("project_name", sa.String(255), nullable=True),
        sa.Column("project_label", sa.String(16), nullable=True),
        sa.Column(
            "plan_id",
            sa.Uuid(),
            sa.ForeignKey("weekly_plans.id", ondelete="SET NULL"),
            nullable=True,
        ),
        sa.Column("decided_via", sa.String(8), nullable=False),
        sa.Column("decided_at", sa.DateTime(timezone=True), nullable=False),
        sa.UniqueConstraint("task_id", name="uq_task_categories_task_id"),
        sa.CheckConstraint(
            "category IN ('goal_aligned','maintenance','off_plan','hidden')",
            name="ck_task_categories_category",
        ),
    )
    op.create_index(
        "ix_task_categories_user_day_category",
        "task_categories",
        ["user_id", "completed_on", "category"],
    )
    op.create_index(
        "ix_task_categories_user_category_completed",
        "task_categories",
        ["user_id", "category", "completed_at"],
    )
    op.create_index("ix_task_categories_project_id", "task_categories", ["project_id"])


def downgrade() -> None:
    op.drop_index("ix_task_categories_project_id", table_name="task_categories")
    op.drop_index("ix_task_categories_user_category_completed", table_name="task_categories")
    op.drop_index("ix_task_categories_user_day_category", table_name="task_categories")
    op.drop_table("task_categories")
