"""Review notes: the one thing an annual review writes (spec 008, FR-017)."""

import uuid
from datetime import datetime

import sqlalchemy as sa
from sqlalchemy import CheckConstraint, DateTime, ForeignKey, Index, Text, Uuid
from sqlalchemy.orm import Mapped, mapped_column

from tefteri.db.base import Base, CreatedMixin, IdMixin, utcnow


class ReviewNote(IdMixin, CreatedMixin, Base):
    """One note per user, year and scope.

    ``goal_id`` is null for the note of the year and set for the note of one annual goal.
    Two partial unique indexes keep the scope unique; the service checks that the goal is an
    annual goal of the user and of that year.
    """

    __tablename__ = "review_notes"

    user_id: Mapped[uuid.UUID] = mapped_column(
        Uuid, ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    year: Mapped[int] = mapped_column(nullable=False)
    goal_id: Mapped[uuid.UUID | None] = mapped_column(
        Uuid, ForeignKey("goals.id", ondelete="CASCADE"), nullable=True
    )
    body: Mapped[str] = mapped_column(Text, nullable=False)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        default=utcnow,
        server_default=sa.text("CURRENT_TIMESTAMP"),
        onupdate=utcnow,
        nullable=False,
    )

    __table_args__ = (
        CheckConstraint(
            "length(body) BETWEEN 1 AND 2000", name="ck_review_notes_body_length"
        ),
        CheckConstraint("year BETWEEN 2000 AND 2100", name="ck_review_notes_year"),
        Index(
            "uq_review_notes_year",
            "user_id",
            "year",
            unique=True,
            sqlite_where=sa.text("goal_id IS NULL"),
            postgresql_where=sa.text("goal_id IS NULL"),
        ),
        Index(
            "uq_review_notes_goal",
            "user_id",
            "goal_id",
            unique=True,
            sqlite_where=sa.text("goal_id IS NOT NULL"),
            postgresql_where=sa.text("goal_id IS NOT NULL"),
        ),
        Index("ix_review_notes_user_year", "user_id", "year"),
    )
