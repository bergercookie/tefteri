"""Declarative base and shared column helpers."""

import uuid
from datetime import UTC, datetime

from sqlalchemy import DateTime, Uuid
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column


def utcnow() -> datetime:
    """Return the current UTC time (timezone aware)."""
    return datetime.now(UTC)


class Base(DeclarativeBase):
    """Base class for all ORM models."""


class IdMixin:
    """UUID primary key."""

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)


class CreatedMixin:
    """Creation timestamp."""

    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)
