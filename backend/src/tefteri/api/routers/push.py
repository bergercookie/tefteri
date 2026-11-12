"""The inbound value push for automatic key results (spec 006, FR-010, contract section 4).

This route does not use the session. It takes only the push token of the user, in the header
``Authorization: Bearer tfv_...``; a cookie or a session token is never accepted, and the
``X-Tefteri-Client`` header is not needed. Every refusal stores nothing.
"""

import uuid
from typing import Annotated, Any

from fastapi import APIRouter, Body, Request, Response
from pydantic import BaseModel

from tefteri.api.deps import Db
from tefteri.api.errors import ApiError
from tefteri.services.value_push import PushRejected, PushTokenService

router = APIRouter(tags=["push"])

_EXAMPLE = {"value": 1342, "at": "2027-03-04T09:30:00Z"}


class PushOut(BaseModel):
    """The answer to an accepted push (201) or to a safe retry of one (200)."""

    stored: bool
    key_result_id: uuid.UUID
    value: float
    at: str
    current_value: float


def _push_token(request: Request) -> str:
    """Return the bearer token of the request, or refuse with 401 ``invalid_push_token``."""
    scheme, _, token = request.headers.get("authorization", "").partition(" ")
    if scheme.lower() != "bearer" or not token.strip():
        raise PushRejected(401, "invalid_push_token", "The push token is not valid.")
    return token.strip()


@router.post(
    "/key-results/{key_result_id}/push",
    status_code=201,
    responses={
        200: {"model": PushOut, "description": "The same value was stored before."},
        401: {"description": "invalid_push_token"},
        404: {"description": "not_found"},
        409: {"description": "retired or not_automatic"},
        422: {"description": "invalid"},
        429: {"description": "rate_limited, with Retry-After"},
    },
)
async def push_value(
    key_result_id: uuid.UUID,
    request: Request,
    response: Response,
    db: Db,
    body: Annotated[dict[str, Any], Body(openapi_examples={"push": {"value": _EXAMPLE}})],
) -> PushOut:
    """Store a value that an outside source sends for an automatic key result (FR-010).

    Body: ``value`` (a finite JSON number) and ``at`` (ISO 8601 with a zone, not more than five
    minutes in the future). The same value with the same time is stored once: the retry answers
    200 with ``stored: false``. At most 60 pushes a minute per token.
    """
    service: PushTokenService = request.app.state.push_token_service
    try:
        outcome = await service.push(
            db, _push_token(request), key_result_id, body.get("value"), body.get("at")
        )
    except PushRejected as exc:
        headers = {"Retry-After": str(exc.retry_after)} if exc.retry_after else None
        raise ApiError(exc.status, exc.code, exc.message, headers) from exc
    if not outcome.stored:
        response.status_code = 200
    return PushOut(
        stored=outcome.stored,
        key_result_id=key_result_id,
        value=outcome.value,
        at=outcome.at.isoformat(),
        current_value=outcome.current_value,
    )
