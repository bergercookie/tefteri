"""Sync run history and conflicts."""

import uuid
from datetime import datetime
from typing import Any

from sqlalchemy import JSON, DateTime, ForeignKey, String, Text, Uuid
from sqlalchemy.orm import Mapped, mapped_column

from tefteri.db.base import Base, CreatedMixin, IdMixin


class SyncRun(IdMixin, Base):
    """One sync of one connection."""

    __tablename__ = "sync_runs"

    user_id: Mapped[uuid.UUID] = mapped_column(
        Uuid, ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    connection_id: Mapped[uuid.UUID] = mapped_column(
        Uuid, ForeignKey("connections.id", ondelete="CASCADE"), index=True
    )
    started_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    finished_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    outcome: Mapped[str] = mapped_column(String(32))
    counts: Mapped[dict[str, Any]] = mapped_column(JSON, default=dict)
    error: Mapped[str | None] = mapped_column(Text, nullable=True)


class Conflict(IdMixin, CreatedMixin, Base):
    """A change made both locally and remotely. Never resolved automatically."""

    __tablename__ = "conflicts"

    user_id: Mapped[uuid.UUID] = mapped_column(
        Uuid, ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    entity_type: Mapped[str] = mapped_column(String(16))
    entity_id: Mapped[uuid.UUID] = mapped_column(Uuid)
    local_snapshot: Mapped[dict[str, Any]] = mapped_column(JSON)
    remote_snapshot: Mapped[dict[str, Any]] = mapped_column(JSON)
    resolved_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    resolution: Mapped[str | None] = mapped_column(String(16), nullable=True)
