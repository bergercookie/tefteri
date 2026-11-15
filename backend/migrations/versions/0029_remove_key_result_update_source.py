"""remove the key result update source

Revision ID: 0029
Revises: 0028

Removes ``update_source`` from ``key_results``. The setting said that an outside source would
push values to a key result. The push contract was removed in revision 0026, so nothing ever
wrote an automatic value, and the setting behaved like manual entry. The user types every value.
"""

import sqlalchemy as sa
from alembic import op

revision = "0029"
down_revision = "0028"
branch_labels = None
depends_on = None


def upgrade() -> None:
    """Drop the column. A key result keeps its series, links and history."""
    with op.batch_alter_table("key_results", schema=None) as batch_op:
        batch_op.drop_column("update_source")


def downgrade() -> None:
    """Add the column again. Every key result is manual, as the code always treated it."""
    with op.batch_alter_table("key_results", schema=None) as batch_op:
        batch_op.add_column(
            sa.Column("update_source", sa.String(length=9), nullable=False, server_default="manual")
        )
