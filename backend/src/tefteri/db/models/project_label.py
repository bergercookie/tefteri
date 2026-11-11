"""The label of a project of a task app, and the history of its changes (spec 003)."""

import uuid
from datetime import datetime

from sqlalchemy import DateTime, ForeignKey, Index, String, UniqueConstraint, Uuid
from sqlalchemy.orm import Mapped, mapped_column

from tefteri.db.base import Base, CreatedMixin, IdMixin


class ProjectLabel(IdMixin, CreatedMixin, Base):
    """One row per project that tefteri has seen in a task connection.

    The row is keyed on the identity of the project in the task app (``remote_id``), never on
    its name, so a rename or a move keeps the label. The row is never deleted when the project
    leaves the task app: it is marked orphaned instead (``orphaned_reason``). Its ``id`` is the
    public id of the project in the API.
    """

    __tablename__ = "project_labels"
    __table_args__ = (
        UniqueConstraint("connection_id", "remote_id"),
        Index("ix_project_labels_user_connection", "user_id", "connection_id"),
    )

    user_id: Mapped[uuid.UUID] = mapped_column(Uuid, ForeignKey("users.id", ondelete="CASCADE"))
    connection_id: Mapped[uuid.UUID] = mapped_column(
        Uuid, ForeignKey("connections.id", ondelete="CASCADE")
    )
    remote_id: Mapped[str] = mapped_column(String(255))
    name: Mapped[str] = mapped_column(String(255))
    """The last title that tefteri read. It is shown when the project is orphaned."""
    parent_remote_id: Mapped[str | None] = mapped_column(String(255), nullable=True)
    label: Mapped[str | None] = mapped_column(String(16), nullable=True)
    """``theme``, ``milestone``, ``maintenance`` or ``ignored``; ``None`` is unclassified. A cache
    of the newest history entry."""
    label_changed_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
    orphaned_reason: Mapped[str | None] = mapped_column(String(16), nullable=True)
    """``missing`` or ``archived``; ``None`` means that the project is live."""
    orphaned_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)


class ProjectLabelHistory(IdMixin, Base):
    """One label change. Rows are only added, never edited or deleted.

    The label of a project on a day is the entry with the latest ``from_at`` not after that day.
    """

    __tablename__ = "project_label_history"

    project_id: Mapped[uuid.UUID] = mapped_column(
        Uuid, ForeignKey("project_labels.id", ondelete="CASCADE"), index=True
    )
    label: Mapped[str | None] = mapped_column(String(16), nullable=True)
    """The label from this moment. ``None`` is back to unclassified."""
    from_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    batch_id: Mapped[uuid.UUID | None] = mapped_column(Uuid, nullable=True, index=True)
    """The rows of one save share it. The rows that an undo adds carry the id they undo."""
    source: Mapped[str] = mapped_column(String(16))  # user | suggestion | undo
