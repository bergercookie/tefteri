"""Per-user settings endpoints."""

from fastapi import APIRouter
from pydantic import BaseModel, ConfigDict

from tefteri.api.deps import CurrentUser, Db
from tefteri.services.settings import SettingsService

router = APIRouter(prefix="/me/settings", tags=["settings"])
_service = SettingsService()


class SettingsOut(BaseModel):
    """The current user's settings."""

    random_time_on_date_drop: bool


class SettingsPatch(BaseModel):
    """Settings to change; fields that are left out stay as they are."""

    model_config = ConfigDict(extra="forbid")

    random_time_on_date_drop: bool | None = None


@router.get("")
async def get_settings(db: Db, user: CurrentUser) -> SettingsOut:
    """Return the current user's settings."""
    current = await _service.get(db, user.id)
    return SettingsOut(random_time_on_date_drop=current.random_time_on_date_drop)


@router.patch("")
async def update_settings(body: SettingsPatch, db: Db, user: CurrentUser) -> SettingsOut:
    """Change the current user's settings."""
    current = await _service.update(
        db, user.id, random_time_on_date_drop=body.random_time_on_date_drop
    )
    return SettingsOut(random_time_on_date_drop=current.random_time_on_date_drop)
