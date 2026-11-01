"""Sync endpoints."""

import uuid
from datetime import datetime

from fastapi import APIRouter, Depends, Request
from pydantic import BaseModel

from tefteri.api.deps import CurrentUser, Db
from tefteri.api.errors import ApiError
from tefteri.services.connections import ConnectionService
from tefteri.services.sync import SyncResult, SyncService

router = APIRouter(tags=["sync"])


def get_sync_service(request: Request) -> SyncService:
    """Return the sync service."""
    service: SyncService = request.app.state.sync_service
    return service


def _connections(request: Request) -> ConnectionService:
    service: ConnectionService = request.app.state.connection_service
    return service


Service = Depends(get_sync_service)


class SyncResultOut(BaseModel):
    """Outcome of syncing one connection."""

    connection_id: uuid.UUID
    name: str
    outcome: str
    reason: str | None
    counts: dict[str, int]

    @classmethod
    def of(cls, r: SyncResult) -> "SyncResultOut":
        """Build from a service result."""
        return cls(
            connection_id=r.connection_id,
            name=r.name,
            outcome=r.outcome,
            reason=r.reason,
            counts=r.counts,
        )


class SyncStatusOut(BaseModel):
    """Last sync information of one connection."""

    connection_id: uuid.UUID
    name: str
    status: str
    last_sync_at: datetime | None
    last_sync_outcome: str | None


@router.post("/sync")
async def sync_all(
    db: Db, user: CurrentUser, service: SyncService = Service
) -> list[SyncResultOut]:
    """Sync every connection. Each result says which one failed and why."""
    return [SyncResultOut.of(r) for r in await service.sync_all(db, user.id)]


@router.post("/connections/{connection_id}/sync")
async def sync_one(
    connection_id: uuid.UUID,
    request: Request,
    db: Db,
    user: CurrentUser,
    service: SyncService = Service,
) -> SyncResultOut:
    """Sync one connection (used by Retry)."""
    connection = await _connections(request).get(db, user.id, connection_id)
    if connection is None:
        raise ApiError(404, "not_found", "Connection not found")
    return SyncResultOut.of(await service.sync_connection(db, connection))


@router.get("/sync/status")
async def sync_status(request: Request, db: Db, user: CurrentUser) -> list[SyncStatusOut]:
    """Return the last sync time and outcome of each connection."""
    return [
        SyncStatusOut(
            connection_id=c.id,
            name=c.display_name,
            status=c.status,
            last_sync_at=c.last_sync_at,
            last_sync_outcome=c.last_sync_outcome,
        )
        for c in await _connections(request).list(db, user.id)
    ]
