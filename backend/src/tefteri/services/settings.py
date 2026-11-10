"""Per-user settings."""

import uuid
from dataclasses import dataclass

from sqlalchemy.ext.asyncio import AsyncSession

from tefteri.db.models.user import User
from tefteri.services.errors import NotFound

MAX_REMINDER_MINUTES = 7 * 24 * 60
"""A reminder fires at most a week before the due time."""


@dataclass(frozen=True)
class UserSettings:
    """The settings a user can change about their own planning."""

    random_time_on_date_drop: bool
    default_reminder_minutes: int


def _of(user: User) -> UserSettings:
    return UserSettings(user.random_time_on_date_drop, user.default_reminder_minutes)


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
    ) -> UserSettings:
        """Change the fields that are not ``None`` and return the new settings."""
        user = await db.get(User, user_id)
        if user is None:
            raise NotFound
        if random_time_on_date_drop is not None:
            user.random_time_on_date_drop = random_time_on_date_drop
        if default_reminder_minutes is not None:
            user.default_reminder_minutes = default_reminder_minutes
        await db.flush()
        return _of(user)
