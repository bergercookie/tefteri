"""Period reviews: planned versus completed, snapshotted when generated."""

import uuid
from datetime import datetime
from typing import Any

from sqlalchemy import JSON, DateTime, ForeignKey, Integer, Uuid
from sqlalchemy.orm import Mapped, mapped_column

from tefteri.db.base import Base, IdMixin


class PeriodReview(IdMixin, Base):
    """The review of one plan, computed from goals and tasks at ``generated_at`` and kept as is.

    ``items`` holds the planned goals and tasks with their state at generation time and
    ``carried_over`` the ids of the ones that were not completed.
    """

    __tablename__ = "period_reviews"

    user_id: Mapped[uuid.UUID] = mapped_column(
        Uuid, ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    plan_id: Mapped[uuid.UUID] = mapped_column(
        Uuid, ForeignKey("plans.id", ondelete="CASCADE"), unique=True
    )
    generated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    planned_count: Mapped[int] = mapped_column(Integer)
    completed_count: Mapped[int] = mapped_column(Integer)
    carried_over: Mapped[list[str]] = mapped_column(JSON, default=list)
    items: Mapped[list[dict[str, Any]]] = mapped_column(JSON, default=list)
    retrospective_note_id: Mapped[uuid.UUID | None] = mapped_column(
        Uuid, ForeignKey("notes.id", ondelete="SET NULL"), nullable=True
    )
