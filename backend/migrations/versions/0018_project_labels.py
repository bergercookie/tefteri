"""project labels: the label of each task-app project, its orphan state and its history

Revision ID: 0018
Revises: 0017
"""

import sqlalchemy as sa
from alembic import op

revision = "0018"
down_revision = "0017"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "project_labels",
        sa.Column("id", sa.Uuid(), primary_key=True),
        sa.Column(
            "user_id", sa.Uuid(), sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False
        ),
        sa.Column(
            "connection_id",
            sa.Uuid(),
            sa.ForeignKey("connections.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("remote_id", sa.String(255), nullable=False),
        sa.Column("name", sa.String(255), nullable=False),
        sa.Column("parent_remote_id", sa.String(255), nullable=True),
        sa.Column("label", sa.String(16), nullable=True),
        sa.Column("label_changed_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("orphaned_reason", sa.String(16), nullable=True),
        sa.Column("orphaned_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.UniqueConstraint("connection_id", "remote_id"),
    )
    op.create_index(
        "ix_project_labels_user_connection", "project_labels", ["user_id", "connection_id"]
    )
    op.create_table(
        "project_label_history",
        sa.Column("id", sa.Uuid(), primary_key=True),
        sa.Column(
            "project_id",
            sa.Uuid(),
            sa.ForeignKey("project_labels.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("label", sa.String(16), nullable=True),
        sa.Column("from_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("batch_id", sa.Uuid(), nullable=True),
        sa.Column("source", sa.String(16), nullable=False),
    )
    op.create_index("ix_project_label_history_project_id", "project_label_history", ["project_id"])
    op.create_index("ix_project_label_history_batch_id", "project_label_history", ["batch_id"])


def downgrade() -> None:
    op.drop_index("ix_project_label_history_batch_id", table_name="project_label_history")
    op.drop_index("ix_project_label_history_project_id", table_name="project_label_history")
    op.drop_table("project_label_history")
    op.drop_index("ix_project_labels_user_connection", table_name="project_labels")
    op.drop_table("project_labels")
