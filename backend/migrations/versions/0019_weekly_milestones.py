"""weekly milestones: milestone rows, rollover events, close logs and the review decision

Revision ID: 0019
Revises: 0018

Adds three tables and six nullable columns. It runs no UPDATE: the old choices of the look-back
(``leftover_action`` carry and backlog) are mapped on read, and no old row changes.
"""

import sqlalchemy as sa
from alembic import op

revision = "0019"
down_revision = "0018"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "milestones",
        sa.Column("id", sa.Uuid(), primary_key=True),
        sa.Column(
            "user_id", sa.Uuid(), sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False
        ),
        sa.Column(
            "project_id",
            sa.Uuid(),
            sa.ForeignKey("project_labels.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("done_state", sa.String(255), nullable=True),
        sa.Column("state", sa.String(8), nullable=False),
        sa.Column("state_changed_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("rollover_count", sa.Integer(), nullable=False),
        sa.Column("done_on", sa.Date(), nullable=True),
        sa.Column("done_by", sa.String(4), nullable=True),
        sa.Column(
            "done_theme_id",
            sa.Uuid(),
            sa.ForeignKey("project_labels.id", ondelete="SET NULL"),
            nullable=True,
        ),
        sa.Column("done_theme_name", sa.String(255), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.UniqueConstraint("project_id"),
    )
    op.create_index("ix_milestones_user_state", "milestones", ["user_id", "state"])
    op.create_table(
        "milestone_rollovers",
        sa.Column("id", sa.Uuid(), primary_key=True),
        sa.Column(
            "milestone_id",
            sa.Uuid(),
            sa.ForeignKey("milestones.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column(
            "plan_project_id",
            sa.Uuid(),
            sa.ForeignKey("weekly_plan_projects.id", ondelete="SET NULL"),
            nullable=True,
        ),
        sa.Column("from_week", sa.Date(), nullable=False),
        sa.Column("to_week", sa.Date(), nullable=False),
        sa.Column("expected", sa.Boolean(), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
    )
    op.create_index("ix_milestone_rollovers_milestone_id", "milestone_rollovers", ["milestone_id"])
    op.create_table(
        "milestone_closures",
        sa.Column("id", sa.Uuid(), primary_key=True),
        sa.Column(
            "milestone_id",
            sa.Uuid(),
            sa.ForeignKey("milestones.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column(
            "plan_project_id",
            sa.Uuid(),
            sa.ForeignKey("weekly_plan_projects.id", ondelete="SET NULL"),
            nullable=True,
        ),
        sa.Column(
            "theme_project_id",
            sa.Uuid(),
            sa.ForeignKey("project_labels.id", ondelete="SET NULL"),
            nullable=True,
        ),
        sa.Column("theme_name", sa.String(255), nullable=False),
        sa.Column("status", sa.String(8), nullable=False),
        sa.Column("moved", sa.JSON(), nullable=False),
        sa.Column("started_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("finished_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("reopened_at", sa.DateTime(timezone=True), nullable=True),
    )
    op.create_index("ix_milestone_closures_milestone_id", "milestone_closures", ["milestone_id"])
    with op.batch_alter_table("weekly_plan_projects") as batch:
        batch.add_column(sa.Column("milestone_id", sa.Uuid(), nullable=True))
        batch.add_column(sa.Column("theme_project_id", sa.Uuid(), nullable=True))
        batch.add_column(sa.Column("theme_name", sa.String(255), nullable=True))
        batch.add_column(sa.Column("decision", sa.String(12), nullable=True))
        batch.add_column(sa.Column("expected_rollover", sa.Boolean(), nullable=True))
        batch.add_column(sa.Column("decided_at", sa.DateTime(timezone=True), nullable=True))
        batch.create_foreign_key(
            "fk_weekly_plan_projects_milestone_id",
            "milestones",
            ["milestone_id"],
            ["id"],
            ondelete="SET NULL",
        )
        batch.create_foreign_key(
            "fk_weekly_plan_projects_theme_project_id",
            "project_labels",
            ["theme_project_id"],
            ["id"],
            ondelete="SET NULL",
        )
        batch.create_index("ix_weekly_plan_projects_milestone_id", ["milestone_id"])
        batch.create_unique_constraint(
            "uq_weekly_plan_projects_plan_id_milestone_id", ["plan_id", "milestone_id"]
        )


def downgrade() -> None:
    with op.batch_alter_table("weekly_plan_projects") as batch:
        batch.drop_constraint("uq_weekly_plan_projects_plan_id_milestone_id", type_="unique")
        batch.drop_index("ix_weekly_plan_projects_milestone_id")
        batch.drop_constraint("fk_weekly_plan_projects_theme_project_id", type_="foreignkey")
        batch.drop_constraint("fk_weekly_plan_projects_milestone_id", type_="foreignkey")
        batch.drop_column("decided_at")
        batch.drop_column("expected_rollover")
        batch.drop_column("decision")
        batch.drop_column("theme_name")
        batch.drop_column("theme_project_id")
        batch.drop_column("milestone_id")
    op.drop_index("ix_milestone_closures_milestone_id", table_name="milestone_closures")
    op.drop_table("milestone_closures")
    op.drop_index("ix_milestone_rollovers_milestone_id", table_name="milestone_rollovers")
    op.drop_table("milestone_rollovers")
    op.drop_index("ix_milestones_user_state", table_name="milestones")
    op.drop_table("milestones")
