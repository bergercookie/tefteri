"""User and login session models."""

import uuid
from datetime import datetime

from sqlalchemy import JSON, Boolean, DateTime, ForeignKey, Integer, String, Uuid, false, text
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
    random_time_on_date_drop: Mapped[bool] = mapped_column(
        Boolean, default=False, server_default=false()
    )
    """A date-only drop on the calendar gets a random time of day instead of staying all-day."""
    checklists: Mapped[dict[str, list[str]]] = mapped_column(
        JSON, default=dict, server_default=text("'{}'")
    )
    """The user's planning checklists: the items for ``week``, ``month`` and ``year``."""
    checklist_sources: Mapped[dict[str, str]] = mapped_column(
        JSON, default=dict, server_default=text("'{}'")
    )
    """The note path that each checklist comes from, by period type, when it is read-only."""
    default_reminder_minutes: Mapped[int] = mapped_column(
        Integer, default=15, server_default=text("15")
    )
    """How many minutes before its due time a new task reminder fires."""
    default_event_container_id: Mapped[uuid.UUID | None] = mapped_column(
        Uuid,
        ForeignKey(
            "source_containers.id",
            ondelete="SET NULL",
            name="fk_users_default_event_container_id",
            use_alter=True,
        ),
        nullable=True,
        default=None,
    )
    """The calendar that a new event starts in, or ``None`` to start in the last one used."""


class AuthSession(IdMixin, CreatedMixin, Base):
    """A login session; only the SHA-256 of the bearer token is stored."""

    __tablename__ = "auth_sessions"

    user_id: Mapped[uuid.UUID] = mapped_column(Uuid, ForeignKey("users.id", ondelete="CASCADE"))
    token_hash: Mapped[str] = mapped_column(String(64), unique=True)
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    lifetime_seconds: Mapped[int | None] = mapped_column(Integer, nullable=True, default=None)
    """How long the session lasts after each use; ``None`` for a session from before renewal."""
