"""remove the work/life context

Revision ID: 0011
Revises: 0010
"""

import sqlalchemy as sa
from alembic import op

revision = "0011"
down_revision = "0010"
branch_labels = None
depends_on = None

NULLABLE_TABLES = ("tasks", "notes", "calendar_entries", "source_containers")


def upgrade() -> None:
    for table in NULLABLE_TABLES:
        with op.batch_alter_table(table) as batch:
            batch.drop_column("context")
    with op.batch_alter_table("goals") as batch:
        batch.drop_column("context")
    with op.batch_alter_table("connections") as batch:
        batch.drop_column("default_context")


def downgrade() -> None:
    with op.batch_alter_table("connections") as batch:
        batch.add_column(
            sa.Column("default_context", sa.String(length=8), nullable=False, server_default="life")
        )
    with op.batch_alter_table("goals") as batch:
        batch.add_column(
            sa.Column("context", sa.String(length=8), nullable=False, server_default="life")
        )
    for table in NULLABLE_TABLES:
        with op.batch_alter_table(table) as batch:
            batch.add_column(sa.Column("context", sa.String(length=8), nullable=True))
