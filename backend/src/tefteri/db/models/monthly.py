"""Monthly focus and immutable review snapshot persistence models."""

import uuid
from datetime import date, datetime

from sqlalchemy import (
    JSON,
    CheckConstraint,
    Date,
    DateTime,
    ForeignKey,
    Integer,
    String,
    UniqueConstraint,
    Uuid,
)
from sqlalchemy.orm import Mapped, mapped_column

from tefteri.db.base import Base, CreatedMixin, IdMixin, utcnow

_FIRST_OF_MONTH = "CAST(substr(CAST(month AS VARCHAR), 9, 2) AS INTEGER) = 1"


class MonthlyFocus(IdMixin, CreatedMixin, Base):
    """The saved monthly focus header for one user and first-of-month date."""

    __tablename__ = "monthly_focuses"
    __table_args__ = (
        UniqueConstraint("user_id", "month", name="uq_monthly_focuses_user_month"),
        CheckConstraint(_FIRST_OF_MONTH, name="ck_monthly_focuses_first_of_month"),
    )

    user_id: Mapped[uuid.UUID] = mapped_column(
        Uuid, ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    month: Mapped[date] = mapped_column(Date, nullable=False)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=utcnow, onupdate=utcnow
    )


class MonthlyFocusEntry(IdMixin, CreatedMixin, Base):
    """One theme entry in a monthly focus, including its count window and leave state."""

    __tablename__ = "monthly_focus_entries"
    __table_args__ = (
        UniqueConstraint("focus_id", "project_id", name="uq_monthly_focus_entries_focus_project"),
        CheckConstraint("target IS NULL OR target >= 0", name="ck_monthly_focus_entries_target"),
        CheckConstraint(
            "(left_on IS NULL) = (left_reason IS NULL)",
            name="ck_monthly_focus_entries_left_state",
        ),
    )

    focus_id: Mapped[uuid.UUID] = mapped_column(
        Uuid, ForeignKey("monthly_focuses.id", ondelete="CASCADE"), index=True
    )
    project_id: Mapped[uuid.UUID] = mapped_column(
        Uuid, ForeignKey("project_labels.id", ondelete="CASCADE"), index=True
    )
    name: Mapped[str] = mapped_column(String(255), nullable=False)
    target: Mapped[int | None] = mapped_column(Integer, nullable=True)
    counts_from: Mapped[date] = mapped_column(Date, nullable=False)
    left_on: Mapped[date | None] = mapped_column(Date, nullable=True)
    left_reason: Mapped[str | None] = mapped_column(String(12), nullable=True)
    position: Mapped[int] = mapped_column(Integer, nullable=False)


class FocusChange(IdMixin, Base):
    """An append-only record of one user or undo change to a monthly focus."""

    __tablename__ = "focus_changes"

    focus_id: Mapped[uuid.UUID] = mapped_column(
        Uuid, ForeignKey("monthly_focuses.id", ondelete="CASCADE"), index=True
    )
    kind: Mapped[str] = mapped_column(String(8), nullable=False)
    changed_on: Mapped[date] = mapped_column(Date, nullable=False)
    out_entry_id: Mapped[uuid.UUID | None] = mapped_column(
        Uuid, ForeignKey("monthly_focus_entries.id", ondelete="SET NULL"), nullable=True
    )
    in_entry_id: Mapped[uuid.UUID | None] = mapped_column(
        Uuid, ForeignKey("monthly_focus_entries.id", ondelete="SET NULL"), nullable=True
    )
    out_project_id: Mapped[uuid.UUID | None] = mapped_column(
        Uuid, ForeignKey("project_labels.id", ondelete="SET NULL"), nullable=True
    )
    in_project_id: Mapped[uuid.UUID | None] = mapped_column(
        Uuid, ForeignKey("project_labels.id", ondelete="SET NULL"), nullable=True
    )
    out_name: Mapped[str | None] = mapped_column(String(255), nullable=True)
    in_name: Mapped[str | None] = mapped_column(String(255), nullable=True)
    target_before: Mapped[int | None] = mapped_column(Integer, nullable=True)
    target_after: Mapped[int | None] = mapped_column(Integer, nullable=True)
    batch_id: Mapped[uuid.UUID] = mapped_column(Uuid, index=True, nullable=False)
    undoes_batch_id: Mapped[uuid.UUID | None] = mapped_column(Uuid, index=True, nullable=True)
    source: Mapped[str] = mapped_column(String(8), nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)


class MonthlyReview(IdMixin, CreatedMixin, Base):
    """Mutable pointer to the current immutable snapshot version for one user's month."""

    __tablename__ = "monthly_reviews"
    __table_args__ = (
        UniqueConstraint("user_id", "month", name="uq_monthly_reviews_user_month"),
        CheckConstraint(_FIRST_OF_MONTH, name="ck_monthly_reviews_first_of_month"),
    )

    user_id: Mapped[uuid.UUID] = mapped_column(
        Uuid, ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    month: Mapped[date] = mapped_column(Date, nullable=False)
    current_version: Mapped[int] = mapped_column(Integer, nullable=False)
    current_changed_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)


class MonthlyReviewSnapshot(IdMixin, Base):
    """One immutable JSON payload and trace of a saved monthly review version."""

    __tablename__ = "monthly_review_snapshots"
    __table_args__ = (
        UniqueConstraint("review_id", "version", name="uq_monthly_review_snapshots_review_version"),
    )

    review_id: Mapped[uuid.UUID] = mapped_column(
        Uuid, ForeignKey("monthly_reviews.id", ondelete="CASCADE"), index=True
    )
    version: Mapped[int] = mapped_column(Integer, nullable=False)
    schema_version: Mapped[int] = mapped_column(Integer, nullable=False)
    payload: Mapped[dict[str, object]] = mapped_column(JSON, nullable=False)
    values_written: Mapped[list[dict[str, str]]] = mapped_column(JSON, nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)
