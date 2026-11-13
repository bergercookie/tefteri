"""Key results, their value series, their theme links and the plan history (spec 006)."""

import uuid
from datetime import date, datetime

import sqlalchemy as sa
from sqlalchemy import (
    CheckConstraint,
    Date,
    DateTime,
    Float,
    ForeignKey,
    Index,
    SmallInteger,
    String,
    Text,
    Uuid,
)
from sqlalchemy.orm import Mapped, mapped_column

from tefteri.db.base import Base, IdMixin, utcnow


class KeyResult(IdMixin, Base):
    """One measurable key result of an annual goal (spec 006).

    The current value is derived from the value series, never stored (R-02). A retired key
    result keeps its series and its history; ``slot`` frees its place while it is retired.
    """

    __tablename__ = "key_results"

    user_id: Mapped[uuid.UUID] = mapped_column(
        Uuid, ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    goal_id: Mapped[uuid.UUID] = mapped_column(
        Uuid, ForeignKey("goals.id", ondelete="CASCADE"), index=True
    )
    year: Mapped[int] = mapped_column(nullable=False)
    """The planning year of the goal, copied at creation."""
    metric: Mapped[str] = mapped_column(String(500), nullable=False)
    kind: Mapped[str] = mapped_column(String(8), default="number", server_default="number")
    """``number`` or ``yes_no``. A yes/no key result stores 0 or 1 as its value."""
    start_value: Mapped[float] = mapped_column(Float, nullable=False)
    target: Mapped[float] = mapped_column(Float, nullable=False)
    deadline: Mapped[date] = mapped_column(Date, nullable=False)
    update_source: Mapped[str] = mapped_column(String(9), nullable=False)  # manual|automatic
    status: Mapped[str] = mapped_column(String(8), default="active", nullable=False)
    slot: Mapped[int | None] = mapped_column(SmallInteger, nullable=True)
    """1 to 3 while active, ``None`` when retired (R-03). Unique with ``goal_id``."""
    position: Mapped[int] = mapped_column(default=0, nullable=False)
    retired_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    retired_reason: Mapped[str | None] = mapped_column(Text, nullable=True)
    seeded_from_id: Mapped[uuid.UUID | None] = mapped_column(
        Uuid, ForeignKey("key_results.id", ondelete="SET NULL"), nullable=True
    )
    """The key result of year N that this one was copied from (for the history and spec 008)."""
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=utcnow, onupdate=utcnow
    )

    __table_args__ = (
        sa.UniqueConstraint("goal_id", "slot", name="uq_key_results_goal_slot"),
        CheckConstraint("kind IN ('number', 'yes_no')", name="ck_key_results_kind"),
        CheckConstraint("target <> start_value", name="ck_key_results_target"),
        CheckConstraint("slot IS NULL OR slot BETWEEN 1 AND 3", name="ck_key_results_slot"),
        CheckConstraint(
            "(status = 'active') = (slot IS NOT NULL)", name="ck_key_results_slot_state"
        ),
    )


class KeyResultValue(IdMixin, Base):
    """One value of the dated series of a key result. Rows are only added (spec 006)."""

    __tablename__ = "key_result_values"

    user_id: Mapped[uuid.UUID] = mapped_column(
        Uuid, ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    key_result_id: Mapped[uuid.UUID] = mapped_column(
        Uuid, ForeignKey("key_results.id", ondelete="CASCADE"), index=True
    )
    value: Mapped[float] = mapped_column(Float, nullable=False)
    at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    """The time stamp of the value, given by the user or by the push."""
    on_date: Mapped[date] = mapped_column(Date, nullable=False)
    """The day of ``at`` in the user time zone when the row was written (R-08)."""
    source: Mapped[str] = mapped_column(String(9), nullable=False)  # manual|automatic
    seq: Mapped[int] = mapped_column(nullable=False)
    """1, 2, 3 ... per key result. A higher ``seq`` was entered later."""
    entered_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)

    __table_args__ = (
        sa.UniqueConstraint("key_result_id", "seq", name="uq_key_result_values_key_result_seq"),
        Index("ix_key_result_values_series", "key_result_id", "on_date", "seq"),
    )


class KeyResultTheme(IdMixin, Base):
    """One link period between a key result and a theme project (R-04).

    Nothing is deleted: removing or replacing a link ends the row with ``ended_at`` and an
    ``end_reason``. The partial unique index allows one active link per key result and project.
    """

    __tablename__ = "key_result_themes"

    user_id: Mapped[uuid.UUID] = mapped_column(
        Uuid, ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    key_result_id: Mapped[uuid.UUID] = mapped_column(
        Uuid, ForeignKey("key_results.id", ondelete="CASCADE"), index=True
    )
    project_id: Mapped[uuid.UUID] = mapped_column(
        Uuid, ForeignKey("project_labels.id", ondelete="CASCADE"), index=True
    )
    year: Mapped[int] = mapped_column(nullable=False)
    """The planning year of the key result (FR-011)."""
    started_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    ended_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    end_reason: Mapped[str | None] = mapped_column(String(20), nullable=True)
    batch_id: Mapped[uuid.UUID | None] = mapped_column(Uuid, nullable=True, index=True)

    __table_args__ = (
        Index(
            "uq_key_result_themes_active",
            "key_result_id",
            "project_id",
            unique=True,
            sqlite_where=sa.text("ended_at IS NULL"),
            postgresql_where=sa.text("ended_at IS NULL"),
        ),
    )


class PlanChange(IdMixin, Base):
    """One row of the plan history. Append only: no update and no delete in the code (R-05)."""

    __tablename__ = "plan_changes"

    user_id: Mapped[uuid.UUID] = mapped_column(
        Uuid, ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    year: Mapped[int] = mapped_column(nullable=False, index=True)
    goal_id: Mapped[uuid.UUID | None] = mapped_column(
        Uuid, ForeignKey("goals.id", ondelete="CASCADE"), nullable=True
    )
    key_result_id: Mapped[uuid.UUID | None] = mapped_column(
        Uuid, ForeignKey("key_results.id", ondelete="CASCADE"), nullable=True
    )
    link_id: Mapped[uuid.UUID | None] = mapped_column(
        Uuid, ForeignKey("key_result_themes.id", ondelete="SET NULL"), nullable=True
    )
    kind: Mapped[str] = mapped_column(String(24), nullable=False)
    field: Mapped[str | None] = mapped_column(String(16), nullable=True)
    old_value: Mapped[str | None] = mapped_column(Text, nullable=True)
    new_value: Mapped[str | None] = mapped_column(Text, nullable=True)
    reason: Mapped[str | None] = mapped_column(Text, nullable=True)
    batch_id: Mapped[uuid.UUID | None] = mapped_column(Uuid, nullable=True, index=True)
    source: Mapped[str] = mapped_column(String(9), nullable=False)  # user|undo|seed|migration
    at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)
