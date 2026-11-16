"""Per-user settings endpoints."""

import uuid
from typing import Annotated, Literal

from fastapi import APIRouter
from pydantic import BaseModel, ConfigDict, Field

from tefteri.api.deps import CurrentUser, Db
from tefteri.services.checklists import MAX_ITEM_LENGTH, MAX_ITEMS
from tefteri.services.settings import (
    MAX_REMINDER_MINUTES,
    MAX_SOURCE_PATH_LENGTH,
    UNSET,
    SettingsService,
    UserSettings,
)

router = APIRouter(prefix="/me/settings", tags=["settings"])
_service = SettingsService()


class ChecklistsOut(BaseModel):
    """The planning checklists: the items to go through at each kind of planning."""

    week: list[str]
    month: list[str]
    year: list[str]


type _Items = Annotated[
    list[Annotated[str, Field(max_length=MAX_ITEM_LENGTH)]], Field(max_length=MAX_ITEMS)
]


class ChecklistsPatch(BaseModel):
    """Checklists to replace; a list that is left out stays as it is."""

    model_config = ConfigDict(extra="forbid")

    week: _Items | None = None
    month: _Items | None = None
    year: _Items | None = None


class ChecklistSourcesOut(BaseModel):
    """The note path of each checklist that comes from the notes app."""

    week: str
    month: str
    year: str


class SettingsOut(BaseModel):
    """The current user's settings."""

    random_time_on_date_drop: bool
    default_reminder_minutes: int
    """Minutes before its due time that a new task reminder fires."""
    checklists: ChecklistsOut
    checklist_sources: ChecklistSourcesOut
    """A path means that the checklist is read from the notes app and cannot be ticked."""
    default_event_container_id: uuid.UUID | None
    """The calendar that a new event starts in, or null when the user has not chosen one."""

    @classmethod
    def of(cls, s: UserSettings) -> "SettingsOut":
        """Build from the settings."""
        return cls(
            random_time_on_date_drop=s.random_time_on_date_drop,
            default_reminder_minutes=s.default_reminder_minutes,
            checklists=ChecklistsOut(**s.checklists),
            checklist_sources=ChecklistSourcesOut(**s.checklist_sources),
            default_event_container_id=s.default_event_container_id,
        )


class ChecklistSourcesPatch(BaseModel):
    """Source paths to replace; an empty path goes back to the local list."""

    model_config = ConfigDict(extra="forbid")

    week: str | None = Field(default=None, max_length=MAX_SOURCE_PATH_LENGTH)
    month: str | None = Field(default=None, max_length=MAX_SOURCE_PATH_LENGTH)
    year: str | None = Field(default=None, max_length=MAX_SOURCE_PATH_LENGTH)


class SettingsPatch(BaseModel):
    """Settings to change; fields that are left out stay as they are."""

    model_config = ConfigDict(extra="forbid")

    random_time_on_date_drop: bool | None = None
    default_reminder_minutes: int | None = Field(default=None, ge=0, le=MAX_REMINDER_MINUTES)
    checklists: ChecklistsPatch | None = None
    checklist_sources: ChecklistSourcesPatch | None = None
    default_event_container_id: uuid.UUID | None = None
    """The calendar for new events; an explicit null clears the choice."""


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
            checklists=body.checklists.model_dump(exclude_none=True) if body.checklists else None,
            checklist_sources=(
                body.checklist_sources.model_dump(exclude_none=True)
                if body.checklist_sources
                else None
            ),
            default_event_container_id=(
                body.default_event_container_id
                if "default_event_container_id" in body.model_fields_set
                else UNSET
            ),
        )
    )


EXPORT_FORMAT: Literal["tefteri-settings"] = "tefteri-settings"
"""Names the kind of file, so that an unrelated JSON file is not imported by mistake."""
EXPORT_VERSION: Literal[1] = 1
"""Raised when the export changes in a way that an older import cannot read."""


class ExportedSettings(BaseModel):
    """The settings that move between installations.

    The calendar for new events is left out: it is an id of this installation. Connections are
    left out too, because they hold the credentials of other services.
    """

    model_config = ConfigDict(extra="forbid")

    random_time_on_date_drop: bool | None = None
    default_reminder_minutes: int | None = Field(default=None, ge=0, le=MAX_REMINDER_MINUTES)
    checklists: ChecklistsPatch | None = None
    checklist_sources: ChecklistSourcesPatch | None = None


class SettingsExport(BaseModel):
    """A file with the user's settings, to keep or to import into another account."""

    model_config = ConfigDict(extra="forbid")

    format: Literal["tefteri-settings"] = EXPORT_FORMAT
    version: Literal[1] = EXPORT_VERSION
    settings: ExportedSettings


@router.get("/export")
async def export_settings(db: Db, user: CurrentUser) -> SettingsExport:
    """Return the current user's settings as a file that ``POST /me/settings/import`` reads."""
    s = await _service.get(db, user.id)
    return SettingsExport(
        settings=ExportedSettings(
            random_time_on_date_drop=s.random_time_on_date_drop,
            default_reminder_minutes=s.default_reminder_minutes,
            checklists=ChecklistsPatch(**s.checklists),
            checklist_sources=ChecklistSourcesPatch(**s.checklist_sources),
        )
    )


@router.post("/import")
async def import_settings(body: SettingsExport, db: Db, user: CurrentUser) -> SettingsOut:
    """Apply an export to the current user. Settings that the file leaves out stay as they are."""
    patch = SettingsPatch(**body.settings.model_dump(exclude_none=True))
    return await update_settings(
        patch,
        db,
        user,
    )
