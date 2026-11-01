"""User and login session models."""

import uuid
from datetime import datetime

from sqlalchemy import Boolean, DateTime, ForeignKey, String, Uuid
from sqlalchemy.orm import Mapped, mapped_column

from tefteri.db.base import Base, CreatedMixin, IdMixin


class User(IdMixin, CreatedMixin, Base):
    """A tefteri user."""

    __tablename__ = "users"
    username: Mapped[str] = mapped_column(String(150), unique=True)
    password_hash: Mapped[str | None] = mapped_column(String(255), nullable=True)
    is_admin: Mapped[bool] = mapped_column(Boolean, default=False)
    timezone: Mapped[str] = mapped_column(String(64), default="UTC")
    disabled: Mapped[bool] = mapped_column(Boolean, default=False)


class AuthSession(IdMixin, CreatedMixin, Base):
    """A login session; only the SHA-256 of the bearer token is stored."""

    __tablename__ = "auth_sessions"

    user_id: Mapped[uuid.UUID] = mapped_column(Uuid, ForeignKey("users.id", ondelete="CASCADE"))
    token_hash: Mapped[str] = mapped_column(String(64), unique=True)
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
