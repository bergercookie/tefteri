"""user setting: the calendar that a new event starts in

Revision ID: 0030
Revises: 0029
"""

import sqlalchemy as sa
from alembic import op

revision = "0030"
down_revision = "0029"
branch_labels = None
depends_on = None


def upgrade() -> None:
    """Add the column; it is empty until the user chooses a calendar."""
    with op.batch_alter_table("users") as batch:
        batch.add_column(sa.Column("default_event_container_id", sa.Uuid(), nullable=True))
        batch.create_foreign_key(
            "fk_users_default_event_container_id",
            "source_containers",
            ["default_event_container_id"],
            ["id"],
            ondelete="SET NULL",
        )


def downgrade() -> None:
    """Remove the column."""
    with op.batch_alter_table("users") as batch:
        batch.drop_constraint("fk_users_default_event_container_id", type_="foreignkey")
        batch.drop_column("default_event_container_id")
