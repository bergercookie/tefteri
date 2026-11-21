"""project label: a theme can be marked as work

Revision ID: 0033
Revises: 0032
"""

import sqlalchemy as sa
from alembic import op

revision = "0033"
down_revision = "0032"
branch_labels = None
depends_on = None


def upgrade() -> None:
    """Add the flag; no theme is work until the user says so."""
    with op.batch_alter_table("project_labels") as batch:
        batch.add_column(
            sa.Column("is_work", sa.Boolean(), nullable=False, server_default=sa.false())
        )


def downgrade() -> None:
    """Remove the flag."""
    with op.batch_alter_table("project_labels") as batch:
        batch.drop_column("is_work")
