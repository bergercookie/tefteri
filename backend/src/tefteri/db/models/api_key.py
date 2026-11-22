"""API keys: long-lived tokens for tools such as an MCP client."""

import uuid
from datetime import datetime

from sqlalchemy import DateTime, ForeignKey, String, Uuid
from sqlalchemy.orm import Mapped, mapped_column

from tefteri.db.base import Base, CreatedMixin, IdMixin


class ApiKey(IdMixin, CreatedMixin, Base):
    """One API key of a user. Only the SHA-256 of the key is stored; it is shown once.

    A key acts as its user, on the same data, until the user revokes (deletes) it. It cannot
    change passwords, manage users or make other keys.
    """

    __tablename__ = "api_keys"

    user_id: Mapped[uuid.UUID] = mapped_column(
        Uuid, ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    name: Mapped[str] = mapped_column(String(80))
    """What the user calls the key, for example the tool that uses it."""
    prefix: Mapped[str] = mapped_column(String(16))
    """The first characters of the key. They are not secret, and they help to tell keys apart."""
    token_hash: Mapped[str] = mapped_column(String(64), unique=True)
    last_used_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
