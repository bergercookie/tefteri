"""Per-user settings endpoints."""

import uuid
from typing import Annotated, Any, Literal

from fastapi import APIRouter, Request
from pydantic import BaseModel, ConfigDict, Field

from tefteri.api.deps import CurrentUser, Db
from tefteri.services.checklists import MAX_ITEM_LENGTH, MAX_ITEMS
from tefteri.services.connection_transfer import (
    CalendarRef,
    ConnectionTransfer,
    ExportedConnection,
)
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
    """Minutes before its due time that the app reminds the user of a task. The same time sets
    a reminder that the user adds to a task in the task app."""
    event_reminder_minutes: int
    """Minutes before a calendar event starts that the app reminds the user."""
    checklists: ChecklistsOut
    checklist_sources: ChecklistSourcesOut
    """A path means that the checklist is read from the notes app and cannot be ticked."""
    default_event_container_id: uuid.UUID | None
    """The calendar that a new event starts in, or null when the user has not chosen one."""
    event_invitees: list[str]
    """The e-mail addresses of the people that the user usually invites to an event."""
    seen_hints: list[str]
    """The ids of the hints that the user has seen. A hint shows only once."""

    @classmethod
    def of(cls, s: UserSettings) -> "SettingsOut":
        """Build from the settings."""
        return cls(
            random_time_on_date_drop=s.random_time_on_date_drop,
            default_reminder_minutes=s.default_reminder_minutes,
            event_reminder_minutes=s.event_reminder_minutes,
            checklists=ChecklistsOut(**s.checklists),
            checklist_sources=ChecklistSourcesOut(**s.checklist_sources),
            default_event_container_id=s.default_event_container_id,
            event_invitees=s.event_invitees,
            seen_hints=s.seen_hints,
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
    event_reminder_minutes: int | None = Field(default=None, ge=0, le=MAX_REMINDER_MINUTES)
    checklists: ChecklistsPatch | None = None
    checklist_sources: ChecklistSourcesPatch | None = None
    default_event_container_id: uuid.UUID | None = None
    """The calendar for new events; an explicit null clears the choice."""
    event_invitees: list[str] | None = Field(default=None, max_length=200)
    """The whole list of standard invitees (e-mail addresses). It replaces the old list."""


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
            event_reminder_minutes=body.event_reminder_minutes,
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
            event_invitees=body.event_invitees,
        )
    )


@router.post("/hints/{hint_id}/seen")
async def mark_hint_seen(hint_id: str, db: Db, user: CurrentUser) -> SettingsOut:
    """Remember that the user has seen a hint, so that it does not show again.

    It is safe to repeat. 422 ``bad_hint_id`` when the id is not a plain id.
    """
    return SettingsOut.of(await _service.mark_hint_seen(db, user.id, hint_id))


@router.delete("/hints")
async def reset_hints(db: Db, user: CurrentUser) -> SettingsOut:
    """Forget every seen hint, so that each hint shows once again."""
    return SettingsOut.of(await _service.reset_hints(db, user.id))


EXPORT_FORMAT: Literal["tefteri-settings"] = "tefteri-settings"
"""Names the kind of file, so that an unrelated JSON file is not imported by mistake."""
EXPORT_VERSION: Literal[1] = 1
"""Raised when the export changes in a way that an older import cannot read."""


class ExportedSettings(BaseModel):
    """The settings that move between installations.

    Connections hold the credentials of other services, and the calendar for new events is an id
    of this installation, so they are in the file only when the user asks for them.
    """

    model_config = ConfigDict(extra="forbid")

    random_time_on_date_drop: bool | None = None
    default_reminder_minutes: int | None = Field(default=None, ge=0, le=MAX_REMINDER_MINUTES)
    event_reminder_minutes: int | None = Field(default=None, ge=0, le=MAX_REMINDER_MINUTES)
    checklists: ChecklistsPatch | None = None
    checklist_sources: ChecklistSourcesPatch | None = None


class ExportedConnectionModel(BaseModel):
    """A connection with its credentials in the clear."""

    model_config = ConfigDict(extra="forbid")

    provider: str
    display_name: str = Field(min_length=1, max_length=150)
    settings: dict[str, Any] = Field(default_factory=dict)
    credentials: dict[str, Any] = Field(default_factory=dict)


class CalendarRefModel(BaseModel):
    """A calendar, named by its connection and its id in the calendar app."""

    model_config = ConfigDict(extra="forbid")

    connection: str
    remote_id: str


class SettingsExport(BaseModel):
    """A file with the user's settings, to keep or to import into another account.

    ``connections`` and ``default_event_calendar`` are there only when the user ticked the box.
    """

    model_config = ConfigDict(extra="forbid")

    format: Literal["tefteri-settings"] = EXPORT_FORMAT
    version: Literal[1] = EXPORT_VERSION
    settings: ExportedSettings
    connections: list[ExportedConnectionModel] | None = None
    """The user's connections with their credentials. A secret: keep the file safe."""
    default_event_calendar: CalendarRefModel | None = None


class ConnectionsImportOut(BaseModel):
    """What an import did with the connections of the file."""

    added: int
    skipped: list[str]
    """Connections that the user already has."""
    failed: dict[str, str]
    """The reason by name for each connection that could not be added."""
    default_event_calendar_restored: bool


class ImportOut(BaseModel):
    """The settings after an import, and what happened to the connections."""

    settings: SettingsOut
    connections: ConnectionsImportOut | None
    """Null when the file had no connections."""


@router.get("/export")
async def export_settings(
    request: Request, db: Db, user: CurrentUser, include_connections: bool = False
) -> SettingsExport:
    """Return the current user's settings as a file that ``POST /me/settings/import`` reads.

    With ``include_connections`` the file also holds the connections with their credentials and
    the calendar for new events.
    """
    s = await _service.get(db, user.id)
    out = SettingsExport(
        settings=ExportedSettings(
            random_time_on_date_drop=s.random_time_on_date_drop,
            default_reminder_minutes=s.default_reminder_minutes,
            event_reminder_minutes=s.event_reminder_minutes,
            checklists=ChecklistsPatch(**s.checklists),
            checklist_sources=ChecklistSourcesPatch(**s.checklist_sources),
        )
    )
    if include_connections:
        connections, calendar = await _transfer(request).export(db, user.id)
        out.connections = [
            ExportedConnectionModel(
                provider=c.provider,
                display_name=c.display_name,
                settings=c.settings,
                credentials=c.credentials,
            )
            for c in connections
        ]
        if calendar is not None:
            out.default_event_calendar = CalendarRefModel(
                connection=calendar.connection, remote_id=calendar.remote_id
            )
    return out


@router.post("/import")
async def import_settings(
    request: Request, body: SettingsExport, db: Db, user: CurrentUser
) -> ImportOut:
    """Apply an export to the current user. Settings that the file leaves out stay as they are.

    Connections of the file are added unless the user has one with the same provider and name.
    """
    patch = SettingsPatch(**body.settings.model_dump(exclude_none=True))
    settings = await update_settings(patch, db, user)
    if body.connections is None and body.default_event_calendar is None:
        return ImportOut(settings=settings, connections=None)
    calendar = body.default_event_calendar
    done = await _transfer(request).import_(
        db,
        user.id,
        [
            ExportedConnection(c.provider, c.display_name, c.settings, c.credentials)
            for c in body.connections or []
        ],
        CalendarRef(calendar.connection, calendar.remote_id) if calendar else None,
    )
    return ImportOut(
        settings=SettingsOut.of(await _service.get(db, user.id)),
        connections=ConnectionsImportOut(
            added=done.added,
            skipped=done.skipped,
            failed=done.failed,
            default_event_calendar_restored=done.default_calendar_restored,
        ),
    )


def _transfer(request: Request) -> ConnectionTransfer:
    return ConnectionTransfer(
        request.app.state.connection_service, request.app.state.sync_service, _service
    )
