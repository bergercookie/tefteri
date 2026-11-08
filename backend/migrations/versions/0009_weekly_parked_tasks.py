"""tasks parked in a weekly plan

Revision ID: 0009
Revises: 0008
"""

import sqlalchemy as sa
from alembic import op

revision = "0009"
down_revision = "0008"
branch_labels = None
depends_on = None


def upgrade() -> None:
    with op.batch_alter_table("weekly_plan_projects") as batch:
        batch.add_column(
            sa.Column("parked_task_ids", sa.JSON(), nullable=False, server_default="[]")
        )


def downgrade() -> None:
    with op.batch_alter_table("weekly_plan_projects") as batch:
        batch.drop_column("parked_task_ids")
