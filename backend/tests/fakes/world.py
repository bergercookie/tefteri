"""A fake 'world' of backends plus a registry that serves them to the app under test."""

from datetime import UTC, datetime

from tefteri.domain.entities import (
    Container,
    EntryDraft,
    NoteDraft,
    TaskDraft,
)
from tefteri.domain.enums import ConnectionKind
from tefteri.services.connections import AdapterRegistry
from tests.fakes.memory import FakeCalendarBackend, FakeNoteBackend, FakeTaskBackend


class FakeWorld:
    """Named fake backends. A connection's ``settings["fake"]`` picks the instance."""

    def __init__(self) -> None:
        """Create one default backend of each kind."""
        self.tasks: dict[str, FakeTaskBackend] = {
            "default": FakeTaskBackend([Container("p1", "Inbox")])
        }
        self.calendars: dict[str, FakeCalendarBackend] = {
            "default": FakeCalendarBackend([Container("cal1", "Personal")])
        }
        self.notes: dict[str, FakeNoteBackend] = {
            "default": FakeNoteBackend([Container("root", "Root")])
        }

    def registry(self) -> AdapterRegistry:
        """Return a registry using the same provider names as production."""
        registry = AdapterRegistry()
        registry.register(
            "vikunja", ConnectionKind.TASKS, lambda s, _c: self.tasks[s.get("fake", "default")]
        )
        registry.register(
            "google_calendar",
            ConnectionKind.CALENDAR,
            lambda s, _c: self.calendars[s.get("fake", "default")],
        )
        registry.register(
            "trilium", ConnectionKind.NOTES, lambda s, _c: self.notes[s.get("fake", "default")]
        )
        return registry

    async def seed(self) -> None:
        """Put one item of each kind into the default backends."""
        await self.tasks["default"].create_task(TaskDraft("p1", "Write report"))
        now = datetime(2026, 11, 2, 9, tzinfo=UTC)
        await self.calendars["default"].create_entry(
            EntryDraft("cal1", "Standup", now, now.replace(minute=15))
        )
        await self.notes["default"].create_note(NoteDraft("Process", "steps"))
