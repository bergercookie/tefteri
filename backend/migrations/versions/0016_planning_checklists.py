"""planning checklists: the lists of a user and the ticks of each period

Revision ID: 0016
Revises: 0015
"""

import sqlalchemy as sa
from alembic import op

revision = "0016"
down_revision = "0015"
branch_labels = None
depends_on = None


def upgrade() -> None:
    with op.batch_alter_table("users") as batch:
        batch.add_column(
            sa.Column("checklists", sa.JSON(), nullable=False, server_default=sa.text("'{}'"))
        )
    op.create_table(
        "checklist_progress",
        sa.Column("id", sa.Uuid(), primary_key=True),
        sa.Column(
            "user_id", sa.Uuid(), sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False
        ),
        sa.Column("period_type", sa.String(5), nullable=False),
        sa.Column("period_start", sa.Date(), nullable=False),
        sa.Column("checked", sa.JSON(), nullable=False),
        sa.UniqueConstraint("user_id", "period_type", "period_start"),
    )
    op.create_index("ix_checklist_progress_user_id", "checklist_progress", ["user_id"])


def downgrade() -> None:
    op.drop_index("ix_checklist_progress_user_id", table_name="checklist_progress")
    op.drop_table("checklist_progress")
    with op.batch_alter_table("users") as batch:
        batch.drop_column("checklists")
