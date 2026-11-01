"""Trilium Next note adapter (ETAPI, token auth)."""

from datetime import date
from typing import Any

import httpx

from tefteri.adapters.http import request
from tefteri.domain.entities import (
    ConnectionHealth,
    Container,
    NoteDraft,
    NotePatch,
    RemoteNote,
)
from tefteri.domain.enums import Capability, ConnectionStatus
from tefteri.domain.errors import AuthExpired, BackendUnavailable, RemoteConflict


class TriliumNoteBackend:
    """``NoteBackend`` for Trilium Next. A subtree below a note is a container."""

    def __init__(
        self, client: httpx.AsyncClient, base_url: str, token: str, root_note_id: str = "root"
    ) -> None:
        """Use ``client`` against ``base_url`` with an ETAPI ``token``."""
        self._client = client
        self._base = base_url.rstrip("/") + "/etapi"
        self._headers = {"Authorization": token}
        self._root = root_note_id

    def capabilities(self) -> set[Capability]:
        """Trilium supports appending to a note's content."""
        return {Capability.NOTE_APPEND}

    async def _call(self, method: str, path: str, **kwargs: Any) -> Any:
        headers = {**self._headers, **kwargs.pop("headers", {})}
        response = await request(self._client, method, self._base + path, headers=headers, **kwargs)
        if response.headers.get("content-type", "").startswith("application/json"):
            return response.json()
        return response.text

    async def _note(self, meta: dict[str, Any], day: date | None = None) -> RemoteNote:
        body = await self._call("GET", f"/notes/{meta['noteId']}/content")
        return RemoteNote(
            remote_id=meta["noteId"],
            title=meta["title"],
            body=body,
            version=meta.get("utcDateModified", ""),
            note_date=day,
        )

    async def list_containers(self) -> list[Container]:
        """List the children of the configured root note."""
        root = await self._call("GET", f"/notes/{self._root}")
        containers = [Container(self._root, root["title"])]
        for child_id in root.get("childNoteIds", []):
            child = await self._call("GET", f"/notes/{child_id}")
            containers.append(Container(child["noteId"], child["title"]))
        return containers

    async def check_connection(self) -> ConnectionHealth:
        """Check the token by reading the app info."""
        try:
            await self._call("GET", "/app-info")
        except AuthExpired:
            return ConnectionHealth(ConnectionStatus.NEEDS_ATTENTION, "auth_expired")
        except BackendUnavailable:
            return ConnectionHealth(ConnectionStatus.ERROR, "unreachable")
        return ConnectionHealth(ConnectionStatus.OK)

    async def list_notes(self, container: Container, since: str | None) -> list[RemoteNote]:  # noqa: ARG002
        """List the notes below a container note."""
        found = await self._call(
            "GET",
            "/notes",
            params={"search": "note.noteId != ''", "ancestorNoteId": container.remote_id},
        )
        return [await self._note(meta) for meta in found.get("results", [])]

    async def get_note(self, remote_id: str) -> RemoteNote:
        """Fetch one note with its content."""
        return await self._note(await self._call("GET", f"/notes/{remote_id}"))

    async def create_note(self, draft: NoteDraft) -> RemoteNote:
        """Create a text note below the root note."""
        created = await self._call(
            "POST",
            "/create-note",
            json={
                "parentNoteId": self._root,
                "title": draft.title,
                "type": "text",
                "content": draft.body,
            },
        )
        return await self._note(created["note"], draft.note_date)

    async def _check(self, remote_id: str, expected_version: str) -> None:
        meta = await self._call("GET", f"/notes/{remote_id}")
        if meta.get("utcDateModified", "") != expected_version:
            raise RemoteConflict(f"note {remote_id} changed remotely")

    async def update_note(
        self, remote_id: str, patch: NotePatch, expected_version: str
    ) -> RemoteNote:
        """Update title and/or content; raise ``RemoteConflict`` on a stale version."""
        await self._check(remote_id, expected_version)
        if patch.title is not None:
            await self._call("PATCH", f"/notes/{remote_id}", json={"title": patch.title})
        if patch.body is not None:
            await self._call(
                "PUT",
                f"/notes/{remote_id}/content",
                content=patch.body,
                headers={**self._headers, "Content-Type": "text/plain"},
            )
        return await self.get_note(remote_id)

    async def delete_note(self, remote_id: str) -> None:
        """Delete a note."""
        await self._call("DELETE", f"/notes/{remote_id}")

    async def get_or_create_daily(self, day: date) -> RemoteNote:
        """Return the daily (calendar) note for ``day``; Trilium creates it when missing."""
        meta = await self._call("GET", f"/calendar/days/{day.isoformat()}")
        return await self._note(meta, day)

    async def append(self, remote_id: str, text: str) -> RemoteNote:
        """Append ``text`` as a new paragraph at the end of the note."""
        current = await self.get_note(remote_id)
        body = f"{current.body}<p>{text}</p>"
        await self._call(
            "PUT",
            f"/notes/{remote_id}/content",
            content=body,
            headers={**self._headers, "Content-Type": "text/plain"},
        )
        return await self.get_note(remote_id)
