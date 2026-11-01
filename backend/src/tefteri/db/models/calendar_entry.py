"""Cached mirror of a calendar event. Scheduled tasks are never stored as entries."""

import uuid
from datetime import datetime

from sqlalchemy import Boolean, DateTime, ForeignKey, String, Text, UniqueConstraint, Uuid
from sqlalchemy.orm import Mapped, mapped_column

from tefteri.db.base import Base, IdMixin
from tefteri.domain.enums import SyncState


class CalendarEntry(IdMixin, Base):
    """A calendar event copy."""

    __tablename__ = "calendar_entries"
    __table_args__ = (UniqueConstraint("connection_id", "remote_id"),)

    user_id: Mapped[uuid.UUID] = mapped_column(
        Uuid, ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    connection_id: Mapped[uuid.UUID] = mapped_column(
        Uuid, ForeignKey("connections.id", ondelete="CASCADE"), index=True
    )
    container_id: Mapped[uuid.UUID | None] = mapped_column(
        Uuid, ForeignKey("source_containers.id", ondelete="SET NULL"), nullable=True
    )
    remote_id: Mapped[str] = mapped_column(String(500))
    title: Mapped[str] = mapped_column(String(500))
    start: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    end: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    all_day: Mapped[bool] = mapped_column(Boolean, default=False)
    recurrence: Mapped[str | None] = mapped_column(Text, nullable=True)  # opaque rule
    location: Mapped[str] = mapped_column(String(500), default="")
    context: Mapped[str | None] = mapped_column(String(8), nullable=True)
    remote_version: Mapped[str] = mapped_column(String(255), default="")
    sync_state: Mapped[str] = mapped_column(String(20), default=SyncState.SYNCED.value)
