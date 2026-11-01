"""Repository base enforcing ``user_id`` scoping on every query (FR-015)."""

import uuid
from collections.abc import Sequence
from typing import Any, ClassVar, cast

from sqlalchemy import ColumnElement, Select, select
from sqlalchemy.ext.asyncio import AsyncSession

from tefteri.db.base import Base


class ScopedRepository[M: Base]:
    """Data access for one model; every operation is limited to one user's rows."""

    model: ClassVar[type[Any]]

    def __init__(self, session: AsyncSession, user_id: uuid.UUID) -> None:
        """Bind the repository to a session and the owning user."""
        self._session = session
        self._user_id = user_id

    @property
    def _user_col(self) -> ColumnElement[Any]:
        return self.model.user_id  # type: ignore[no-any-return]

    def _select(self) -> Select[Any]:
        return select(self.model).where(self._user_col == self._user_id)

    async def get(self, entity_id: uuid.UUID) -> M | None:
        """Return the user's row with this id, or ``None`` (also for other users' rows)."""
        result = await self._session.execute(self._select().where(self.model.id == entity_id))
        return cast(M | None, result.scalar_one_or_none())

    async def list(self, *conditions: ColumnElement[bool]) -> Sequence[M]:
        """Return the user's rows matching all ``conditions``."""
        result = await self._session.execute(self._select().where(*conditions))
        return cast(Sequence[M], result.scalars().all())

    async def add(self, entity: M) -> M:
        """Insert a row owned by this user (the owner is forced, never taken from input)."""
        entity.user_id = self._user_id  # type: ignore[attr-defined]
        self._session.add(entity)
        await self._session.flush()
        return entity

    async def delete(self, entity: M) -> None:
        """Delete a row, refusing rows of another user."""
        if entity.user_id != self._user_id:  # type: ignore[attr-defined]
            raise PermissionError("row belongs to another user")
        await self._session.delete(entity)
        await self._session.flush()
