"""Goals and plans.

A goal belongs to one period. Since spec 006 the annual plan is the only planning flow that
owns goals: a row with ``period_type = 'year'`` is an annual goal, and month or week rows are
read-only history (spec 006, FR-022).
"""

import uuid
from datetime import date, datetime

import sqlalchemy as sa
from sqlalchemy import Date, DateTime, ForeignKey, String, Text, Uuid
from sqlalchemy.orm import Mapped, mapped_column

from tefteri.db.base import Base, IdMixin, utcnow


class Goal(IdMixin, Base):
    """A goal for a planning year.

    An annual goal is ``active`` or ``retired``; a legacy year row can still be ``done``
    (treated as active). Month and week rows are history: they keep the old statuses
    (``active``, ``done``, ``dropped``) and have no write route (spec 006, FR-023).
    """

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
    criteria: Mapped[str] = mapped_column(Text, default="")
    """The old criteria text (before annual planning). Offered as a key result metric
    suggestion while the goal has no key result (spec 006, FR-024)."""
    status: Mapped[str] = mapped_column(String(8), default="active")  # active|done|dropped|retired
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        default=utcnow,
        server_default=sa.text("CURRENT_TIMESTAMP"),
        nullable=False,
    )
    retired_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    retired_reason: Mapped[str | None] = mapped_column(Text, nullable=True)
    position: Mapped[int] = mapped_column(default=0, server_default=sa.text("0"), nullable=False)

    __table_args__ = (
        sa.Index("ix_goals_user_period", "user_id", "period_type", "period_start"),
    )


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
