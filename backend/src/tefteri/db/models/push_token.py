"""The inbound value push token of a user (spec 006, FR-010, R-07).

One token per user, only its SHA-256 digest is stored. The plain token is shown once when it
is issued or rotated.
"""

import uuid
from datetime import datetime

import sqlalchemy as sa
from sqlalchemy import DateTime, ForeignKey, String, Uuid
from sqlalchemy.orm import Mapped, mapped_column

from tefteri.db.base import Base, IdMixin, utcnow


class ValuePushToken(IdMixin, Base):
    """The push token of one user. Works only on the push route (spec 006)."""

    __tablename__ = "value_push_tokens"

    user_id: Mapped[uuid.UUID] = mapped_column(
        Uuid, ForeignKey("users.id", ondelete="CASCADE")
    )
    token_hash: Mapped[str] = mapped_column(String(64))
    """The SHA-256 digest of the token. The token itself is never stored."""
    hint: Mapped[str] = mapped_column(String(4))
    """The last four characters of the token, shown in the settings."""
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)
    last_used_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    """Set only by an accepted push."""

    __table_args__ = (
        sa.UniqueConstraint("user_id", name="uq_value_push_tokens_user_id"),
        sa.UniqueConstraint("token_hash", name="uq_value_push_tokens_token_hash"),
    )
