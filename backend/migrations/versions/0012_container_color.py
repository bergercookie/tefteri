"""the color of a calendar in the app that holds it

Revision ID: 0012
Revises: 0011
"""

import sqlalchemy as sa
from alembic import op

revision = "0012"
down_revision = "0011"
branch_labels = None
depends_on = None


def upgrade() -> None:
    with op.batch_alter_table("source_containers") as batch:
        batch.add_column(sa.Column("color", sa.String(length=7), nullable=True))


def downgrade() -> None:
    with op.batch_alter_table("source_containers") as batch:
        batch.drop_column("color")
