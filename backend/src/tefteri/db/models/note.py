"""Cached mirror of a note in the connected note app."""

import uuid
from datetime import date

from sqlalchemy import Date, ForeignKey, String, Text, UniqueConstraint, Uuid
from sqlalchemy.orm import Mapped, mapped_column

from tefteri.db.base import Base, IdMixin
from tefteri.domain.enums import SyncState


class Note(IdMixin, Base):
    """A note copy. ``kind`` is daily, custom, process or retrospective."""

    __tablename__ = "notes"
    __table_args__ = (UniqueConstraint("connection_id", "remote_id"),)

    user_id: Mapped[uuid.UUID] = mapped_column(
        Uuid, ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    connection_id: Mapped[uuid.UUID] = mapped_column(
        Uuid, ForeignKey("connections.id", ondelete="CASCADE"), index=True
    )
    remote_id: Mapped[str] = mapped_column(String(255))
    kind: Mapped[str] = mapped_column(String(16), default="custom")
    title: Mapped[str] = mapped_column(String(500))
    body: Mapped[str] = mapped_column(Text, default="")
    note_date: Mapped[date | None] = mapped_column(Date, nullable=True)
    context: Mapped[str | None] = mapped_column(String(8), nullable=True)
    remote_version: Mapped[str] = mapped_column(String(255), default="")
    sync_state: Mapped[str] = mapped_column(String(20), default=SyncState.SYNCED.value)
