"""Administrator-only user management."""

import uuid

from fastapi import APIRouter, Request
from pydantic import BaseModel, Field

from tefteri.api.deps import AdminUser, Db
from tefteri.api.errors import ApiError
from tefteri.db.models.user import User
from tefteri.services.users import NotAllowed, UsernameTaken, UserService

router = APIRouter(prefix="/users", tags=["users"])


def _service(request: Request) -> UserService:
    service: UserService = request.app.state.user_service
    return service


class UserOut(BaseModel):
    """A user as shown to administrators. Password hashes are never returned."""

    id: uuid.UUID
    username: str
    is_admin: bool
    timezone: str
    disabled: bool

    @classmethod
    def of(cls, u: User) -> "UserOut":
        """Build from the ORM row."""
        return cls(
            id=u.id,
            username=u.username,
            is_admin=u.is_admin,
            timezone=u.timezone,
            disabled=u.disabled,
        )


class UserIn(BaseModel):
    """Data to create a user."""

    username: str = Field(min_length=1, max_length=150)
    password: str
    is_admin: bool = False
    timezone: str = "UTC"


class UserPatch(BaseModel):
    """Partial user update. A new ``password`` resets a forgotten one."""

    password: str | None = None
    is_admin: bool | None = None
    disabled: bool | None = None
    timezone: str | None = None


_NOT_ALLOWED = ApiError(
    409, "not_allowed", "You cannot remove or disable yourself or the last administrator"
)


@router.get("")
async def list_users(request: Request, db: Db, admin: AdminUser) -> list[UserOut]:  # noqa: ARG001
    """List all users."""
    return [UserOut.of(u) for u in await _service(request).list(db)]


@router.post("", status_code=201)
async def create_user(body: UserIn, request: Request, db: Db, admin: AdminUser) -> UserOut:  # noqa: ARG001
    """Create a user."""
    try:
        user = await _service(request).create(db, **body.model_dump())
    except UsernameTaken as exc:
        raise ApiError(409, "username_taken", "This username is already in use") from exc
    return UserOut.of(user)


@router.patch("/{user_id}")
async def update_user(
    user_id: uuid.UUID, body: UserPatch, request: Request, db: Db, admin: AdminUser
) -> UserOut:
    """Change a user, set a new password, or disable an account."""
    service = _service(request)
    user = await service.get(db, user_id)
    try:
        updated = await service.update(db, admin, user, **body.model_dump(exclude_unset=True))
    except NotAllowed as exc:
        raise _NOT_ALLOWED from exc
    return UserOut.of(updated)


@router.delete("/{user_id}", status_code=204)
async def delete_user(user_id: uuid.UUID, request: Request, db: Db, admin: AdminUser) -> None:
    """Delete a user and all of the user's data."""
    service = _service(request)
    try:
        await service.delete(db, admin, await service.get(db, user_id))
    except NotAllowed as exc:
        raise _NOT_ALLOWED from exc
