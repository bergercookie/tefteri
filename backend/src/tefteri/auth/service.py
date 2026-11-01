"""Admin bootstrap, login, session issuing and token authentication."""

import hashlib
import secrets
from collections.abc import Callable
from datetime import UTC, datetime, timedelta

from sqlalchemy import delete, select
from sqlalchemy.ext.asyncio import AsyncSession

from tefteri.auth.passwords import hash_password, verify_password
from tefteri.auth.throttle import LoginThrottle
from tefteri.db.models.user import AuthSession, User


class InvalidCredentials(Exception):
    """Username or password is wrong, or the account is disabled."""


def _digest(token: str) -> str:
    return hashlib.sha256(token.encode()).hexdigest()


# Verified against when the user does not exist, so timing does not reveal valid usernames.
_DUMMY_HASH = hash_password("tefteri-dummy")


class AuthService:
    """Authentication use cases working on a caller-provided database session."""

    def __init__(
        self,
        throttle: LoginThrottle,
        session_lifetime_seconds: int,
        clock: Callable[[], datetime] = lambda: datetime.now(UTC),
    ) -> None:
        """Configure throttling, session lifetime and the clock."""
        self._throttle = throttle
        self._lifetime = timedelta(seconds=session_lifetime_seconds)
        self._clock = clock

    async def bootstrap_admin(self, db: AsyncSession, username: str, password_hash: str) -> User:
        """Create the admin user, or sync its hash from configuration, at startup."""
        user = (
            await db.execute(select(User).where(User.username == username))
        ).scalar_one_or_none()
        if user is None:
            user = User(username=username, password_hash=password_hash, is_admin=True)
            db.add(user)
        else:
            user.password_hash = password_hash
            user.is_admin = True
            user.disabled = False
        await db.flush()
        return user

    async def login(self, db: AsyncSession, username: str, password: str) -> tuple[str, datetime]:
        """Verify credentials and return ``(token, expires_at)``.

        Raises:
            Throttled: too many recent failures for this username.
            InvalidCredentials: bad username/password or disabled account.
        """
        key = username.lower()
        self._throttle.check(key)
        user = (
            await db.execute(select(User).where(User.username == username))
        ).scalar_one_or_none()
        ok = verify_password(
            user.password_hash if user and user.password_hash else _DUMMY_HASH, password
        )
        if user is None or user.password_hash is None or user.disabled or not ok:
            self._throttle.record_failure(key)
            raise InvalidCredentials
        self._throttle.record_success(key)
        return await self.issue_session(db, user)

    async def issue_session(self, db: AsyncSession, user: User) -> tuple[str, datetime]:
        """Create a session for ``user``."""
        token = secrets.token_urlsafe(32)
        expires = self._clock() + self._lifetime
        db.add(AuthSession(user_id=user.id, token_hash=_digest(token), expires_at=expires))
        await db.flush()
        return token, expires

    async def authenticate(self, db: AsyncSession, token: str) -> User | None:
        """Return the user for a valid, unexpired token; ``None`` otherwise."""
        row = (
            await db.execute(select(AuthSession).where(AuthSession.token_hash == _digest(token)))
        ).scalar_one_or_none()
        if row is None:
            return None
        expires = row.expires_at if row.expires_at.tzinfo else row.expires_at.replace(tzinfo=UTC)
        if expires <= self._clock():
            await db.delete(row)
            await db.flush()
            return None
        user = await db.get(User, row.user_id)
        if user is None or user.disabled:
            return None
        return user

    async def logout(self, db: AsyncSession, token: str) -> None:
        """Invalidate a token."""
        await db.execute(delete(AuthSession).where(AuthSession.token_hash == _digest(token)))
