"""Work/life context: effective-context resolution and filtering."""

import uuid
from dataclasses import dataclass
from enum import StrEnum
from typing import Protocol

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from tefteri.db.models.connection import Connection, SourceContainer
from tefteri.domain.enums import Context


class ContextFilter(StrEnum):
    """The all/life/work switch."""

    ALL = "all"
    LIFE = "life"
    WORK = "work"


class HasContext(Protocol):
    """Anything that can carry its own context override."""

    context: str | None
    connection_id: uuid.UUID


@dataclass(frozen=True)
class ContextMaps:
    """Container overrides and connection defaults of one user."""

    containers: dict[uuid.UUID, str | None]
    connections: dict[uuid.UUID, str]

    def effective(
        self, item_context: str | None, container_id: uuid.UUID | None, connection_id: uuid.UUID
    ) -> tuple[Context, str]:
        """Return ``(context, source)``: item override, else container, else connection default.

        ``source`` is ``item``, ``container`` or ``connection``. ``connection`` means the item
        has no label of its own (the UI shows the unclassified marker).
        """
        if item_context:
            return Context(item_context), "item"
        container = self.containers.get(container_id) if container_id else None
        if container:
            return Context(container), "container"
        return Context(self.connections[connection_id]), "connection"

    def matches(
        self,
        wanted: ContextFilter,
        item_context: str | None,
        container_id: uuid.UUID | None,
        connection_id: uuid.UUID,
    ) -> bool:
        """Return whether an item passes the filter. ``all`` passes everything."""
        if wanted is ContextFilter.ALL:
            return True
        return self.effective(item_context, container_id, connection_id)[0].value == wanted.value


async def load_maps(db: AsyncSession, user_id: uuid.UUID) -> ContextMaps:
    """Load the user's container overrides and connection defaults."""
    containers = {
        c.id: c.context
        for c in (
            await db.execute(select(SourceContainer).where(SourceContainer.user_id == user_id))
        ).scalars()
    }
    connections = {
        c.id: c.default_context
        for c in (
            await db.execute(select(Connection).where(Connection.user_id == user_id))
        ).scalars()
    }
    return ContextMaps(containers, connections)
