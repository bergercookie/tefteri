"""user setting: the hints that the user has seen

Revision ID: 0034
Revises: 0033
"""

import sqlalchemy as sa
from alembic import op

revision = "0034"
down_revision = "0033"
branch_labels = None
depends_on = None


def upgrade() -> None:
    """Add the column; the list is empty, so every hint shows once."""
    with op.batch_alter_table("users") as batch:
        batch.add_column(
            sa.Column("seen_hints", sa.JSON(), nullable=False, server_default=sa.text("'[]'"))
        )


def downgrade() -> None:
    """Remove the column."""
    with op.batch_alter_table("users") as batch:
        batch.drop_column("seen_hints")
