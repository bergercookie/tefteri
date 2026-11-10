"""Vikunja task adapter (REST API v1, API-token auth)."""

import hashlib
import json
import logging
import re
from datetime import UTC, datetime, time
from typing import Any
from zoneinfo import ZoneInfo

import httpx

from tefteri.adapters.http import request
from tefteri.domain.colors import normalize_color
from tefteri.domain.entities import (
    ConnectionHealth,
    Container,
    RemoteTask,
    TaskDraft,
    TaskPage,
    TaskPatch,
)
from tefteri.domain.enums import Capability, ConnectionStatus
from tefteri.domain.errors import AuthExpired, BackendUnavailable, NotSaved, RemoteConflict

logger = logging.getLogger(__name__)

_ZERO_DATE = "0001-01-01T00:00:00Z"
_PAGE_SIZE = 50
_VERSIONED_FIELDS = (
    "project_id",
    "title",
    "description",
    "done",
    "due_date",
)


def _parse(value: str | None) -> datetime | None:
    if not value or value == _ZERO_DATE:
        return None
    # Vikunja writes times in the time zone of its server (for example ``+02:00``).
    return datetime.fromisoformat(value.replace("Z", "+00:00")).astimezone(UTC)


def _fmt(value: datetime | None) -> str:
    return value.astimezone(UTC).strftime("%Y-%m-%dT%H:%M:%SZ") if value else _ZERO_DATE


_FRACTION = re.compile(r"\.\d+")


def _stamp(value: object) -> str:
    """Return a Vikunja timestamp as UTC whole seconds, so that its forms compare equal.

    Vikunja answers a create or update with the task as it is in memory (``updated`` with
    nanoseconds, for example ``2026-11-03T21:04:25.982515748Z``). A later read gives what the
    database stored (``2026-11-03T21:04:25Z``). The same task must have the same version in
    both forms. Anything that is not a timestamp is returned as it is.
    """
    text = str(value or "")
    try:
        parsed = datetime.fromisoformat(_FRACTION.sub("", text).replace("Z", "+00:00"))
    except ValueError:
        return text
    return parsed.astimezone(UTC).strftime("%Y-%m-%dT%H:%M:%SZ")


def _version(data: dict[str, Any]) -> str:
    """Return the task's version: its ``updated`` stamp plus a digest of the mapped fields.

    Vikunja has no optimistic locking and ``updated`` has second resolution, so two writes
    within one second share a stamp; the digest tells them apart.
    """
    fields = json.dumps(
        [
            _stamp(data.get(name)) if name == "due_date" else data.get(name)
            for name in _VERSIONED_FIELDS
        ],
        default=str,
    )
    digest = hashlib.sha256(fields.encode()).hexdigest()[:12]
    return f"{_stamp(data.get('updated'))}#{digest}"


class VikunjaTaskBackend:
    """``TaskBackend`` for a Vikunja server. Projects are containers."""

    def __init__(
        self,
        client: httpx.AsyncClient,
        base_url: str,
        token: str,
        timezone: str = "UTC",
    ) -> None:
        """Use ``client`` (injectable for tests) against ``base_url`` with an API ``token``.

        ``timezone`` is the user's time zone. Vikunja has no all-day flag, so a date-only due
        date is stored as 00:00 in this zone and read back the same way (research R-03).
        """
        self._tz = ZoneInfo(timezone)
        self._client = client
        self._base = base_url.rstrip("/") + "/api/v1"
        self._headers = {"Authorization": f"Bearer {token}"}

    def capabilities(self) -> set[Capability]:
        """Vikunja stores the due date and time of a task, and recurrence."""
        return {
            Capability.TASK_TIME,
            Capability.RECURRING,
            Capability.SUBPROJECTS,
            Capability.ARCHIVE_PROJECTS,
        }

    async def _call(self, method: str, path: str, **kwargs: Any) -> Any:
        # Vikunja answers 412 for invalid data and 409 for duplicates, never for a version
        # mismatch (versions are checked here), so neither means ``RemoteConflict``.
        response = await request(
            self._client,
            method,
            self._base + path,
            headers=self._headers,
            ok_conflict_statuses=(),
            **kwargs,
        )
        return response.json()

    def _task(self, data: dict[str, Any]) -> RemoteTask:
        # Only the due date is read: it is the single planning date (constitution VII).
        due = _parse(data.get("due_date"))
        return RemoteTask(
            remote_id=str(data["id"]),
            container_id=str(data["project_id"]),
            title=data["title"],
            description=data.get("description", "") or "",
            done=bool(data.get("done")),
            done_at=_parse(data.get("done_at")) if data.get("done") else None,
            due_at=due,
            all_day=due is not None and due.astimezone(self._tz).time() == time.min,
            version=_version(data),
            labels=tuple(
                str(label["title"]) for label in data.get("labels") or [] if label.get("title")
            ),
        )

    async def list_containers(self) -> list[Container]:
        """List projects. A subproject names its parent.

        Vikunja also lists its saved filters here, as projects with a negative id. A filter
        holds no tasks of its own (they belong to real projects) and cannot be written to, so
        it is not a container.
        """
        data = await self._call("GET", "/projects")
        return [
            Container(
                str(p["id"]),
                p["title"],
                str(p["parent_project_id"]) if p.get("parent_project_id") else None,
                color=normalize_color(p.get("hex_color")),
            )
            for p in data
            if int(p["id"]) > 0
        ]

    async def archive_container(self, container: Container) -> None:
        """Archive a project (and, in Vikunja, its subprojects). It can be restored there."""
        path = f"/projects/{container.remote_id}"
        project = await self._call("GET", path)
        project["is_archived"] = True
        await self._call("POST", path, json=project)
        # Read it back: a change that Vikunja did not keep must not look like a success.
        if not (await self._call("GET", path)).get("is_archived"):
            raise NotSaved(f"project {container.remote_id} is not archived")

    async def create_container(self, name: str, parent: Container | None) -> Container:
        """Create a project, as a subproject of ``parent`` when given."""
        body: dict[str, Any] = {"title": name}
        if parent is not None:
            body["parent_project_id"] = int(parent.remote_id)
        data = await self._call("PUT", "/projects", json=body)
        return Container(
            str(data["id"]),
            data["title"],
            str(data["parent_project_id"]) if data.get("parent_project_id") else None,
            color=normalize_color(data.get("hex_color")),
        )

    async def check_connection(self) -> ConnectionHealth:
        """Check the token by listing projects."""
        try:
            await self._call("GET", "/projects")
        except AuthExpired:
            return ConnectionHealth(ConnectionStatus.NEEDS_ATTENTION, "auth_expired")
        except BackendUnavailable:
            return ConnectionHealth(ConnectionStatus.ERROR, "unreachable")
        return ConnectionHealth(ConnectionStatus.OK)

    async def list_tasks(self, container: Container, since: str | None) -> TaskPage:  # noqa: ARG002
        """List all tasks of a project (follows pagination)."""
        tasks: list[RemoteTask] = []
        page = 1
        while True:
            data = await self._call(
                "GET",
                f"/projects/{container.remote_id}/tasks",
                params={"page": page, "per_page": _PAGE_SIZE},
            )
            tasks.extend(self._task(t) for t in data)
            if len(data) < _PAGE_SIZE:
                return TaskPage(items=tasks)
            page += 1

    async def get_task(self, remote_id: str) -> RemoteTask:
        """Fetch one task."""
        return self._task(await self._call("GET", f"/tasks/{remote_id}"))

    async def _labels(self) -> dict[str, dict[str, Any]]:
        """Return the labels of the user by lower-case title (follows pagination)."""
        found: dict[str, dict[str, Any]] = {}
        page = 1
        while True:
            data = await self._call("GET", "/labels", params={"page": page, "per_page": _PAGE_SIZE})
            for label in data or []:
                found.setdefault(str(label["title"]).casefold(), label)
            if len(data or []) < _PAGE_SIZE:
                return found
            page += 1

    async def list_labels(self) -> list[str]:
        """List the names of the labels, in alphabetical order."""
        return sorted((str(v["title"]) for v in (await self._labels()).values()), key=str.casefold)

    async def _put_labels(self, task_id: object, names: tuple[str, ...]) -> None:
        """Put the labels ``names`` on a task; create the ones that do not exist."""
        known = await self._labels()
        ids: dict[int, None] = {}  # in order, and each label once: "home" and "Home" are one
        for name in (n.strip() for n in names if n.strip()):
            label = known.get(name.casefold())
            if label is None:
                label = await self._call("PUT", "/labels", json={"title": name})
                known[name.casefold()] = label
            ids[int(label["id"])] = None
        if ids:
            await self._call(
                "POST", f"/tasks/{task_id}/labels/bulk", json={"labels": [{"id": i} for i in ids]}
            )

    async def create_task(self, draft: TaskDraft) -> RemoteTask:
        """Create a task in a project, with its labels."""
        body: dict[str, Any] = {"title": draft.title, "description": draft.description}
        if draft.due_at:
            body["due_date"] = _fmt(draft.due_at)
        data = await self._call("PUT", f"/projects/{draft.container_id}/tasks", json=body)
        if draft.labels:
            await self._put_labels(data["id"], draft.labels)
            # Read it back: the answer to the create does not have the labels.
            data = await self._call("GET", f"/tasks/{data['id']}")
        return self._task(data)

    async def _update(
        self, remote_id: str, expected_version: str | None, changes: dict[str, Any]
    ) -> RemoteTask:
        current = await self._call("GET", f"/tasks/{remote_id}")
        if expected_version is not None and _version(current) != expected_version:
            raise RemoteConflict(f"task {remote_id} changed remotely")
        current.update(changes)
        await self._call("POST", f"/tasks/{remote_id}", json=current)
        # Read the task back. The update answer is the task as it is in memory (for example a
        # sub-second ``updated`` stamp), a read gives what is stored. The version must come
        # from the same form as the next conflict check, or the next write to this task would
        # look like a change in Vikunja.
        return self._task(await self._call("GET", f"/tasks/{remote_id}"))

    async def update_task(
        self, remote_id: str, patch: TaskPatch, expected_version: str
    ) -> RemoteTask:
        """Update a task; raise ``RemoteConflict`` if it changed since ``expected_version``."""
        changes: dict[str, Any] = {}
        if patch.title is not None:
            changes["title"] = patch.title
        if patch.description is not None:
            changes["description"] = patch.description
        if patch.due_at is not None:
            changes["due_date"] = _fmt(patch.due_at)
        return await self._update(remote_id, expected_version, changes)

    async def delete_task(self, remote_id: str) -> None:
        """Delete a task."""
        await self._call("DELETE", f"/tasks/{remote_id}")

    async def complete_task(self, remote_id: str) -> RemoteTask:
        """Mark a task done."""
        return await self._update(remote_id, None, {"done": True})

    async def reopen_task(self, remote_id: str) -> RemoteTask:
        """Mark a done task open again."""
        return await self._update(remote_id, None, {"done": False})

    async def set_planned_time(
        self,
        remote_id: str,
        due_at: datetime | None,
        all_day: bool,
        expected_version: str,
    ) -> RemoteTask:
        """Write or clear the task's due date. Start and end dates are never written."""
        if due_at is not None and all_day:
            local = due_at.astimezone(self._tz)
            due_at = datetime.combine(local.date(), time.min, tzinfo=self._tz)
        task = await self._update(remote_id, expected_version, {"due_date": _fmt(due_at)})
        # The task was read back. If Vikunja kept another date, tell the user now: a
        # change that the next sync takes back is worse than a message.
        if task.due_at != due_at:
            logger.warning(
                "Vikunja kept due_date %s for task %s after a write of %s",
                task.due_at,
                remote_id,
                due_at,
            )
            raise NotSaved(
                f"wrote the due date {due_at}, but Vikunja has {task.due_at} for task {remote_id}"
            )
        return task
