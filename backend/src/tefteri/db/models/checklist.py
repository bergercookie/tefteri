"""Which items of a planning checklist the user has ticked, for one period."""

import uuid
from datetime import date

from sqlalchemy import JSON, Date, ForeignKey, String, UniqueConstraint, Uuid
from sqlalchemy.orm import Mapped, mapped_column

from tefteri.db.base import Base, IdMixin


class ChecklistProgress(IdMixin, Base):
    """The ticks of one checklist in one period (the week, month or year that starts on a date).

    The list itself is a setting of the user. The ticks belong to the period, so the next
    period starts with a clean list, and an old period keeps what was ticked in it. ``checked``
    holds the texts of the ticked items.
    """

    __tablename__ = "checklist_progress"
    __table_args__ = (UniqueConstraint("user_id", "period_type", "period_start"),)

    user_id: Mapped[uuid.UUID] = mapped_column(
        Uuid, ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    period_type: Mapped[str] = mapped_column(String(5))  # week | month | year
    period_start: Mapped[date] = mapped_column(Date)
    checked: Mapped[list[str]] = mapped_column(JSON, default=list)
