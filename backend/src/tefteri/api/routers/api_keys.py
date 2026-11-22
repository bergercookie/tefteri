"""API keys: make, list and revoke the keys that tools such as an MCP client use."""

import uuid
from typing import Annotated

from fastapi import APIRouter
from pydantic import BaseModel, ConfigDict, StringConstraints

from tefteri.api.deps import AuthDep, Db, SessionUser
from tefteri.api.errors import ApiError
from tefteri.api.schemas import UtcDatetime
from tefteri.db.models.api_key import ApiKey

router = APIRouter(prefix="/me/api-keys", tags=["api-keys"])

MAX_KEYS = 20
"""The most keys one user can have."""


class ApiKeyIn(BaseModel):
    """The name of a new key."""

    model_config = ConfigDict(extra="forbid")

    name: Annotated[str, StringConstraints(strip_whitespace=True, min_length=1, max_length=80)]
    """What the key is for, for example ``Claude Desktop``."""


class ApiKeyOut(BaseModel):
    """A key, without the key itself."""

    id: uuid.UUID
    name: str
    prefix: str
    """The first characters of the key, to tell keys apart."""
    created_at: UtcDatetime
    last_used_at: UtcDatetime | None

    @classmethod
    def of(cls, row: ApiKey) -> "ApiKeyOut":
        """Build from the row."""
        return cls(
            id=row.id,
            name=row.name,
            prefix=row.prefix,
            created_at=row.created_at,
            last_used_at=row.last_used_at,
        )


class ApiKeyCreated(ApiKeyOut):
    """A new key. ``key`` is shown this once and cannot be read again."""

    key: str


@router.get("")
async def list_keys(db: Db, auth: AuthDep, user: SessionUser) -> list[ApiKeyOut]:
    """List the keys of the signed-in user, the newest first."""
    return [ApiKeyOut.of(r) for r in await auth.list_api_keys(db, user.id)]


@router.post("", status_code=201)
async def create_key(body: ApiKeyIn, db: Db, auth: AuthDep, user: SessionUser) -> ApiKeyCreated:
    """Make a key. The answer holds the key; it is not shown again."""
    if len(await auth.list_api_keys(db, user.id)) >= MAX_KEYS:
        raise ApiError(
            422, "too_many_keys", f"You can have at most {MAX_KEYS} keys. Revoke one first."
        )
    row, key = await auth.create_api_key(db, user, body.name)
    return ApiKeyCreated(**ApiKeyOut.of(row).model_dump(), key=key)


@router.delete("/{key_id}", status_code=204)
async def revoke_key(key_id: uuid.UUID, db: Db, auth: AuthDep, user: SessionUser) -> None:
    """Revoke a key. A tool that uses it is signed out at once."""
    if not await auth.revoke_api_key(db, user.id, key_id):
        raise ApiError(404, "not_found", "There is no such key.")
