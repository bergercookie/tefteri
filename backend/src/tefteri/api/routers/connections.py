"""Connection management and Google OAuth endpoints."""

import html
import uuid
from typing import Any

from fastapi import APIRouter, Depends, Request
from fastapi.responses import HTMLResponse, RedirectResponse, Response
from pydantic import BaseModel, Field
from sqlalchemy import select

from tefteri.api.deps import CurrentUser, Db, SettingsDep
from tefteri.api.errors import ApiError
from tefteri.api.routers.sync import SyncResultOut
from tefteri.api.schemas import UtcDatetime
from tefteri.db.models.connection import Connection, SourceContainer
from tefteri.domain.capabilities import CapabilityReport
from tefteri.services.connections import ConnectionService, MissingCapability, UnknownProvider
from tefteri.services.google_oauth import GoogleOAuth, InvalidState
from tefteri.services.projects import ProjectService
from tefteri.services.sync import SyncService

router = APIRouter(prefix="/connections", tags=["connections"])


def _callback_url(request: Request, public_url: str | None) -> str:
    """Return the Google callback URL, using the configured public base URL when set."""
    if public_url:
        return f"{public_url.rstrip('/')}/api/v1/connections/google/callback"
    return str(request.url_for("google_callback"))


def get_connection_service(request: Request) -> ConnectionService:
    """Return the connection service."""
    service: ConnectionService = request.app.state.connection_service
    return service


Service = Depends(get_connection_service)


class ConnectionIn(BaseModel):
    """Data to create a connection."""

    provider: str
    display_name: str = Field(min_length=1, max_length=150)
    settings: dict[str, Any] = Field(default_factory=dict)
    credentials: dict[str, Any] = Field(default_factory=dict)


class ConnectionPatch(BaseModel):
    """Partial connection update."""

    display_name: str | None = Field(default=None, min_length=1, max_length=150)
    settings: dict[str, Any] | None = None
    credentials: dict[str, Any] | None = None


class ConnectionOut(BaseModel):
    """A connection as shown to the client. Credentials are never returned."""

    id: uuid.UUID
    kind: str
    provider: str
    display_name: str
    settings: dict[str, Any]
    status: str
    last_sync_at: UtcDatetime | None
    last_sync_outcome: str | None

    @classmethod
    def of(cls, c: Connection) -> "ConnectionOut":
        """Build from the ORM row."""
        return cls(
            id=c.id,
            kind=c.kind,
            provider=c.provider,
            display_name=c.display_name,
            settings=c.settings,
            status=c.status,
            last_sync_at=c.last_sync_at,
            last_sync_outcome=c.last_sync_outcome,
        )


class CapabilitiesOut(BaseModel):
    """What a task app can do (spec 003). Other kinds of connection have an empty report."""

    missing_required: list[str]
    """Required capabilities that the app lacks. A task app with any is refused."""
    optional: dict[str, bool]
    """Optional features: ``rename``, ``restore``, ``move_tasks``. A client hides what is off."""

    @classmethod
    def of(cls, report: CapabilityReport) -> "CapabilitiesOut":
        """Build from the domain report."""
        return cls(missing_required=report.missing_required, optional=report.optional)


class ConnectionCreatedOut(ConnectionOut):
    """A new connection and the result of its first sync."""

    sync: SyncResultOut
    capabilities: CapabilitiesOut


async def _create_and_sync(
    request: Request, db: Db, service: ConnectionService, user_id: uuid.UUID, **fields: Any
) -> tuple[Connection, SyncResultOut]:
    """Create a connection and sync it at once, whatever its provider.

    The connection stays when the sync fails: the result says why, and the user can fix the
    address or the token. Every way to add a connection goes through here.
    """
    connection = await service.create(db, user_id, **fields)
    sync: SyncService = request.app.state.sync_service
    return connection, SyncResultOut.of(await sync.sync_connection(db, connection))


class ConnectionCheckOut(BaseModel):
    """Whether a connection works, and if not, why."""

    status: str
    reason: str | None
    message: str | None
    capabilities: CapabilitiesOut


@router.post("/{connection_id}/check")
async def check_connection(
    connection_id: uuid.UUID, db: Db, user: CurrentUser, service: ConnectionService = Service
) -> ConnectionCheckOut:
    """Test the address and the credentials now, and say what is wrong when they fail."""
    connection = await _own(service, db, user, connection_id)
    health = await service.check(db, connection)
    return ConnectionCheckOut(
        status=health.status.value,
        reason=health.detail or None,
        message=health.message or None,
        capabilities=CapabilitiesOut.of(await service.capability_report(db, connection)),
    )


class ContainerOut(BaseModel):
    """A project, calendar or note subtree."""

    id: uuid.UUID
    remote_id: str
    name: str
    parent_remote_id: str | None = None
    color: str | None = None
    """The color of a calendar in the calendar app, as ``#rrggbb``."""
    enabled: bool = True
    """Tefteri syncs it. The user chooses which calendars of a Google account to sync."""
    read_only: bool = False
    """The user cannot change what it holds in the app."""


async def _own(service: ConnectionService, db: Db, user: CurrentUser, cid: uuid.UUID) -> Connection:
    connection = await service.get(db, user.id, cid)
    if connection is None:
        raise ApiError(404, "not_found", "Connection not found")
    return connection


@router.get("")
async def list_connections(
    db: Db, user: CurrentUser, service: ConnectionService = Service
) -> list[ConnectionOut]:
    """List the user's connections."""
    return [ConnectionOut.of(c) for c in await service.list(db, user.id)]


@router.post("", status_code=201)
async def create_connection(
    request: Request,
    body: ConnectionIn,
    db: Db,
    user: CurrentUser,
    service: ConnectionService = Service,
) -> ConnectionCreatedOut:
    """Connect an app and sync it once. The answer holds the result of that sync."""
    try:
        connection, sync = await _create_and_sync(
            request,
            db,
            service,
            user.id,
            provider=body.provider,
            display_name=body.display_name,
            settings=body.settings,
            credentials=body.credentials,
        )
    except UnknownProvider as exc:
        raise ApiError(422, "unknown_provider", f"Unknown provider: {body.provider}") from exc
    except MissingCapability as exc:
        raise ApiError(422, "missing_capability", exc.message) from exc
    report = await service.capability_report(db, connection)
    return ConnectionCreatedOut(
        **ConnectionOut.of(connection).model_dump(),
        sync=sync,
        capabilities=CapabilitiesOut.of(report),
    )


@router.get("/google/authorize")
async def google_authorize(
    request: Request,
    user: CurrentUser,
    settings: SettingsDep,
    display_name: str = "Google Calendar",
) -> dict[str, str]:
    """Return the Google consent URL for adding one more Google account."""
    oauth: GoogleOAuth | None = request.app.state.google_oauth
    if oauth is None:
        raise ApiError(503, "google_not_configured", "Google sign-in is not configured")
    redirect = _callback_url(request, settings.public_url)
    url = oauth.authorize_url(user.id, redirect, {"name": display_name})
    return {"url": url}


@router.get(
    "/google/callback",
    name="google_callback",
    response_class=HTMLResponse,
    responses={303: {"description": "Back to the web client's Connections screen"}},
)
async def google_callback(
    request: Request,
    db: Db,
    settings: SettingsDep,
    code: str,
    state: str,
    service: ConnectionService = Service,
) -> Response:
    """Finish Google sign-in. The signed ``state`` identifies the user.

    Google sends the user's browser here, so the answer is a page, not JSON: the web
    client's Connections screen when this server serves it, else a short confirmation.
    """
    oauth: GoogleOAuth | None = request.app.state.google_oauth
    if oauth is None:
        raise ApiError(503, "google_not_configured", "Google sign-in is not configured")
    try:
        data = oauth.read_state(state)
    except InvalidState as exc:
        raise ApiError(400, "invalid_state", "Invalid or expired sign-in request") from exc
    refresh_token = await oauth.exchange_code(code, _callback_url(request, settings.public_url))
    connection, _ = await _create_and_sync(
        request,
        db,
        service,
        uuid.UUID(data["user_id"]),
        provider="google_calendar",
        display_name=data["name"],
        settings={},
        credentials={"refresh_token": refresh_token},
    )
    if settings.web_dir is not None:
        base = (settings.public_url or "").rstrip("/")
        return RedirectResponse(
            f"{base}/#/settings/connections?choose={connection.id}", status_code=303
        )
    name = html.escape(connection.display_name)
    return HTMLResponse(
        f"<!doctype html><title>tefteri</title><p>{name} is connected. "
        "You can close this tab and go back to tefteri.</p>"
    )


@router.patch("/{connection_id}")
async def update_connection(
    connection_id: uuid.UUID,
    body: ConnectionPatch,
    db: Db,
    user: CurrentUser,
    service: ConnectionService = Service,
) -> ConnectionOut:
    """Change a connection."""
    connection = await _own(service, db, user, connection_id)
    updated = await service.update(
        db,
        connection,
        display_name=body.display_name,
        settings=body.settings,
        credentials=body.credentials,
    )
    return ConnectionOut.of(updated)


@router.delete("/{connection_id}", status_code=204)
async def delete_connection(
    connection_id: uuid.UUID, db: Db, user: CurrentUser, service: ConnectionService = Service
) -> None:
    """Remove a connection and its cached items."""
    await service.delete(db, user.id, await _own(service, db, user, connection_id))


@router.get("/{connection_id}/containers")
async def list_containers(
    connection_id: uuid.UUID, db: Db, user: CurrentUser, service: ConnectionService = Service
) -> list[ContainerOut]:
    """List the projects, calendars or note subtrees found by the last sync."""
    await _own(service, db, user, connection_id)
    rows = (
        await db.execute(
            select(SourceContainer).where(
                SourceContainer.connection_id == connection_id,
                SourceContainer.user_id == user.id,
            )
        )
    ).scalars()
    return [
        ContainerOut(
            id=r.id,
            remote_id=r.remote_id,
            name=r.name,
            parent_remote_id=r.parent_remote_id,
            color=r.color,
            enabled=r.enabled,
            read_only=r.read_only,
        )
        for r in rows
    ]


class EnabledIn(BaseModel):
    """The calendars (containers) that tefteri syncs. Every other one of the connection is off."""

    container_ids: list[uuid.UUID]


class ContainersSyncedOut(BaseModel):
    """The containers after a new choice, and the result of the sync that followed."""

    containers: list[ContainerOut]
    sync: SyncResultOut


@router.put("/{connection_id}/containers/enabled")
async def choose_containers(
    connection_id: uuid.UUID,
    body: EnabledIn,
    request: Request,
    db: Db,
    user: CurrentUser,
    service: ConnectionService = Service,
) -> ContainersSyncedOut:
    """Choose which calendars of the connection tefteri syncs, then sync the connection.

    The ids that are not listed are switched off, and their events leave the cache. An id that
    does not belong to the connection is refused.
    """
    connection = await _own(service, db, user, connection_id)
    rows = list(
        (
            await db.execute(
                select(SourceContainer).where(
                    SourceContainer.connection_id == connection_id,
                    SourceContainer.user_id == user.id,
                )
            )
        ).scalars()
    )
    known = {r.id for r in rows}
    unknown = set(body.container_ids) - known
    if unknown:
        raise ApiError(422, "unknown_container", "One of the calendars is not in this connection.")
    chosen = set(body.container_ids)
    for row in rows:
        row.enabled = row.id in chosen
    await db.flush()
    sync: SyncService = request.app.state.sync_service
    result = SyncResultOut.of(await sync.sync_connection(db, connection))
    return ContainersSyncedOut(
        containers=[
            ContainerOut(
                id=r.id,
                remote_id=r.remote_id,
                name=r.name,
                parent_remote_id=r.parent_remote_id,
                color=r.color,
                enabled=r.enabled,
                read_only=r.read_only,
            )
            for r in rows
        ],
        sync=result,
    )


@router.get("/{connection_id}/labels")
async def list_labels(
    connection_id: uuid.UUID,
    request: Request,
    db: Db,
    user: CurrentUser,
    service: ConnectionService = Service,
) -> list[str]:
    """List the labels that exist in the task app, for suggestions."""
    await _own(service, db, user, connection_id)
    projects: ProjectService = request.app.state.project_service
    return await projects.labels(db, user.id, connection_id)


@router.post("/{connection_id}/containers/{container_id}/archive", status_code=204)
async def archive_container(
    connection_id: uuid.UUID,
    container_id: uuid.UUID,
    request: Request,
    db: Db,
    user: CurrentUser,
    service: ConnectionService = Service,
) -> None:
    """Archive a project in the task app. The app can restore it; tefteri forgets it."""
    await _own(service, db, user, connection_id)
    row = await db.get(SourceContainer, container_id)
    if row is None or row.connection_id != connection_id or row.user_id != user.id:
        raise ApiError(404, "not_found", "Container not found")
    projects: ProjectService = request.app.state.project_service
    await projects.archive(db, user.id, container_id)
