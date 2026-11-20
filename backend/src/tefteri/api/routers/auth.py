"""Login, logout and identity endpoints."""

import uuid

from fastapi import APIRouter, Request, Response
from pydantic import BaseModel

from tefteri.api.deps import (
    COOKIE_PATH,
    SESSION_COOKIE,
    AuthDep,
    CurrentUser,
    Db,
    SettingsDep,
    Token,
    set_session_cookie,
)
from tefteri.api.errors import ApiError
from tefteri.api.schemas import UtcDatetime
from tefteri.auth.passwords import hash_password
from tefteri.auth.service import InvalidCredentials
from tefteri.auth.throttle import Throttled
from tefteri.services.errors import Invalid
from tefteri.services.users import check_password

router = APIRouter(prefix="/auth", tags=["auth"])


class LoginRequest(BaseModel):
    """Username and password."""

    username: str
    password: str
    remember: bool = False
    """Stay signed in: the session lasts 30 days (by default) instead of 8 hours."""


class LoginResponse(BaseModel):
    """Issued bearer token."""

    token: str
    expires_at: UtcDatetime


class MeResponse(BaseModel):
    """The signed-in user."""

    id: uuid.UUID
    username: str
    is_admin: bool
    timezone: str


class PasswordChange(BaseModel):
    """Current and new password."""

    current_password: str
    new_password: str


class MethodsResponse(BaseModel):
    """Enabled login methods."""

    password: bool


@router.post("/login")
async def login(
    body: LoginRequest,
    db: Db,
    auth: AuthDep,
    request: Request,
    response: Response,
    settings: SettingsDep,
) -> LoginResponse:
    """Exchange username and password for a session token.

    The token is also set as an HttpOnly, SameSite=Strict cookie so the web client stays
    signed in across reloads without page scripts ever being able to read the token.
    """
    try:
        token, expires = await auth.login(db, body.username, body.password, body.remember)
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
    set_session_cookie(response, request, settings, token, expires)
    return LoginResponse(token=token, expires_at=expires)


@router.post("/logout", status_code=204)
async def logout(db: Db, auth: AuthDep, token: Token, response: Response) -> None:
    """Invalidate the current token and clear the session cookie."""
    await auth.logout(db, token)
    response.delete_cookie(SESSION_COOKIE, path=COOKIE_PATH, httponly=True, samesite="strict")


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


@router.post("/password", status_code=204)
async def change_password(
    body: PasswordChange, db: Db, auth: AuthDep, user: CurrentUser, token: Token
) -> None:
    """Change your own password. Your other sessions end."""
    try:
        check_password(body.new_password)
    except Invalid as exc:
        raise ApiError(422, "invalid", str(exc)) from exc
    try:
        await auth.change_password(
            db, user, body.current_password, hash_password(body.new_password), token
        )
    except InvalidCredentials as exc:
        await db.rollback()
        raise ApiError(401, "invalid_credentials", "The current password is wrong") from exc
