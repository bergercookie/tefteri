"""user setting: the people that the user usually invites to events

Revision ID: 0032
Revises: 0031
"""

import sqlalchemy as sa
from alembic import op

revision = "0032"
down_revision = "0031"
branch_labels = None
depends_on = None


def upgrade() -> None:
    """Add the column; the list is empty until the user adds a person."""
    with op.batch_alter_table("users") as batch:
        batch.add_column(
            sa.Column("event_invitees", sa.JSON(), nullable=False, server_default=sa.text("'[]'"))
        )


def downgrade() -> None:
    """Remove the column."""
    with op.batch_alter_table("users") as batch:
        batch.drop_column("event_invitees")
