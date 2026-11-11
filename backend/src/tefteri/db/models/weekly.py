"""Weekly planning sessions: the projects chosen for a week and how the week went."""

import uuid
from datetime import date, datetime

from sqlalchemy import (
    JSON,
    Boolean,
    Date,
    DateTime,
    ForeignKey,
    Integer,
    String,
    Text,
    UniqueConstraint,
    Uuid,
)
from sqlalchemy.orm import Mapped, mapped_column

from tefteri.db.base import Base, IdMixin


class WeeklyPlan(IdMixin, Base):
    """The plan of one week (Monday start): the milestones committed to, then the look-back.

    ``status`` is ``draft`` while the user plans and ``committed`` after the commit. The
    look-back (``reviewed_at``) happens at the start of the next week's planning.
    """

    __tablename__ = "weekly_plans"
    __table_args__ = (UniqueConstraint("user_id", "week_start"),)

    user_id: Mapped[uuid.UUID] = mapped_column(
        Uuid, ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    week_start: Mapped[date] = mapped_column(Date)
    status: Mapped[str] = mapped_column(String(12), default="draft")  # draft | committed
    committed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    retro_skipped: Mapped[bool] = mapped_column(Boolean, default=False)
    """The user chose to plan the *next* week without looking back at this one's predecessor."""
    reviewed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    reflection: Mapped[str] = mapped_column(Text, default="")


class WeeklyPlanProject(IdMixin, Base):
    """The weekly commitment of one milestone project (spec 004).

    ``committed_task_ids`` is the list of tasks planned for the week when the plan was
    committed. The ``reviewed_*`` columns are the counts that the look-back stored, ``decision``
    is what the review decided. An entry from before spec 004 has no ``milestone_id`` and keeps
    ``leftover_action``; it is read under the new names and never rewritten.
    """

    __tablename__ = "weekly_plan_projects"
    __table_args__ = (
        UniqueConstraint("plan_id", "container_id"),
        UniqueConstraint("plan_id", "milestone_id"),
    )

    plan_id: Mapped[uuid.UUID] = mapped_column(
        Uuid, ForeignKey("weekly_plans.id", ondelete="CASCADE"), index=True
    )
    container_id: Mapped[uuid.UUID | None] = mapped_column(
        Uuid, ForeignKey("source_containers.id", ondelete="SET NULL"), nullable=True
    )
    name: Mapped[str] = mapped_column(String(255))
    position: Mapped[int] = mapped_column(Integer, default=0)
    created_here: Mapped[bool] = mapped_column(Boolean, default=False)
    committed_task_ids: Mapped[list[str]] = mapped_column(JSON, default=list)
    parked_task_ids: Mapped[list[str]] = mapped_column(JSON, default=list)
    """Tasks set aside for this week's plan: the spread and the commit leave them out."""
    outcome: Mapped[str | None] = mapped_column(String(12), nullable=True)  # done | not_done
    leftover_action: Mapped[str | None] = mapped_column(String(8), nullable=True)  # carry|backlog
    reviewed_committed: Mapped[int | None] = mapped_column(Integer, nullable=True)
    reviewed_done: Mapped[int | None] = mapped_column(Integer, nullable=True)
    milestone_id: Mapped[uuid.UUID | None] = mapped_column(
        Uuid, ForeignKey("milestones.id", ondelete="SET NULL"), nullable=True, index=True
    )
    """``None`` for an entry from before spec 004."""
    theme_project_id: Mapped[uuid.UUID | None] = mapped_column(
        Uuid, ForeignKey("project_labels.id", ondelete="SET NULL"), nullable=True
    )
    """The parent theme at the time of the commitment."""
    theme_name: Mapped[str | None] = mapped_column(String(255), nullable=True)
    """A copy of its name. ``None`` means no theme, or an entry from before spec 004."""
    decision: Mapped[str | None] = mapped_column(String(12), nullable=True)
    """``recommit``, ``park``, ``close`` or ``decide_later``. ``None`` before the review."""
    expected_rollover: Mapped[bool | None] = mapped_column(Boolean, nullable=True)
    """The marker given with a ``recommit``. Copied to the rollover event."""
    decided_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
