"""Links to a task or a project in the task app, for the screens that show one."""

from tefteri.db.models.connection import Connection


def task_base_url(connection: Connection | None) -> str | None:
    """Return a task connection's web base address when it provides one."""
    if connection is None or connection.kind != "tasks":
        return None
    base = str(connection.settings.get("base_url", "")).rstrip("/")
    return base or None


def task_url(base: str | None, remote_id: str) -> str | None:
    """The address of one task, or ``None`` when the task app has no pages."""
    return f"{base}/tasks/{remote_id}" if base else None
