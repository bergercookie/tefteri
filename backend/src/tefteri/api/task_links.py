"""Links to a task or a project in the task app, for the screens that show one."""

from tefteri.db.models.connection import Connection


def task_base_url(connection: Connection | None) -> str | None:
    """The address of the task app, when it has pages for projects and tasks."""
    if connection is not None and connection.provider == "vikunja":
        base = str(connection.settings.get("base_url", "")).rstrip("/")
        return base or None
    return None


def task_url(base: str | None, remote_id: str) -> str | None:
    """The address of one task, or ``None`` when the task app has no pages."""
    return f"{base}/tasks/{remote_id}" if base else None
