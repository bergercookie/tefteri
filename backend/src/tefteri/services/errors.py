"""Errors raised by services and mapped to HTTP answers by the API layer."""

from collections.abc import Awaitable
from typing import Any

from tefteri.db.models.connection import Connection
from tefteri.domain.errors import (
    AuthExpired,
    BackendUnavailable,
    NotSaved,
    NotSupported,
    RemoteConflict,
)


class BackendProblem(Exception):
    """A connected app could not do what was asked. Nothing was applied or queued."""

    def __init__(self, code: str, connection_name: str, message: str) -> None:
        """Store a stable ``code`` and a message that names the connection."""
        super().__init__(message)
        self.code = code
        self.connection_name = connection_name
        self.message = message
        self.extra: dict[str, Any] = {}
        """More fields for the body of the answer (for example the tasks a close already moved)."""


class NotFound(Exception):
    """A requested item does not exist for this user."""


class Invalid(Exception):
    """The request is not valid. ``code`` is the stable code of the 422 answer."""

    def __init__(self, message: str = "", code: str = "invalid") -> None:
        """Store the ``message`` for the user and a stable ``code`` (default ``invalid``)."""
        super().__init__(message)
        self.code = code


class Conflict(Exception):
    """The request clashes with the state of the data (for example an undo done twice)."""

    def __init__(self, code: str, message: str, *, extra: dict[str, Any] | None = None) -> None:
        """Store a stable ``code``, a user-facing message and extra body fields.

        The extra fields are things like the existing project of ``theme_exists``.
        """
        super().__init__(message)
        self.code = code
        self.message = message
        self.extra: dict[str, Any] = extra or {}


class InvalidTarget(Invalid):
    """A monthly milestone target is not a non-negative whole number or null."""

    def __init__(self) -> None:
        """Create a stable validation error for an invalid target."""
        super().__init__(
            "A target is a whole number of milestones, 0 or more. Leave it empty for no target.",
            "invalid_target",
        )


class NotAFocusTheme(Invalid):
    """A project is not an eligible live theme for a monthly focus."""

    def __init__(self) -> None:
        """Create the 003 eligibility error."""
        super().__init__("That project is not a live theme.", "not_a_theme")


class DuplicateTheme(Invalid):
    """The same project was supplied more than once for one focus."""

    def __init__(self) -> None:
        """Create a duplicate-theme validation error."""
        super().__init__("Choose each theme only once.", "duplicate_theme")


class NotInFocus(Invalid):
    """A focus change named a project that is not currently in the focus."""

    def __init__(self) -> None:
        """Create a missing-focus-theme validation error."""
        super().__init__("That theme is not in this month's focus.", "not_in_focus")


class AlreadyInFocus(Conflict):
    """An add or swap tried to add a theme already in the current focus."""

    def __init__(self) -> None:
        """Create an already-in-focus conflict."""
        super().__init__("already_in_focus", "That theme is already in this month's focus.")


class LeftThisMonth(Conflict):
    """A theme that already left this month's focus was added again."""

    def __init__(self) -> None:
        """Create a left-this-month conflict."""
        super().__init__(
            "left_this_month", "That theme already left this month. Undo that change first."
        )


class UseChanges(Conflict):
    """A saved focus in progress cannot change membership through plan save."""

    def __init__(self) -> None:
        """Create a conflict directing the caller to the change workflow."""
        super().__init__("use_changes", "Use a focus change to change this month's themes.")


class PastMonth(Conflict):
    """A plan save attempted to change a month that has ended."""

    def __init__(self) -> None:
        """Create a past-month conflict."""
        super().__init__("past_month", "A past month cannot be changed.")


class NotCurrentMonth(Conflict):
    """A mid-month focus change targeted another month."""

    def __init__(self) -> None:
        """Create a not-current-month conflict."""
        super().__init__("not_current_month", "Focus changes are available in the current month.")


class FutureMonth(Conflict):
    """A review operation targeted a future month."""

    def __init__(self) -> None:
        """Create a future-month conflict."""
        super().__init__("future_month", "A future month cannot be reviewed.")


class ConfirmRequired(Invalid):
    """Saving a later review version needs explicit confirmation."""

    def __init__(self) -> None:
        """Create a confirmation validation error."""
        super().__init__(
            "Saving creates a new version. The old version stays in the history.",
            "confirm_required",
        )


class NoSuchVersion(NotFound):
    """A review snapshot version does not exist for this user and month."""


class NotUndoable(Conflict):
    """A later change makes the requested focus change impossible to undo."""

    def __init__(self) -> None:
        """Create an undo conflict."""
        super().__init__("not_undoable", "A later focus change means this change cannot be undone.")


class AlreadyUndone(Conflict):
    """A focus change batch has already been undone."""

    def __init__(self) -> None:
        """Create an already-undone conflict."""
        super().__init__("already_undone", "This focus change has already been undone.")


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
    except NotSaved as exc:
        raise BackendProblem(
            "not_saved",
            name,
            f"{name} answered, but it did not keep the change. Nothing was changed in tefteri. "
            f"({exc})",
        ) from exc
    except RemoteConflict as exc:
        raise BackendProblem(
            "remote_conflict", name, f"The item changed in {name}. Sync to see the new version."
        ) from exc
