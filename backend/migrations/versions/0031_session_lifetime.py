"""login session: remember how long it lasts, so that use can renew it

Revision ID: 0031
Revises: 0030
"""

import sqlalchemy as sa
from alembic import op

revision = "0031"
down_revision = "0030"
branch_labels = None
depends_on = None


def upgrade() -> None:
    """Add the column; a session from before this change has none and is not renewed."""
    with op.batch_alter_table("auth_sessions") as batch:
        batch.add_column(sa.Column("lifetime_seconds", sa.Integer(), nullable=True))


def downgrade() -> None:
    """Remove the column."""
    with op.batch_alter_table("auth_sessions") as batch:
        batch.drop_column("lifetime_seconds")
