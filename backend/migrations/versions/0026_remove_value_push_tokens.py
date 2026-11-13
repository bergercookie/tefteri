"""remove value push tokens

Revision ID: 0026
Revises: 0025

The inbound value push and its token are gone with the Push token action of the annual plan.
No other table points at ``value_push_tokens``.
"""

import sqlalchemy as sa
from alembic import op

revision = "0026"
down_revision = "0025"
branch_labels = None
depends_on = None


def upgrade() -> None:
    """Drop the push-token table."""
    op.drop_table("value_push_tokens")


def downgrade() -> None:
    """Recreate the empty push-token table."""
    op.create_table(
        "value_push_tokens",
        sa.Column("user_id", sa.Uuid(), nullable=False),
        sa.Column("token_hash", sa.String(length=64), nullable=False),
        sa.Column("hint", sa.String(length=4), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("last_used_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("token_hash", name="uq_value_push_tokens_token_hash"),
        sa.UniqueConstraint("user_id", name="uq_value_push_tokens_user_id"),
    )
