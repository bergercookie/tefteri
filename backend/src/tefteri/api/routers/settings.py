"""Per-user settings endpoints."""

from fastapi import APIRouter
from pydantic import BaseModel, ConfigDict, Field

from tefteri.api.deps import CurrentUser, Db
from tefteri.services.settings import MAX_REMINDER_MINUTES, SettingsService, UserSettings

router = APIRouter(prefix="/me/settings", tags=["settings"])
_service = SettingsService()


class SettingsOut(BaseModel):
    """The current user's settings."""

    random_time_on_date_drop: bool
    default_reminder_minutes: int
    """Minutes before its due time that a new task reminder fires."""

    @classmethod
    def of(cls, s: UserSettings) -> "SettingsOut":
        """Build from the settings."""
        return cls(
            random_time_on_date_drop=s.random_time_on_date_drop,
            default_reminder_minutes=s.default_reminder_minutes,
        )


class SettingsPatch(BaseModel):
    """Settings to change; fields that are left out stay as they are."""

    model_config = ConfigDict(extra="forbid")

    random_time_on_date_drop: bool | None = None
    default_reminder_minutes: int | None = Field(default=None, ge=0, le=MAX_REMINDER_MINUTES)


@router.get("")
async def get_settings(db: Db, user: CurrentUser) -> SettingsOut:
    """Return the current user's settings."""
    return SettingsOut.of(await _service.get(db, user.id))


@router.patch("")
async def update_settings(body: SettingsPatch, db: Db, user: CurrentUser) -> SettingsOut:
    """Change the current user's settings."""
    return SettingsOut.of(
        await _service.update(
            db,
            user.id,
            random_time_on_date_drop=body.random_time_on_date_drop,
            default_reminder_minutes=body.default_reminder_minutes,
        )
    )
