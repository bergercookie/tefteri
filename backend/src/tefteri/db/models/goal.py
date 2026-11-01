"""Goals and plans."""

import uuid
from datetime import date

from sqlalchemy import Date, ForeignKey, String, Text, Uuid
from sqlalchemy.orm import Mapped, mapped_column

from tefteri.db.base import Base, IdMixin


class Goal(IdMixin, Base):
    """A goal for a year, month or week. ``progress`` is computed, never stored."""

    __tablename__ = "goals"

    user_id: Mapped[uuid.UUID] = mapped_column(
        Uuid, ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    parent_id: Mapped[uuid.UUID | None] = mapped_column(
        Uuid, ForeignKey("goals.id", ondelete="CASCADE"), nullable=True, index=True
    )
    period_type: Mapped[str] = mapped_column(String(8))  # 'year' | 'month' | 'week'
    period_start: Mapped[date] = mapped_column(Date)
    title: Mapped[str] = mapped_column(String(500))
    description: Mapped[str] = mapped_column(Text, default="")
    context: Mapped[str] = mapped_column(String(8), default="life")
    status: Mapped[str] = mapped_column(String(8), default="active")  # active|done|dropped


class Plan(IdMixin, Base):
    """A plan groups the goals of one period and is kept after the period ends."""

    __tablename__ = "plans"

    user_id: Mapped[uuid.UUID] = mapped_column(
        Uuid, ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    period_type: Mapped[str] = mapped_column(String(8))
    period_start: Mapped[date] = mapped_column(Date)
    title: Mapped[str] = mapped_column(String(500))
    summary: Mapped[str] = mapped_column(Text, default="")
