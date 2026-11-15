"""Per-user settings."""

import uuid
from dataclasses import dataclass

from sqlalchemy.ext.asyncio import AsyncSession

from tefteri.db.models.user import User
from tefteri.services.checklists import KINDS, clean_items
from tefteri.services.errors import NotFound

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


def _of(user: User) -> UserSettings:
    lists = {k.value: list(user.checklists.get(k.value, [])) for k in KINDS}
    sources = {k.value: str(user.checklist_sources.get(k.value, "")).strip() for k in KINDS}
    return UserSettings(
        user.random_time_on_date_drop, user.default_reminder_minutes, lists, sources
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
        await db.flush()
        return _of(user)
