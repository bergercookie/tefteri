"""Enumerations shared across the domain, persistence and API layers."""

from enum import StrEnum


class Context(StrEnum):
    """Work/life label of an item."""

    WORK = "work"
    LIFE = "life"


class ConnectionKind(StrEnum):
    """Kind of external application a connection talks to."""

    TASKS = "tasks"
    CALENDAR = "calendar"
    NOTES = "notes"


class ConnectionStatus(StrEnum):
    """Health of a connection."""

    OK = "ok"
    NEEDS_ATTENTION = "needs_attention"
    ERROR = "error"


class SyncState(StrEnum):
    """Synchronisation state of a cached item."""

    SYNCED = "synced"
    CONFLICT = "conflict"
    DELETED_REMOTELY = "deleted_remotely"


class Resolution(StrEnum):
    """How the user resolved a conflict."""

    KEEP_LOCAL = "keep_local"
    KEEP_REMOTE = "keep_remote"


class Capability(StrEnum):
    """Optional features an adapter may support."""

    TASK_TIME = "task_time"
    RECURRING = "recurring"
    NOTE_APPEND = "note_append"
