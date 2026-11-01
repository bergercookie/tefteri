"""Login, logout and identity endpoints."""

import uuid
from datetime import datetime

from fastapi import APIRouter
from pydantic import BaseModel

from tefteri.api.deps import AuthDep, CurrentUser, Db, Token
from tefteri.api.errors import ApiError
from tefteri.auth.service import InvalidCredentials
from tefteri.auth.throttle import Throttled

router = APIRouter(prefix="/auth", tags=["auth"])


class LoginRequest(BaseModel):
    """Username and password."""

    username: str
    password: str


class LoginResponse(BaseModel):
    """Issued bearer token."""

    token: str
    expires_at: datetime


class MeResponse(BaseModel):
    """The signed-in user."""

    id: uuid.UUID
    username: str
    is_admin: bool
    timezone: str


class MethodsResponse(BaseModel):
    """Enabled login methods."""

    password: bool


@router.post("/login")
async def login(body: LoginRequest, db: Db, auth: AuthDep) -> LoginResponse:
    """Exchange username and password for a bearer token."""
    try:
        token, expires = await auth.login(db, body.username, body.password)
    except Throttled as exc:
        raise ApiError(
            429,
            "login_throttled",
            "Too many failed attempts; try again later",
            headers={"Retry-After": str(exc.retry_after)},
        ) from exc
    except InvalidCredentials as exc:
        await db.commit()
        raise ApiError(401, "invalid_credentials", "Invalid username or password") from exc
    return LoginResponse(token=token, expires_at=expires)


@router.post("/logout", status_code=204)
async def logout(db: Db, auth: AuthDep, token: Token) -> None:
    """Invalidate the current token."""
    await auth.logout(db, token)


@router.get("/me")
async def me(user: CurrentUser) -> MeResponse:
    """Return the signed-in user."""
    return MeResponse(
        id=user.id, username=user.username, is_admin=user.is_admin, timezone=user.timezone
    )


@router.get("/methods")
async def methods() -> MethodsResponse:
    """List enabled login methods."""
    return MethodsResponse(password=True)
