"""Stateful fake of the Vikunja REST API (``/api/v1``), as used by ``VikunjaTaskBackend``.

Modelled after Vikunja's behaviour:

- API-token auth (``Authorization: Bearer <token>``); a bad token answers 401.
- Timestamps are RFC 3339 with second resolution; an unset date is ``0001-01-01T00:00:00Z``.
- ``PUT /projects/{id}/tasks`` creates (201), ``POST /tasks/{id}`` updates by *replacing* all
  writable fields with the body (a missing field is reset to its zero value), ``DELETE``
  answers 200 with a message. There is no optimistic locking: ``updated`` is just a stamp.
- Validation errors answer 412 ("Invalid Data"), missing items 404 with a Vikunja error code.
"""

import json
from datetime import UTC, datetime
from typing import Any
from zoneinfo import ZoneInfo

import httpx

from tests.fakes.http.base import FakeHttpServer, json_response

ZERO_DATE = "0001-01-01T00:00:00Z"
_DATE_FIELDS = ("due_date", "start_date", "end_date")


def _render(value: datetime | None, tz: ZoneInfo | None = None) -> str:
    """Render a time as Vikunja does: in the time zone of the server, whole seconds."""
    if value is None:
        return ZERO_DATE
    if tz is None or tz == ZoneInfo("UTC"):
        return value.astimezone(UTC).replace(microsecond=0).strftime("%Y-%m-%dT%H:%M:%SZ")
    return value.astimezone(tz).replace(microsecond=0).isoformat()


def _parse(value: object) -> datetime | None:
    if not isinstance(value, str) or not value or value == ZERO_DATE:
        return None
    return datetime.fromisoformat(value)


class FakeVikunja(FakeHttpServer):
    """In-memory Vikunja server with projects and tasks."""

    def __init__(
        self,
        base_url: str = "https://vikunja.test",
        token: str = "vikunja-token",
        timezone: str = "UTC",
    ) -> None:
        """Start with one project ("Inbox") and no tasks.

        ``timezone`` is the time zone of the server. With ``Europe/Athens`` every time is sent
        with an offset (``2026-11-04T11:00:00+02:00``), as a real server in that zone does.
        """
        super().__init__((base_url,))
        self.tz = ZoneInfo(timezone)
        self.base_url = base_url
        self.token = token
        self.projects: dict[int, dict[str, Any]] = {}
        self.tasks: dict[int, dict[str, Any]] = {}
        self._next_id = 1
        self.add_project("Inbox")
        api = base_url + "/api/v1"
        self.route("GET", f"{api}/projects", self._list_projects)
        self.route("GET", f"{api}/projects/{{project_id}}/tasks", self._list_tasks)
        self.route("PUT", f"{api}/projects/{{project_id}}/tasks", self._create_task)
        self.route("GET", f"{api}/tasks/{{task_id}}", self._get_task)
        self.route("POST", f"{api}/tasks/{{task_id}}", self._update_task)
        self.route("DELETE", f"{api}/tasks/{{task_id}}", self._delete_task)

    def add_project(self, title: str) -> int:
        """Create a project directly in the app and return its id."""
        project_id = len(self.projects) + 1
        stamp = _render(self.now)
        self.projects[project_id] = {
            "id": project_id,
            "title": title,
            "description": "",
            "parent_project_id": 0,
            "is_archived": False,
            "created": stamp,
            "updated": stamp,
        }
        return project_id

    def add_label(self, task_id: int, title: str) -> None:
        """Give a task a label directly in the app."""
        labels = self.tasks[task_id].setdefault("labels", [])
        labels.append({"id": len(labels) + 1, "title": title, "hex_color": "ffcc00"})

    def authorised(self, request: httpx.Request) -> bool:
        """Accept only the configured API token."""
        return str(request.headers.get("authorization", "")) == f"Bearer {self.token}"

    def unauthorised(self) -> httpx.Response:
        """Vikunja's answer to a missing or invalid token."""
        return json_response(
            401, {"message": "missing, malformed, expired or otherwise invalid token provided"}
        )

    def not_found(self) -> httpx.Response:
        """Echo's default 404 for unknown routes."""
        return json_response(404, {"message": "Not Found"})

    def _error(self, status: int, code: int, message: str) -> httpx.Response:
        return json_response(status, {"code": code, "message": message})

    def _invalid(self, field: str) -> httpx.Response:
        return json_response(
            412, {"code": 2002, "message": "Invalid Data", "invalid_fields": [field]}
        )

    def _task_json(self, task: dict[str, Any]) -> dict[str, Any]:
        out = dict(task)
        for name in (*_DATE_FIELDS, "done_at", "created", "updated"):
            out[name] = _render(task[name], self.tz)
        out["identifier"] = f"#{task['index']}"
        return out

    def _list_projects(self, request: httpx.Request) -> httpx.Response:  # noqa: ARG002
        return json_response(200, list(self.projects.values()))

    def _list_tasks(self, request: httpx.Request, project_id: str) -> httpx.Response:
        if int(project_id) not in self.projects:
            return self._error(404, 3001, "The project does not exist.")
        page = int(request.url.params.get("page", "1"))
        per_page = int(request.url.params.get("per_page", "50"))
        tasks = sorted(
            (t for t in self.tasks.values() if t["project_id"] == int(project_id)),
            key=lambda t: t["id"],
        )
        chunk = tasks[(page - 1) * per_page : page * per_page]
        pages = max(1, -(-len(tasks) // per_page))
        return json_response(
            200,
            [self._task_json(t) for t in chunk],
            headers={
                "x-pagination-total-pages": str(pages),
                "x-pagination-result-count": str(len(chunk)),
            },
        )

    def _create_task(self, request: httpx.Request, project_id: str) -> httpx.Response:
        if int(project_id) not in self.projects:
            return self._error(404, 3001, "The project does not exist.")
        body = json.loads(request.content)
        if not str(body.get("title", "")).strip():
            return self._invalid("title")
        task_id = self._next_id
        self._next_id += 1
        index = 1 + sum(1 for t in self.tasks.values() if t["project_id"] == int(project_id))
        task: dict[str, Any] = {
            "id": task_id,
            "project_id": int(project_id),
            "index": index,
            "created": self.now,
            "updated": self.now,
            "labels": [],
        }
        self._write(task, body)
        self.tasks[task_id] = task
        return json_response(201, self._task_json(task))

    def _write(self, task: dict[str, Any], body: dict[str, Any]) -> None:
        # Vikunja binds the whole body onto the task: absent fields become zero values.
        was_done = bool(task.get("done"))
        task["title"] = str(body.get("title", ""))
        task["description"] = str(body.get("description", "") or "")
        task["done"] = bool(body.get("done", False))
        task["priority"] = int(body.get("priority", 0) or 0)
        task["repeat_after"] = int(body.get("repeat_after", 0) or 0)
        task["percent_done"] = float(body.get("percent_done", 0) or 0)
        for name in _DATE_FIELDS:
            task[name] = _parse(body.get(name))
        if task["done"] and not was_done:
            task["done_at"] = self.now
        elif not task["done"]:
            task["done_at"] = None
        task["updated"] = self.now

    def _get_task(self, request: httpx.Request, task_id: str) -> httpx.Response:  # noqa: ARG002
        task = self.tasks.get(int(task_id))
        if task is None:
            return self._error(404, 4002, "The task does not exist.")
        return json_response(200, self._task_json(task))

    def _update_task(self, request: httpx.Request, task_id: str) -> httpx.Response:
        task = self.tasks.get(int(task_id))
        if task is None:
            return self._error(404, 4002, "The task does not exist.")
        body = json.loads(request.content)
        if not str(body.get("title", "")).strip():
            return self._invalid("title")
        moved_to = int(body.get("project_id", 0) or 0)
        if moved_to and moved_to not in self.projects:
            return self._error(404, 3001, "The project does not exist.")
        self._write(task, body)
        if moved_to:
            task["project_id"] = moved_to
        return json_response(200, self._task_json(task))

    def _delete_task(self, request: httpx.Request, task_id: str) -> httpx.Response:  # noqa: ARG002
        if self.tasks.pop(int(task_id), None) is None:
            return self._error(404, 4002, "The task does not exist.")
        return json_response(200, {"message": "Successfully deleted."})
