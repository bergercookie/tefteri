"""calendar entries: the description of the event

Revision ID: 0036
Revises: 0035
"""

import sqlalchemy as sa
from alembic import op

revision = "0036"
down_revision = "0035"
branch_labels = None
depends_on = None


def upgrade() -> None:
    """Add the column. It is empty until the next sync reads the description."""
    with op.batch_alter_table("calendar_entries") as batch:
        batch.add_column(
            sa.Column("description", sa.Text(), nullable=False, server_default=sa.text("''"))
        )


def downgrade() -> None:
    """Remove the column."""
    with op.batch_alter_table("calendar_entries") as batch:
        batch.drop_column("description")
