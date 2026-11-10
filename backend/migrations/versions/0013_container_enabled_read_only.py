"""which calendars tefteri syncs, and which are read-only

Revision ID: 0013
Revises: 0012
"""

import sqlalchemy as sa
from alembic import op

revision = "0013"
down_revision = "0012"
branch_labels = None
depends_on = None


def upgrade() -> None:
    with op.batch_alter_table("source_containers") as batch:
        batch.add_column(
            sa.Column("enabled", sa.Boolean(), nullable=False, server_default=sa.true())
        )
        batch.add_column(
            sa.Column("read_only", sa.Boolean(), nullable=False, server_default=sa.false())
        )


def downgrade() -> None:
    with op.batch_alter_table("source_containers") as batch:
        batch.drop_column("read_only")
        batch.drop_column("enabled")
