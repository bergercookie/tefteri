"""Exceptions raised by backend adapters and the services built on them."""

from tefteri.domain.enums import Capability


class BackendError(Exception):
    """Base class for adapter failures."""


class BackendUnavailable(BackendError):
    """The connected application cannot be reached."""


class AuthExpired(BackendError):
    """Credentials for the connected application expired or were revoked."""


class NotSupported(BackendError):
    """The connected application does not support the requested capability."""

    def __init__(self, capability: Capability) -> None:
        """Remember which capability is missing."""
        super().__init__(f"capability not supported: {capability.value}")
        self.capability = capability


class NotSaved(BackendError):
    """The application accepted a change but did not keep it.

    The adapter read the item back and found the old value. Tefteri shows this at once, so that
    the user does not see a change that the next sync would take back.
    """


class RemoteConflict(BackendError):
    """The remote item changed since the cached version was read."""
