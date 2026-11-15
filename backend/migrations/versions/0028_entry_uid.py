"""calendar entry uid

Revision ID: 0028
Revises: 0027

Adds ``uid`` to ``calendar_entries``: the iCalendar UID of the event. It is the same in every
calendar that holds a copy of the event (an event in one calendar to which the owner of another
calendar was invited), so the planner can show the copies as one event. Existing rows get it at
the next sync.
"""

import sqlalchemy as sa
from alembic import op

revision = "0028"
down_revision = "0027"
branch_labels = None
depends_on = None


def upgrade() -> None:
    """Add the uid column, empty for the events cached so far."""
    with op.batch_alter_table("calendar_entries", schema=None) as batch_op:
        batch_op.add_column(
            sa.Column("uid", sa.String(length=1024), nullable=False, server_default="")
        )


def downgrade() -> None:
    """Remove the uid column."""
    with op.batch_alter_table("calendar_entries", schema=None) as batch_op:
        batch_op.drop_column("uid")
