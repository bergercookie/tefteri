"""The stored work category of a completed task (spec 005)."""

import uuid
from datetime import date, datetime

from sqlalchemy import (
    Boolean,
    CheckConstraint,
    Date,
    DateTime,
    ForeignKey,
    Index,
    String,
    UniqueConstraint,
    Uuid,
)
from sqlalchemy.orm import Mapped, mapped_column

from tefteri.db.base import Base, IdMixin


class TaskCategory(IdMixin, Base):
    """One row per task that tefteri saw as completed.

    The recorder writes it when the task is first seen as completed, and replaces it in place
    when a reopened task is completed again. It is never edited otherwise: a relabel, a changed
    commitment, a rename or a move never changes it (FR-007). A row counts only while the task is
    done and ``completed_at`` equals the completion time of the task. ``hidden`` is the ignored
    count, not a work category.
    """

    __tablename__ = "task_categories"
    __table_args__ = (
        UniqueConstraint("task_id", name="uq_task_categories_task_id"),
        CheckConstraint(
            "category IN ('goal_aligned','maintenance','off_plan','hidden')",
            name="ck_task_categories_category",
        ),
        Index("ix_task_categories_user_day_category", "user_id", "completed_on", "category"),
        Index("ix_task_categories_user_category_completed", "user_id", "category", "completed_at"),
        Index("ix_task_categories_project_id", "project_id"),
    )

    user_id: Mapped[uuid.UUID] = mapped_column(Uuid, ForeignKey("users.id", ondelete="CASCADE"))
    task_id: Mapped[uuid.UUID] = mapped_column(Uuid, ForeignKey("tasks.id", ondelete="CASCADE"))
    completed_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    """The completion time this row was decided for."""
    completed_on: Mapped[date] = mapped_column(Date)
    """The local day of ``completed_at`` in the time zone of the user at the decision. Stored."""
    category: Mapped[str] = mapped_column(String(12))
    reason: Mapped[str] = mapped_column(String(24))
    unsorted: Mapped[bool] = mapped_column(Boolean)
    project_id: Mapped[uuid.UUID | None] = mapped_column(
        Uuid, ForeignKey("project_labels.id", ondelete="SET NULL"), nullable=True
    )
    project_name: Mapped[str | None] = mapped_column(String(255), nullable=True)
    project_label: Mapped[str | None] = mapped_column(String(16), nullable=True)
    plan_id: Mapped[uuid.UUID | None] = mapped_column(
        Uuid, ForeignKey("weekly_plans.id", ondelete="SET NULL"), nullable=True
    )
    decided_via: Mapped[str] = mapped_column(String(8))  # sync | app
    decided_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
