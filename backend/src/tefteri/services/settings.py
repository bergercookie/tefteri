"""Per-user settings."""

import uuid
from dataclasses import dataclass

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from tefteri.db.models.connection import Connection, SourceContainer
from tefteri.db.models.user import User
from tefteri.services.checklists import KINDS, clean_items
from tefteri.services.errors import Invalid, NotFound

MAX_REMINDER_MINUTES = 7 * 24 * 60
"""A reminder fires at most a week before the due time."""
MAX_SOURCE_PATH_LENGTH = 500
"""A note path is at most this many characters long."""


@dataclass(frozen=True)
class UserSettings:
    """The settings a user can change about their own planning."""

    random_time_on_date_drop: bool
    default_reminder_minutes: int
    checklists: dict[str, list[str]]
    """The planning checklists by period type: ``week``, ``month`` and ``year``."""
    checklist_sources: dict[str, str]
    """The note path of each read-only checklist, by period type. Empty when it is local."""
    default_event_container_id: uuid.UUID | None = None
    """The calendar that a new event starts in, or ``None`` when the user has not chosen one."""


class _Unset:
    """Marks a setting that the caller leaves as it is, because ``None`` is a value for it."""


UNSET = _Unset()


def _of(user: User) -> UserSettings:
    lists = {k.value: list(user.checklists.get(k.value, [])) for k in KINDS}
    sources = {k.value: str(user.checklist_sources.get(k.value, "")).strip() for k in KINDS}
    return UserSettings(
        user.random_time_on_date_drop,
        user.default_reminder_minutes,
        lists,
        sources,
        user.default_event_container_id,
    )


def clean_path(path: str) -> str:
    """Trim a note path; an empty result means no source. Spaces inside a title stay."""
    return path.strip()


class SettingsService:
    """Read and change the current user's settings."""

    async def get(self, db: AsyncSession, user_id: uuid.UUID) -> UserSettings:
        """Return the user's settings."""
        user = await db.get(User, user_id)
        if user is None:
            raise NotFound
        return _of(user)

    async def update(
        self,
        db: AsyncSession,
        user_id: uuid.UUID,
        *,
        random_time_on_date_drop: bool | None = None,
        default_reminder_minutes: int | None = None,
        checklists: dict[str, list[str]] | None = None,
        checklist_sources: dict[str, str] | None = None,
        default_event_container_id: uuid.UUID | None | _Unset = UNSET,
    ) -> UserSettings:
        """Change the fields that are not ``None`` and return the new settings."""
        user = await db.get(User, user_id)
        if user is None:
            raise NotFound
        if random_time_on_date_drop is not None:
            user.random_time_on_date_drop = random_time_on_date_drop
        if default_reminder_minutes is not None:
            user.default_reminder_minutes = default_reminder_minutes
        if checklists:
            # Only the lists that are given change; the others stay as they are.
            merged = {k.value: list(user.checklists.get(k.value, [])) for k in KINDS}
            for kind, items in checklists.items():
                merged[kind] = clean_items(items)
            user.checklists = merged
        if checklist_sources:
            # An empty path removes the source and brings the local list back.
            sources = {k.value: str(user.checklist_sources.get(k.value, "")).strip() for k in KINDS}
            for kind, path in checklist_sources.items():
                cleaned = clean_path(path)
                if cleaned:
                    sources[kind] = cleaned
                else:
                    sources.pop(kind, None)
            user.checklist_sources = {k: v for k, v in sources.items() if v}
        if not isinstance(default_event_container_id, _Unset):
            if default_event_container_id is not None:
                await _check_calendar(db, user_id, default_event_container_id)
            user.default_event_container_id = default_event_container_id
        await db.flush()
        return _of(user)


async def _check_calendar(db: AsyncSession, user_id: uuid.UUID, container_id: uuid.UUID) -> None:
    """Raise ``Invalid`` unless the container is a calendar of the user that can be changed."""
    row = (
        await db.execute(
            select(SourceContainer, Connection)
            .join(Connection, Connection.id == SourceContainer.connection_id)
            .where(SourceContainer.id == container_id, SourceContainer.user_id == user_id)
        )
    ).first()
    if row is None or row[1].kind != "calendar":
        raise Invalid("Choose one of your calendars.", "unknown_calendar")
    if row[0].read_only:
        raise Invalid("You cannot add events to this calendar.", "calendar_read_only")
