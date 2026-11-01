"""User-scoped repositories for cached items."""

from tefteri.db.models.calendar_entry import CalendarEntry
from tefteri.db.models.links import TaskNoteLink
from tefteri.db.models.note import Note
from tefteri.db.models.task import Task
from tefteri.db.repositories.base import ScopedRepository


class TaskRepository(ScopedRepository[Task]):
    """User-scoped access to tasks."""

    model = Task


class EntryRepository(ScopedRepository[CalendarEntry]):
    """User-scoped access to calendar entries."""

    model = CalendarEntry


class NoteRepository(ScopedRepository[Note]):
    """User-scoped access to notes."""

    model = Note


class TaskNoteLinkRepository(ScopedRepository[TaskNoteLink]):
    """User-scoped access to task-note links."""

    model = TaskNoteLink
