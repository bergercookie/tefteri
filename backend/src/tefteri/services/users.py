"""User management (administrators only) and password rules."""

import uuid
from collections.abc import Sequence

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from tefteri.auth.passwords import hash_password
from tefteri.db.models.user import User
from tefteri.services.errors import Invalid, NotFound

MIN_PASSWORD_LENGTH = 8


class UsernameTaken(Exception):
    """Another user already has this username."""


class NotAllowed(Exception):
    """The action would lock the administrators out (self or last administrator)."""


def check_password(password: str) -> None:
    """Raise ``Invalid`` when ``password`` is too short."""
    if len(password) < MIN_PASSWORD_LENGTH:
        raise Invalid(f"the password must have at least {MIN_PASSWORD_LENGTH} characters")


class UserService:
    """Create, change and delete users. Only administrators call these methods."""

    async def list(self, db: AsyncSession) -> Sequence[User]:
        """List all users by name."""
        return (await db.execute(select(User).order_by(User.username))).scalars().all()

    async def get(self, db: AsyncSession, user_id: uuid.UUID) -> User:
        """Return a user or raise ``NotFound``."""
        user = await db.get(User, user_id)
        if user is None:
            raise NotFound
        return user

    async def create(
        self,
        db: AsyncSession,
        *,
        username: str,
        password: str,
        is_admin: bool = False,
        timezone: str = "UTC",
    ) -> User:
        """Create a user with a password hash. There is no self-registration."""
        check_password(password)
        taken = await db.execute(select(User).where(func.lower(User.username) == username.lower()))
        if taken.scalar_one_or_none() is not None:
            raise UsernameTaken
        user = User(
            username=username,
            password_hash=hash_password(password),
            is_admin=is_admin,
            timezone=timezone,
        )
        db.add(user)
        await db.flush()
        return user

    async def _other_admins(self, db: AsyncSession, user: User) -> int:
        count = await db.execute(
            select(func.count())
            .select_from(User)
            .where(User.is_admin.is_(True), User.disabled.is_(False), User.id != user.id)
        )
        return int(count.scalar_one())

    async def update(
        self,
        db: AsyncSession,
        acting: User,
        user: User,
        *,
        password: str | None = None,
        is_admin: bool | None = None,
        disabled: bool | None = None,
        timezone: str | None = None,
    ) -> User:
        """Change a user. A new password resets a forgotten one.

        Raises ``NotAllowed`` when an administrator would disable or demote themselves, or when
        the last enabled administrator would lose the role.
        """
        removes_admin = (is_admin is False and user.is_admin) or (
            disabled is True and user.is_admin
        )
        if removes_admin and (user.id == acting.id or await self._other_admins(db, user) == 0):
            raise NotAllowed
        if disabled is True and user.id == acting.id:
            raise NotAllowed
        if password is not None:
            check_password(password)
            user.password_hash = hash_password(password)
        if is_admin is not None:
            user.is_admin = is_admin
        if disabled is not None:
            user.disabled = disabled
        if timezone is not None:
            user.timezone = timezone
        await db.flush()
        return user

    async def delete(self, db: AsyncSession, acting: User, user: User) -> None:
        """Delete a user and, through cascades, all of the user's data."""
        if user.id == acting.id or (user.is_admin and await self._other_admins(db, user) == 0):
            raise NotAllowed
        await db.delete(user)
        await db.flush()
