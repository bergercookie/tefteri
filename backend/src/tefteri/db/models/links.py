"""Links between tasks and notes."""

import uuid

from sqlalchemy import ForeignKey, String, UniqueConstraint, Uuid
from sqlalchemy.orm import Mapped, mapped_column

from tefteri.db.base import Base, IdMixin


class TaskNoteLink(IdMixin, Base):
    """A note linked to a task, with an optional anchor inside the note."""

    __tablename__ = "task_note_links"
    __table_args__ = (UniqueConstraint("task_id", "note_id"),)

    user_id: Mapped[uuid.UUID] = mapped_column(
        Uuid, ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    task_id: Mapped[uuid.UUID] = mapped_column(Uuid, ForeignKey("tasks.id", ondelete="CASCADE"))
    note_id: Mapped[uuid.UUID] = mapped_column(Uuid, ForeignKey("notes.id", ondelete="CASCADE"))
    anchor: Mapped[str | None] = mapped_column(String(255), nullable=True)
