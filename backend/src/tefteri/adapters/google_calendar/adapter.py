"""Google Calendar adapter (one instance per Google account; OAuth2 refresh-token flow)."""

from datetime import datetime
from typing import Any

import httpx

from tefteri.adapters.http import request
from tefteri.domain.entities import (
    ConnectionHealth,
    Container,
    EntryDraft,
    EntryPage,
    EntryPatch,
    RemoteEntry,
)
from tefteri.domain.enums import Capability, ConnectionStatus
from tefteri.domain.errors import AuthExpired, BackendError, BackendUnavailable

API = "https://www.googleapis.com/calendar/v3"
TOKEN_URL = "https://oauth2.googleapis.com/token"  # noqa: S105
SEP = "::"


def join_id(calendar_id: str, event_id: str) -> str:
    """Build the remote id of an event: it must also identify the calendar."""
    return f"{calendar_id}{SEP}{event_id}"


def split_id(remote_id: str) -> tuple[str, str]:
    """Split a remote id into ``(calendar_id, event_id)``."""
    calendar_id, _, event_id = remote_id.rpartition(SEP)
    return calendar_id, event_id


class GoogleCalendarBackend:
    """``CalendarBackend`` for one Google account. Its calendars are the containers."""

    def __init__(
        self,
        client: httpx.AsyncClient,
        client_id: str,
        client_secret: str,
        refresh_token: str,
    ) -> None:
        """Use ``client`` and the app/account credentials; access tokens are refreshed lazily."""
        self._client = client
        self._client_id = client_id
        self._client_secret = client_secret
        self._refresh_token = refresh_token
        self._access_token: str | None = None

    def capabilities(self) -> set[Capability]:
        """Google Calendar supports recurring events."""
        return {Capability.RECURRING}

    async def _refresh(self) -> str:
        try:
            response = await request(
                self._client,
                "POST",
                TOKEN_URL,
                ok_conflict_statuses=(),
                data={
                    "grant_type": "refresh_token",
                    "refresh_token": self._refresh_token,
                    "client_id": self._client_id,
                    "client_secret": self._client_secret,
                },
            )
        except (BackendUnavailable, AuthExpired):
            raise
        except BackendError as exc:
            # Google answers 400 ``invalid_grant`` for an expired or revoked refresh token
            # (and 400/401 for a bad client): the account must be reconnected.
            raise AuthExpired("Google rejected the stored credentials") from exc
        self._access_token = str(response.json()["access_token"])
        return self._access_token

    async def _call(self, method: str, path: str, **kwargs: Any) -> Any:
        token = self._access_token or await self._refresh()
        headers = {"Authorization": f"Bearer {token}", **kwargs.pop("headers", {})}
        try:
            response = await request(self._client, method, API + path, headers=headers, **kwargs)
        except AuthExpired:
            headers["Authorization"] = f"Bearer {await self._refresh()}"
            response = await request(self._client, method, API + path, headers=headers, **kwargs)
        return response.json() if response.content else None

    @staticmethod
    def _entry(calendar_id: str, data: dict[str, Any]) -> RemoteEntry:
        start, end = data["start"], data["end"]
        all_day = "date" in start
        parse = datetime.fromisoformat
        return RemoteEntry(
            remote_id=join_id(calendar_id, data["id"]),
            container_id=calendar_id,
            title=data.get("summary", ""),
            start=parse(start["date"] if all_day else start["dateTime"]),
            end=parse(end["date"] if all_day else end["dateTime"]),
            all_day=all_day,
            recurrence=";".join(data["recurrence"]) if data.get("recurrence") else None,
            location=data.get("location", ""),
            version=data.get("etag", ""),
        )

    async def list_containers(self) -> list[Container]:
        """List the account's calendars (personal, shared, company)."""
        data = await self._call("GET", "/users/me/calendarList")
        return [Container(c["id"], c.get("summaryOverride") or c["summary"]) for c in data["items"]]

    async def check_connection(self) -> ConnectionHealth:
        """Check the credentials by listing calendars."""
        try:
            await self._call("GET", "/users/me/calendarList")
        except AuthExpired:
            return ConnectionHealth(ConnectionStatus.NEEDS_ATTENTION, "auth_expired")
        except BackendUnavailable:
            return ConnectionHealth(ConnectionStatus.ERROR, "unreachable")
        return ConnectionHealth(ConnectionStatus.OK)

    async def list_entries(
        self,
        container: Container,
        start: datetime,
        end: datetime,
        sync_token: str | None,  # noqa: ARG002
    ) -> EntryPage:
        """List single (expanded) events in the window, following pagination."""
        entries: list[RemoteEntry] = []
        params: dict[str, Any] = {
            "timeMin": start.isoformat(),
            "timeMax": end.isoformat(),
            "singleEvents": "true",
            "maxResults": 250,
        }
        while True:
            data = await self._call(
                "GET", f"/calendars/{container.remote_id}/events", params=params
            )
            entries.extend(
                self._entry(container.remote_id, e)
                for e in data.get("items", [])
                if e.get("status") != "cancelled"
            )
            if not data.get("nextPageToken"):
                return EntryPage(items=entries, sync_token=data.get("nextSyncToken"))
            params["pageToken"] = data["nextPageToken"]

    async def get_entry(self, remote_id: str) -> RemoteEntry:
        """Fetch one event."""
        calendar_id, event_id = split_id(remote_id)
        data = await self._call("GET", f"/calendars/{calendar_id}/events/{event_id}")
        return self._entry(calendar_id, data)

    async def create_entry(self, draft: EntryDraft) -> RemoteEntry:
        """Create an event."""
        if draft.all_day:
            when: dict[str, Any] = {
                "start": {"date": draft.start.date().isoformat()},
                "end": {"date": draft.end.date().isoformat()},
            }
        else:
            when = {
                "start": {"dateTime": draft.start.isoformat()},
                "end": {"dateTime": draft.end.isoformat()},
            }
        body = {"summary": draft.title, "location": draft.location, **when}
        data = await self._call("POST", f"/calendars/{draft.container_id}/events", json=body)
        return self._entry(draft.container_id, data)

    async def update_entry(
        self, remote_id: str, patch: EntryPatch, expected_version: str
    ) -> RemoteEntry:
        """Patch an event with ``If-Match``; a 412 answer raises ``RemoteConflict``."""
        calendar_id, event_id = split_id(remote_id)
        body: dict[str, Any] = {}
        if patch.title is not None:
            body["summary"] = patch.title
        if patch.location is not None:
            body["location"] = patch.location
        if patch.start is not None:
            body["start"] = {"dateTime": patch.start.isoformat()}
        if patch.end is not None:
            body["end"] = {"dateTime": patch.end.isoformat()}
        data = await self._call(
            "PATCH",
            f"/calendars/{calendar_id}/events/{event_id}",
            json=body,
            headers={"If-Match": expected_version},
        )
        return self._entry(calendar_id, data)

    async def delete_entry(self, remote_id: str) -> None:
        """Delete an event."""
        calendar_id, event_id = split_id(remote_id)
        await self._call("DELETE", f"/calendars/{calendar_id}/events/{event_id}")
