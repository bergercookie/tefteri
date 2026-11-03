"""FastAPI dependencies: database session, services and the authenticated user."""

from collections.abc import AsyncIterator
from typing import Annotated

from fastapi import Depends, Request
from sqlalchemy.ext.asyncio import AsyncSession

from tefteri.api.errors import ApiError
from tefteri.auth.service import AuthService
from tefteri.config import Settings
from tefteri.db.models.user import User
from tefteri.db.session import session_scope


def get_settings(request: Request) -> Settings:
    """Return the application settings."""
    settings: Settings = request.app.state.settings
    return settings


def get_auth_service(request: Request) -> AuthService:
    """Return the auth service."""
    service: AuthService = request.app.state.auth_service
    return service


async def get_db(request: Request) -> AsyncIterator[AsyncSession]:
    """Yield a transactional database session for one request."""
    async with session_scope(request.app.state.session_factory) as session:
        yield session


Db = Annotated[AsyncSession, Depends(get_db)]
SettingsDep = Annotated[Settings, Depends(get_settings)]
AuthDep = Annotated[AuthService, Depends(get_auth_service)]


SESSION_COOKIE = "tefteri_session"
CLIENT_HEADER = "x-tefteri-client"
_SAFE_METHODS = frozenset({"GET", "HEAD", "OPTIONS"})


def session_token(request: Request) -> str:
    """Return the session token from the bearer header or the session cookie, or raise 401.

    Native clients send a bearer token; the web client relies on the HttpOnly cookie set at
    login, so a page reload keeps the session. A request that changes data through the cookie
    must also carry ``X-Tefteri-Client``: another site cannot add that header without a CORS
    preflight, which this server never allows, so a forged cross-site request fails (CSRF).
    """
    header = request.headers.get("authorization", "")
    scheme, _, token = header.partition(" ")
    if scheme.lower() == "bearer" and token:
        return token
    cookie = request.cookies.get(SESSION_COOKIE)
    if not cookie:
        raise ApiError(401, "not_authenticated", "Authentication required")
    if request.method not in _SAFE_METHODS and CLIENT_HEADER not in request.headers:
        raise ApiError(
            403, "missing_client_header", "Requests with the session cookie need X-Tefteri-Client"
        )
    return cookie


Token = Annotated[str, Depends(session_token)]


async def current_user(db: Db, auth: AuthDep, token: Token) -> User:
    """Return the authenticated user or raise 401."""
    user = await auth.authenticate(db, token)
    if user is None:
        raise ApiError(401, "not_authenticated", "Invalid or expired session")
    return user


CurrentUser = Annotated[User, Depends(current_user)]


async def admin_user(user: CurrentUser) -> User:
    """Return the authenticated user if they are an administrator, else raise 403."""
    if not user.is_admin:
        raise ApiError(403, "forbidden", "Only administrators can do this")
    return user


AdminUser = Annotated[User, Depends(admin_user)]
