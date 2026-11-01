"""Cached mirror of a task in a connected task app."""

import uuid
from datetime import datetime

from sqlalchemy import Boolean, DateTime, ForeignKey, String, Text, UniqueConstraint, Uuid
from sqlalchemy.orm import Mapped, mapped_column

from tefteri.db.base import Base, IdMixin
from tefteri.domain.enums import SyncState


class Task(IdMixin, Base):
    """A task copy. Effective context = task override, else container, else connection default."""

    __tablename__ = "tasks"
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
    remote_id: Mapped[str] = mapped_column(String(255))
    title: Mapped[str] = mapped_column(String(500))
    description: Mapped[str] = mapped_column(Text, default="")
    status: Mapped[str] = mapped_column(String(8), default="open")  # 'open' | 'done'
    due_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    scheduled_start: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    scheduled_end: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    all_day: Mapped[bool] = mapped_column(Boolean, default=False)
    context: Mapped[str | None] = mapped_column(String(8), nullable=True)
    goal_id: Mapped[uuid.UUID | None] = mapped_column(Uuid, nullable=True)
    remote_version: Mapped[str] = mapped_column(String(255), default="")
    sync_state: Mapped[str] = mapped_column(String(20), default=SyncState.SYNCED.value)
