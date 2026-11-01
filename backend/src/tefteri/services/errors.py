"""Errors raised by services and mapped to HTTP answers by the API layer."""

from collections.abc import Awaitable

from tefteri.db.models.connection import Connection
from tefteri.domain.errors import AuthExpired, BackendUnavailable, NotSupported, RemoteConflict


class BackendProblem(Exception):
    """A connected app could not do what was asked. Nothing was applied or queued."""

    def __init__(self, code: str, connection_name: str, message: str) -> None:
        """Store a stable ``code`` and a message that names the connection."""
        super().__init__(message)
        self.code = code
        self.connection_name = connection_name
        self.message = message


class NotFound(Exception):
    """A requested item does not exist for this user."""


class Invalid(Exception):
    """The request is not valid."""


async def guard[T](connection: Connection, call: Awaitable[T]) -> T:
    """Await a backend call and turn adapter errors into ``BackendProblem``."""
    name = connection.display_name
    try:
        return await call
    except BackendUnavailable as exc:
        raise BackendProblem(
            "backend_unavailable", name, f"{name} cannot be reached. Nothing was changed."
        ) from exc
    except AuthExpired as exc:
        raise BackendProblem(
            "auth_expired",
            name,
            f"The credentials for {name} expired or were revoked. "
            "Reconnect it. Nothing was changed.",
        ) from exc
    except NotSupported as exc:
        raise BackendProblem(
            "not_supported", name, f"{name} does not support this action ({exc.capability.value})."
        ) from exc
    except RemoteConflict as exc:
        raise BackendProblem(
            "remote_conflict", name, f"The item changed in {name}. Sync to see the new version."
        ) from exc
