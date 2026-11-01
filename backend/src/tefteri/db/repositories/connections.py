"""Repositories for connections and containers."""

from tefteri.db.models.connection import Connection, SourceContainer
from tefteri.db.repositories.base import ScopedRepository


class ConnectionRepository(ScopedRepository[Connection]):
    """User-scoped access to connections."""

    model = Connection


class ContainerRepository(ScopedRepository[SourceContainer]):
    """User-scoped access to source containers."""

    model = SourceContainer
