"""users: how long before a calendar event the app reminds the user

Revision ID: 0038
Revises: 0037
"""

import sqlalchemy as sa
from alembic import op

revision = "0038"
down_revision = "0037"
branch_labels = None
depends_on = None


def upgrade() -> None:
    """Add the column. Every user starts with 15 minutes."""
    with op.batch_alter_table("users") as batch:
        batch.add_column(
            sa.Column("event_reminder_minutes", sa.Integer(), nullable=False, server_default="15")
        )


def downgrade() -> None:
    """Remove the column."""
    with op.batch_alter_table("users") as batch:
        batch.drop_column("event_reminder_minutes")
