"""Vikunja task adapter (REST API v1, API-token auth)."""

from datetime import UTC, datetime
from typing import Any

import httpx

from tefteri.adapters.http import request
from tefteri.domain.entities import (
    ConnectionHealth,
    Container,
    RemoteTask,
    TaskDraft,
    TaskPage,
    TaskPatch,
)
from tefteri.domain.enums import Capability, ConnectionStatus
from tefteri.domain.errors import AuthExpired, BackendUnavailable, RemoteConflict

_ZERO_DATE = "0001-01-01T00:00:00Z"
_PAGE_SIZE = 50


def _parse(value: str | None) -> datetime | None:
    if not value or value == _ZERO_DATE:
        return None
    return datetime.fromisoformat(value.replace("Z", "+00:00"))


def _fmt(value: datetime | None) -> str:
    return value.astimezone(UTC).strftime("%Y-%m-%dT%H:%M:%SZ") if value else _ZERO_DATE


class VikunjaTaskBackend:
    """``TaskBackend`` for a Vikunja server. Projects are containers."""

    def __init__(self, client: httpx.AsyncClient, base_url: str, token: str) -> None:
        """Use ``client`` (injectable for tests) against ``base_url`` with an API ``token``."""
        self._client = client
        self._base = base_url.rstrip("/") + "/api/v1"
        self._headers = {"Authorization": f"Bearer {token}"}

    def capabilities(self) -> set[Capability]:
        """Vikunja stores task times (start/end) and recurrence."""
        return {Capability.TASK_TIME, Capability.RECURRING}

    async def _call(self, method: str, path: str, **kwargs: Any) -> Any:
        response = await request(
            self._client, method, self._base + path, headers=self._headers, **kwargs
        )
        return response.json()

    def _task(self, data: dict[str, Any]) -> RemoteTask:
        return RemoteTask(
            remote_id=str(data["id"]),
            container_id=str(data["project_id"]),
            title=data["title"],
            description=data.get("description", "") or "",
            done=bool(data.get("done")),
            due_at=_parse(data.get("due_date")),
            scheduled_start=_parse(data.get("start_date")),
            scheduled_end=_parse(data.get("end_date")),
            version=str(data.get("updated", "")),
        )

    async def list_containers(self) -> list[Container]:
        """List projects."""
        data = await self._call("GET", "/projects")
        return [Container(str(p["id"]), p["title"]) for p in data]

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

    async def create_task(self, draft: TaskDraft) -> RemoteTask:
        """Create a task in a project."""
        body: dict[str, Any] = {"title": draft.title, "description": draft.description}
        if draft.due_at:
            body["due_date"] = _fmt(draft.due_at)
        data = await self._call("PUT", f"/projects/{draft.container_id}/tasks", json=body)
        return self._task(data)

    async def _update(
        self, remote_id: str, expected_version: str | None, changes: dict[str, Any]
    ) -> RemoteTask:
        current = await self._call("GET", f"/tasks/{remote_id}")
        if expected_version is not None and str(current.get("updated", "")) != expected_version:
            raise RemoteConflict(f"task {remote_id} changed remotely")
        current.update(changes)
        return self._task(await self._call("POST", f"/tasks/{remote_id}", json=current))

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

    async def set_schedule(
        self,
        remote_id: str,
        start: datetime | None,
        end: datetime | None,
        expected_version: str,
    ) -> RemoteTask:
        """Write or clear the task's start and end date."""
        return await self._update(
            remote_id, expected_version, {"start_date": _fmt(start), "end_date": _fmt(end)}
        )
