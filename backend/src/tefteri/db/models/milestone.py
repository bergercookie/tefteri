"""Milestone projects: planning data that sits next to the label of a project (spec 004)."""

import uuid
from datetime import date, datetime

from sqlalchemy import (
    JSON,
    Boolean,
    Date,
    DateTime,
    ForeignKey,
    Index,
    Integer,
    String,
    Uuid,
)
from sqlalchemy.orm import Mapped, mapped_column

from tefteri.db.base import Base, CreatedMixin, IdMixin, utcnow


class Milestone(IdMixin, CreatedMixin, Base):
    """One row per milestone project, made the first time the weekly flow touches the project.

    No row means state ``active``, rollover count 0 and no done-state. The row hangs on the
    label row of the project (``project_labels``), which is never deleted, so a finished or
    orphaned milestone keeps its history. ``done_on``, ``done_by`` and ``done_theme_*`` are all
    set, or all empty, together with the state ``done``. A change of theme never writes them.
    """

    __tablename__ = "milestones"
    __table_args__ = (Index("ix_milestones_user_state", "user_id", "state"),)

    user_id: Mapped[uuid.UUID] = mapped_column(Uuid, ForeignKey("users.id", ondelete="CASCADE"))
    project_id: Mapped[uuid.UUID] = mapped_column(
        Uuid, ForeignKey("project_labels.id", ondelete="CASCADE"), unique=True
    )
    done_state: Mapped[str | None] = mapped_column(String(255), nullable=True)
    """One sentence that says when the milestone is finished."""
    state: Mapped[str] = mapped_column(String(8), default="active")
    """``active``, ``parked``, ``closed`` or ``done``."""
    state_changed_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)
    rollover_count: Mapped[int] = mapped_column(Integer, default=0)
    """Raised only by a recommit decision, never reset. Equals its ``milestone_rollovers`` rows."""
    done_on: Mapped[date | None] = mapped_column(Date, nullable=True)
    """The local day it became done: the day of its last closed task, or the day of the user."""
    done_by: Mapped[str | None] = mapped_column(String(4), nullable=True)  # auto | user
    done_theme_id: Mapped[uuid.UUID | None] = mapped_column(
        Uuid, ForeignKey("project_labels.id", ondelete="SET NULL"), nullable=True
    )
    done_theme_name: Mapped[str | None] = mapped_column(String(255), nullable=True)
    """A copy of the theme name at that moment. ``None`` with no theme."""


class MilestoneRollover(IdMixin, Base):
    """One recommit of a milestone. Rows are only added, never edited or deleted."""

    __tablename__ = "milestone_rollovers"

    milestone_id: Mapped[uuid.UUID] = mapped_column(
        Uuid, ForeignKey("milestones.id", ondelete="CASCADE"), index=True
    )
    plan_project_id: Mapped[uuid.UUID | None] = mapped_column(
        Uuid, ForeignKey("weekly_plan_projects.id", ondelete="SET NULL"), nullable=True
    )
    """The reviewed entry that made the decision."""
    from_week: Mapped[date] = mapped_column(Date)
    to_week: Mapped[date] = mapped_column(Date)
    expected: Mapped[bool] = mapped_column(Boolean, default=False)
    """The marker of this one event: "this was bigger than a week"."""
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)


class MilestoneClosure(IdMixin, Base):
    """The log of one close and return. It makes a retry safe and the undo possible.

    ``moved`` is a list of ``{"task_id", "remote_id", "from_remote_project", "version"}``. One
    entry is added after each successful move; ``version`` is the task version after the move.
    """

    __tablename__ = "milestone_closures"

    milestone_id: Mapped[uuid.UUID] = mapped_column(
        Uuid, ForeignKey("milestones.id", ondelete="CASCADE"), index=True
    )
    plan_project_id: Mapped[uuid.UUID | None] = mapped_column(
        Uuid, ForeignKey("weekly_plan_projects.id", ondelete="SET NULL"), nullable=True
    )
    theme_project_id: Mapped[uuid.UUID | None] = mapped_column(
        Uuid, ForeignKey("project_labels.id", ondelete="SET NULL"), nullable=True
    )
    """The project that got the tasks."""
    theme_name: Mapped[str] = mapped_column(String(255))
    status: Mapped[str] = mapped_column(String(8))  # moving | closed | reopened
    moved: Mapped[list[dict[str, str]]] = mapped_column(JSON, default=list)
    started_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)
    finished_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    reopened_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
