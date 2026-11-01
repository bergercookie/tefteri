"""Stateful fake of Trilium Next's ETAPI (``/etapi``), as used by ``TriliumNoteBackend``.

Modelled after Trilium's behaviour:

- ETAPI token auth: the raw token in ``Authorization``; otherwise 401 ``NOT_AUTHENTICATED``.
- Notes form a tree (``parentNoteIds``/``childNoteIds``); ``utcDateModified`` has millisecond
  resolution and changes on every save of the note, including a content change.
- Content is separate: ``GET /notes/{id}/content`` answers the note's mime type (``text/html``
  for text notes) and ``PUT`` takes ``text/plain`` and answers 204.
- ``GET /calendar/days/{date}`` returns the day note, creating the calendar root, year and
  month notes on the way (titles follow Trilium's default patterns).
- ``DELETE`` answers 204 (also for an unknown note) and removes the subtree.
"""

import hashlib
import itertools
import json
from datetime import date
from typing import Any

import httpx

from tests.fakes.http.base import FakeHttpServer, json_response

_SEARCH_ALL = "note.noteId != ''"


def _error(status: int, code: str, message: str) -> httpx.Response:
    return json_response(status, {"status": status, "code": code, "message": message})


class FakeTrilium(FakeHttpServer):
    """In-memory Trilium Next instance."""

    def __init__(self, base_url: str = "https://trilium.test", token: str = "etapi-token") -> None:
        """Start with the root note only."""
        super().__init__((base_url,))
        self.base_url = base_url
        self.token = token
        self.notes: dict[str, dict[str, Any]] = {}
        self.content: dict[str, str] = {}
        self._ids = itertools.count(1)
        self._add("root", "root", None)
        etapi = base_url + "/etapi"
        self.route("GET", f"{etapi}/app-info", self._app_info)
        self.route("GET", f"{etapi}/notes", self._search)
        self.route("POST", f"{etapi}/create-note", self._create)
        self.route("GET", f"{etapi}/notes/{{note_id}}", self._get)
        self.route("PATCH", f"{etapi}/notes/{{note_id}}", self._patch)
        self.route("DELETE", f"{etapi}/notes/{{note_id}}", self._delete)
        self.route("GET", f"{etapi}/notes/{{note_id}}/content", self._get_content)
        self.route("PUT", f"{etapi}/notes/{{note_id}}/content", self._put_content)
        self.route("GET", f"{etapi}/calendar/days/{{day}}", self._day)

    def authorised(self, request: httpx.Request) -> bool:
        """Accept only the configured ETAPI token."""
        return str(request.headers.get("authorization", "")) == self.token

    def unauthorised(self) -> httpx.Response:
        """Trilium's answer to a missing or wrong token."""
        return _error(401, "NOT_AUTHENTICATED", "Not authenticated")

    def not_found(self) -> httpx.Response:
        """Trilium's answer for an unknown endpoint."""
        return _error(404, "ENDPOINT_NOT_FOUND", "Endpoint not found")

    def _note_missing(self, note_id: str) -> httpx.Response:
        return _error(404, "NOTE_NOT_FOUND", f"Note '{note_id}' not found.")

    def _stamps(self) -> tuple[str, str]:
        """Return ``(local, utc)`` modification stamps with millisecond resolution."""
        base = self.now.strftime("%Y-%m-%d %H:%M:%S.") + f"{self.now.microsecond // 1000:03d}"
        return f"{base}+0000", f"{base}Z"

    def _touch(self, note: dict[str, Any]) -> None:
        note["dateModified"], note["utcDateModified"] = self._stamps()

    def _add(
        self,
        note_id: str,
        title: str,
        parent_id: str | None,
        content: str = "",
        labels: dict[str, str] | None = None,
    ) -> dict[str, Any]:
        local, utc = self._stamps()
        note: dict[str, Any] = {
            "noteId": note_id,
            "isProtected": False,
            "title": title,
            "type": "text",
            "mime": "text/html",
            "blobId": "",
            "dateCreated": local,
            "dateModified": local,
            "utcDateCreated": utc,
            "utcDateModified": utc,
            "parentNoteIds": [parent_id] if parent_id else ["none"],
            "childNoteIds": [],
            "parentBranchIds": [f"{parent_id}_{note_id}"] if parent_id else ["none_root"],
            "childBranchIds": [],
            "attributes": [
                {
                    "attributeId": f"a{next(self._ids):011d}",
                    "noteId": note_id,
                    "type": "label",
                    "name": name,
                    "value": value,
                    "isInheritable": False,
                }
                for name, value in (labels or {}).items()
            ],
        }
        self.notes[note_id] = note
        self._set_content(note, content)
        if parent_id:
            parent = self.notes[parent_id]
            parent["childNoteIds"].append(note_id)
            parent["childBranchIds"].append(f"{parent_id}_{note_id}")
        return note

    def _new_id(self) -> str:
        return f"n{next(self._ids):011d}"

    def _set_content(self, note: dict[str, Any], content: str) -> None:
        self.content[note["noteId"]] = content
        blob_id = hashlib.sha1(content.encode(), usedforsecurity=False).hexdigest()[:20]
        if blob_id != note["blobId"]:
            # A new blob means the note entity itself is saved, which bumps its stamps.
            note["blobId"] = blob_id
            self._touch(note)

    def _with_label(self, name: str, value: str = "") -> dict[str, Any] | None:
        for note in self.notes.values():
            for attr in note["attributes"]:
                if attr["name"] == name and (not value or attr["value"] == value):
                    return note
        return None

    def _descendants(self, note_id: str) -> list[str]:
        found: list[str] = []
        for child in self.notes[note_id]["childNoteIds"]:
            found.extend([child, *self._descendants(child)])
        return found

    def _app_info(self, request: httpx.Request) -> httpx.Response:  # noqa: ARG002
        return json_response(
            200,
            {
                "appVersion": "0.90.0",
                "dbVersion": 228,
                "syncVersion": 34,
                "clipperProtocolVersion": "1.0",
            },
        )

    def _search(self, request: httpx.Request) -> httpx.Response:
        params = request.url.params
        if params.get("search") != _SEARCH_ALL:
            return _error(400, "SEARCH_QUERY_NOT_SUPPORTED_BY_FAKE", str(params.get("search")))
        ancestor = params.get("ancestorNoteId", "root")
        if ancestor not in self.notes:
            return self._note_missing(ancestor)
        ids = dict.fromkeys(self._descendants(ancestor))
        return json_response(200, {"results": [self.notes[i] for i in ids]})

    def _create(self, request: httpx.Request) -> httpx.Response:
        body = json.loads(request.content)
        parent_id = body.get("parentNoteId")
        if parent_id not in self.notes:
            return _error(400, "PROPERTY_VALIDATION_ERROR", f"Note '{parent_id}' does not exist.")
        if not isinstance(body.get("title"), str) or not isinstance(body.get("content"), str):
            return _error(400, "PROPERTY_VALIDATION_ERROR", "title and content are required.")
        if body.get("type") != "text":
            return _error(400, "PROPERTY_VALIDATION_ERROR", "the fake only models text notes.")
        note = self._add(self._new_id(), body["title"], parent_id, body["content"])
        branch_id = note["parentBranchIds"][0]
        branch = {"branchId": branch_id, "noteId": note["noteId"], "parentNoteId": parent_id}
        return json_response(201, {"note": note, "branch": branch})

    def _get(self, request: httpx.Request, note_id: str) -> httpx.Response:  # noqa: ARG002
        note = self.notes.get(note_id)
        return self._note_missing(note_id) if note is None else json_response(200, note)

    def _patch(self, request: httpx.Request, note_id: str) -> httpx.Response:
        note = self.notes.get(note_id)
        if note is None:
            return self._note_missing(note_id)
        body = json.loads(request.content)
        unknown = set(body) - {"title", "type", "mime", "dateCreated", "utcDateCreated"}
        if unknown:
            return _error(
                400, "PROPERTY_NOT_ALLOWED", f"Property '{sorted(unknown)[0]}' is not allowed."
            )
        note.update(body)
        self._touch(note)
        return json_response(200, note)

    def _delete(self, request: httpx.Request, note_id: str) -> httpx.Response:  # noqa: ARG002
        if note_id not in self.notes:
            return httpx.Response(204)
        for gone in [note_id, *self._descendants(note_id)]:
            note = self.notes.pop(gone, None)
            self.content.pop(gone, None)
            for parent_id in note["parentNoteIds"] if note else []:
                parent = self.notes.get(parent_id)
                if parent is not None and gone in parent["childNoteIds"]:
                    parent["childNoteIds"].remove(gone)
                    parent["childBranchIds"].remove(f"{parent_id}_{gone}")
        return httpx.Response(204)

    def _get_content(self, request: httpx.Request, note_id: str) -> httpx.Response:  # noqa: ARG002
        note = self.notes.get(note_id)
        if note is None:
            return self._note_missing(note_id)
        return httpx.Response(
            200,
            content=self.content[note_id].encode(),
            headers={"content-type": f"{note['mime']}; charset=utf-8"},
        )

    def _put_content(self, request: httpx.Request, note_id: str) -> httpx.Response:
        note = self.notes.get(note_id)
        if note is None:
            return self._note_missing(note_id)
        if not request.headers.get("content-type", "").startswith("text/plain"):
            return _error(400, "CONTENT_TYPE_NOT_SUPPORTED", "Content must be text/plain.")
        self._set_content(note, request.content.decode())
        return httpx.Response(204)

    def _day(self, request: httpx.Request, day: str) -> httpx.Response:  # noqa: ARG002
        try:
            when = date.fromisoformat(day)
        except ValueError:
            return _error(400, "DATE_INVALID", f"Date '{day}' is not valid.")
        existing = self._with_label("dateNote", when.isoformat())
        if existing is not None:
            return json_response(200, existing)
        root = self._with_label("calendarRoot") or self._add(
            self._new_id(), "Calendar", "root", labels={"calendarRoot": "", "sorted": ""}
        )
        year = self._with_label("yearNote", str(when.year)) or self._add(
            self._new_id(), str(when.year), root["noteId"], labels={"yearNote": str(when.year)}
        )
        month_key = when.strftime("%Y-%m")
        month = self._with_label("monthNote", month_key) or self._add(
            self._new_id(),
            when.strftime("%m - %B"),
            year["noteId"],
            labels={"monthNote": month_key},
        )
        note = self._add(
            self._new_id(),
            when.strftime("%d - %A"),
            month["noteId"],
            labels={"dateNote": when.isoformat()},
        )
        return json_response(200, note)
