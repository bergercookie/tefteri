"""Conflict endpoints."""

import uuid
from datetime import datetime
from typing import Any

from fastapi import APIRouter, Request
from pydantic import BaseModel

from tefteri.api.deps import CurrentUser, Db
from tefteri.domain.enums import Resolution
from tefteri.services.conflicts import ConflictService

router = APIRouter(prefix="/conflicts", tags=["conflicts"])


def _service(request: Request) -> ConflictService:
    service: ConflictService = request.app.state.conflict_service
    return service


class ConflictOut(BaseModel):
    """An unresolved conflict with both versions."""

    id: uuid.UUID
    entity_type: str
    entity_id: uuid.UUID
    local_snapshot: dict[str, Any]
    remote_snapshot: dict[str, Any]
    created_at: datetime


class ResolveIn(BaseModel):
    """The user's choice."""

    resolution: Resolution


@router.get("")
async def list_conflicts(request: Request, db: Db, user: CurrentUser) -> list[ConflictOut]:
    """List unresolved conflicts."""
    return [
        ConflictOut(
            id=c.id,
            entity_type=c.entity_type,
            entity_id=c.entity_id,
            local_snapshot=c.local_snapshot,
            remote_snapshot=c.remote_snapshot,
            created_at=c.created_at,
        )
        for c in await _service(request).list_open(db, user.id)
    ]


@router.post("/{conflict_id}/resolve", status_code=204)
async def resolve(
    conflict_id: uuid.UUID, body: ResolveIn, request: Request, db: Db, user: CurrentUser
) -> None:
    """Keep the local or the remote version. Nothing is resolved automatically."""
    await _service(request).resolve(db, user.id, conflict_id, body.resolution)
