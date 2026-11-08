"""Connection to an external app and its sub-scopes."""

import uuid
from datetime import datetime
from typing import Any

from sqlalchemy import JSON, DateTime, ForeignKey, String, Text, UniqueConstraint, Uuid
from sqlalchemy.orm import Mapped, mapped_column

from tefteri.db.base import Base, CreatedMixin, IdMixin
from tefteri.domain.enums import ConnectionStatus


class Connection(IdMixin, CreatedMixin, Base):
    """A user's connection to one task, calendar or note application."""

    __tablename__ = "connections"

    user_id: Mapped[uuid.UUID] = mapped_column(
        Uuid, ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    kind: Mapped[str] = mapped_column(String(16))
    provider: Mapped[str] = mapped_column(String(32))
    display_name: Mapped[str] = mapped_column(String(150))
    default_context: Mapped[str] = mapped_column(String(8), default="life")
    encrypted_credentials: Mapped[str | None] = mapped_column(Text, nullable=True)
    settings: Mapped[dict[str, Any]] = mapped_column(JSON, default=dict)
    status: Mapped[str] = mapped_column(String(32), default=ConnectionStatus.OK.value)
    last_sync_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    last_sync_outcome: Mapped[str | None] = mapped_column(String(255), nullable=True)
    sync_cursor: Mapped[str | None] = mapped_column(String(255), nullable=True)


class SourceContainer(IdMixin, Base):
    """A project, calendar or note subtree inside a connection."""

    __tablename__ = "source_containers"
    __table_args__ = (UniqueConstraint("connection_id", "remote_id"),)

    user_id: Mapped[uuid.UUID] = mapped_column(
        Uuid, ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    connection_id: Mapped[uuid.UUID] = mapped_column(
        Uuid, ForeignKey("connections.id", ondelete="CASCADE"), index=True
    )
    remote_id: Mapped[str] = mapped_column(String(255))
    name: Mapped[str] = mapped_column(String(255))
    context: Mapped[str | None] = mapped_column(String(8), nullable=True)
    parent_remote_id: Mapped[str | None] = mapped_column(String(255), nullable=True)
    """``remote_id`` of the project this one is nested in (a Vikunja subproject)."""
