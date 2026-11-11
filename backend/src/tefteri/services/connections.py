"""Adapter registry and connection management (credentials are encrypted at rest)."""

import json
import uuid
from collections.abc import Callable, Sequence
from typing import Any

from sqlalchemy.ext.asyncio import AsyncSession

from tefteri.db.models.connection import Connection
from tefteri.db.models.user import User
from tefteri.db.repositories.connections import ConnectionRepository
from tefteri.domain.capabilities import (
    CapabilityReport,
    missing_message,
    missing_required,
    report_for,
)
from tefteri.domain.entities import ConnectionHealth
from tefteri.domain.enums import ConnectionKind, ConnectionStatus
from tefteri.domain.ports import Backend
from tefteri.security.crypto import TokenCipher

BackendFactory = Callable[[dict[str, Any], dict[str, Any]], Backend]
"""Builds a backend from a connection's ``settings`` and decrypted ``credentials``."""


class UnknownProvider(Exception):
    """No adapter is registered for the requested provider."""


class InvalidConnection(Exception):
    """The connection data is not valid (for example a kind that does not match the provider)."""


class MissingCapability(Exception):
    """A task app lacks a capability that tefteri needs (spec 003, FR-015)."""

    def __init__(self, missing: list[str], message: str) -> None:
        """Keep the names of the missing capabilities and a message that names them."""
        super().__init__(message)
        self.missing = missing
        self.message = message


class AdapterRegistry:
    """Maps a provider name to the adapter factory and the kind of app it serves."""

    def __init__(self) -> None:
        """Start with no adapters."""
        self._factories: dict[str, tuple[ConnectionKind, BackendFactory]] = {}

    def register(self, provider: str, kind: ConnectionKind, factory: BackendFactory) -> None:
        """Register ``factory`` for ``provider``."""
        self._factories[provider] = (kind, factory)

    def kind_of(self, provider: str) -> ConnectionKind:
        """Return the kind of app a provider serves."""
        try:
            return self._factories[provider][0]
        except KeyError as exc:
            raise UnknownProvider(provider) from exc

    def providers(self) -> list[str]:
        """List registered providers."""
        return sorted(self._factories)

    def build(
        self, provider: str, settings: dict[str, Any], credentials: dict[str, Any]
    ) -> Backend:
        """Create the backend for a connection."""
        try:
            factory = self._factories[provider][1]
        except KeyError as exc:
            raise UnknownProvider(provider) from exc
        return factory(settings, credentials)


class ConnectionService:
    """Create, read, update and delete the current user's connections."""

    def __init__(self, registry: AdapterRegistry, cipher: TokenCipher) -> None:
        """Use ``registry`` to validate providers and ``cipher`` to protect credentials."""
        self.registry = registry
        self._cipher = cipher

    def credentials_of(self, connection: Connection) -> dict[str, Any]:
        """Decrypt a connection's credentials."""
        if not connection.encrypted_credentials:
            return {}
        data: dict[str, Any] = json.loads(self._cipher.decrypt(connection.encrypted_credentials))
        return data

    def backend_for(self, connection: Connection, timezone: str = "UTC") -> Backend:
        """Build the backend for ``connection``; ``timezone`` is the owner's time zone."""
        return self.registry.build(
            connection.provider,
            {**connection.settings, "timezone": timezone},
            self.credentials_of(connection),
        )

    async def backend_of_owner(self, db: AsyncSession, connection: Connection) -> Backend:
        """Build the backend for ``connection`` using its owner's time zone."""
        owner = await db.get(User, connection.user_id)
        return self.backend_for(connection, owner.timezone if owner else "UTC")

    async def check(self, db: AsyncSession, connection: Connection) -> ConnectionHealth:
        """Ask the app whether the address and the credentials work, and store the status.

        Never raises: a connection with missing settings or a failing adapter gives an
        ``error`` health with a message.
        """
        try:
            backend = await self.backend_of_owner(db, connection)
            health = await backend.check_connection()
        except KeyError as exc:
            health = ConnectionHealth(
                ConnectionStatus.ERROR, "error", f"The setting {exc} is missing."
            )
        except Exception as exc:  # noqa: BLE001 - any adapter failure is a result, not a crash
            health = ConnectionHealth(
                ConnectionStatus.ERROR, "error", str(exc) or type(exc).__name__
            )
        if health.status is ConnectionStatus.OK and connection.kind == ConnectionKind.TASKS.value:
            missing = missing_required(backend.capabilities())
            if missing:
                health = ConnectionHealth(
                    ConnectionStatus.ERROR, "missing_capability", missing_message(missing)
                )
        connection.status = health.status.value
        await db.flush()
        return health

    async def capability_report(self, db: AsyncSession, connection: Connection) -> CapabilityReport:
        """Say which required capabilities a connection lacks and which optional ones it has.

        Only a task connection has them. For any other kind, or when the adapter cannot be
        built (a setting is missing), the report is empty.
        """
        if connection.kind != ConnectionKind.TASKS.value:
            return CapabilityReport([], {})
        try:
            backend = await self.backend_of_owner(db, connection)
        except Exception:  # noqa: BLE001 - a connection that cannot be built has no report
            return CapabilityReport([], {})
        return report_for(backend.capabilities())

    async def list(self, db: AsyncSession, user_id: uuid.UUID) -> Sequence[Connection]:
        """List the user's connections."""
        return await ConnectionRepository(db, user_id).list()

    async def get(
        self, db: AsyncSession, user_id: uuid.UUID, connection_id: uuid.UUID
    ) -> Connection | None:
        """Return one of the user's connections, or ``None``."""
        return await ConnectionRepository(db, user_id).get(connection_id)

    async def create(
        self,
        db: AsyncSession,
        user_id: uuid.UUID,
        *,
        provider: str,
        display_name: str,
        settings: dict[str, Any],
        credentials: dict[str, Any],
    ) -> Connection:
        """Create a connection. The kind follows from the provider."""
        kind = self.registry.kind_of(provider)
        if kind is ConnectionKind.TASKS:
            self._require_capabilities(provider, settings, credentials)
        connection = Connection(
            kind=kind.value,
            provider=provider,
            display_name=display_name,
            settings=settings,
            encrypted_credentials=self._cipher.encrypt(json.dumps(credentials)),
            status=ConnectionStatus.OK.value,
        )
        return await ConnectionRepository(db, user_id).add(connection)

    def _require_capabilities(
        self, provider: str, settings: dict[str, Any], credentials: dict[str, Any]
    ) -> None:
        """Refuse a task app that lacks a required capability, and name it (FR-015).

        An adapter that cannot be built yet (a setting is missing) is not refused here: the
        first sync and ``check`` report that problem.
        """
        try:
            backend = self.registry.build(provider, {**settings, "timezone": "UTC"}, credentials)
        except UnknownProvider:
            raise
        except Exception:  # noqa: BLE001 - the sync says what is wrong with the settings
            return
        missing = missing_required(backend.capabilities())
        if missing:
            raise MissingCapability([c.value for c in missing], missing_message(missing))

    async def update(
        self,
        db: AsyncSession,
        connection: Connection,
        *,
        display_name: str | None = None,
        settings: dict[str, Any] | None = None,
        credentials: dict[str, Any] | None = None,
    ) -> Connection:
        """Change a connection; new credentials reset a ``needs_attention`` status."""
        if display_name is not None:
            connection.display_name = display_name
        if settings is not None:
            connection.settings = settings
        if credentials is not None:
            connection.encrypted_credentials = self._cipher.encrypt(json.dumps(credentials))
            connection.status = ConnectionStatus.OK.value
        await db.flush()
        return connection

    async def delete(self, db: AsyncSession, user_id: uuid.UUID, connection: Connection) -> None:
        """Delete a connection and, through cascades, its cached items."""
        await ConnectionRepository(db, user_id).delete(connection)
