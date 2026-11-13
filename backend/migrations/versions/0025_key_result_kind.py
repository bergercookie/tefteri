"""key result kind

Revision ID: 0025
Revises: 0024

Adds ``kind`` to ``key_results``: a number (the old behaviour) or a yes/no answer. Existing
rows are numbers. A yes/no key result stores 0 or 1 as its value.
"""

import sqlalchemy as sa
from alembic import op

revision = "0025"
down_revision = "0024"
branch_labels = None
depends_on = None


def upgrade() -> None:
    """Add the kind column with a safe default for existing key results."""
    with op.batch_alter_table("key_results", schema=None) as batch_op:
        batch_op.add_column(
            sa.Column("kind", sa.String(length=8), nullable=False, server_default="number")
        )
        batch_op.create_check_constraint("ck_key_results_kind", "kind IN ('number', 'yes_no')")


def downgrade() -> None:
    """Remove the kind column; the stored values stay numbers."""
    with op.batch_alter_table("key_results", schema=None) as batch_op:
        batch_op.drop_constraint("ck_key_results_kind", type_="check")
        batch_op.drop_column("kind")
