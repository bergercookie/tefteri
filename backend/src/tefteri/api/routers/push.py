"""Inbound value-push route for automatic key results."""

import uuid
from datetime import datetime

from fastapi import APIRouter, Request
from pydantic import BaseModel

from tefteri.api.deps import Db
from tefteri.services.value_push import PushRejected

router = APIRouter(tags=["push"])


class PushIn(BaseModel):
    """One inbound push value."""

    value: float
    at: str | None = None


def _token_from_auth_header(request: Request) -> str:
    header = request.headers.get("authorization", "")
    if not header:
        raise PushRejected(401, "invalid_push_token", "The push token is not valid.")
    scheme, _, token = header.partition(" ")
    if token and scheme.lower() == "bearer":
        return token
    if scheme and scheme.lower() != "bearer":
        return header
    return header


@router.post("/key-results/{key_result_id}/push")
async def push_value(
    key_result_id: uuid.UUID,
    body: PushIn,
    request: Request,
    db: Db,
) -> dict[str, object]:
    """Accept an automatic value from the push token of the owner."""
    token = _token_from_auth_header(request)
    parsed_at: datetime | None = None
    if body.at is not None:
        raw = body.at
        if raw.endswith("Z"):
            raw = raw[:-1] + "+00:00"
        try:
            parsed_at = datetime.fromisoformat(raw)
        except ValueError as exc:
            raise PushRejected(422, "invalid", "The time of the value needs a time zone.") from exc
    try:
        outcome = await request.app.state.push_token_service.push(
            db,
            token,
            key_result_id,
            body.value,
            parsed_at,
        )
    except PushRejected as exc:
        if getattr(exc, "status", 0) == 429 and getattr(exc, "retry_after", None) is not None:
            raise
        raise
    return {
        "stored": outcome.stored,
        "key_result_id": outcome.key_result_id,
        "value": outcome.value,
        "at": outcome.at,
        "current_value": outcome.current_value,
    }
