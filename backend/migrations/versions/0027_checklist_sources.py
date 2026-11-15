"""add the notes path of each planning checklist

Revision ID: 0027
Revises: 0026

A checklist can come from a note in the notes app instead of the list in the settings. The
path is kept per period type. Existing users keep their local lists and get no source.
"""

import sqlalchemy as sa
from alembic import op

revision = "0027"
down_revision = "0026"
branch_labels = None
depends_on = None


def upgrade() -> None:
    """Add the source paths to the users table."""
    with op.batch_alter_table("users") as batch:
        batch.add_column(
            sa.Column(
                "checklist_sources", sa.JSON(), nullable=False, server_default=sa.text("'{}'")
            )
        )


def downgrade() -> None:
    """Drop the source paths; the local lists stay."""
    with op.batch_alter_table("users") as batch:
        batch.drop_column("checklist_sources")
