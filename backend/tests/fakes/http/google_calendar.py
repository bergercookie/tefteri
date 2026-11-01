"""Stateful fake of Google Calendar API v3 plus Google's OAuth2 token endpoint.

Modelled after Google's behaviour, for one account:

- ``POST https://oauth2.googleapis.com/token`` trades the refresh token for a bearer access
  token. A wrong client answers 401 ``invalid_client``; a wrong or revoked refresh token
  answers **400** ``invalid_grant`` (Google never answers 401 for a revoked grant).
- API calls need a currently valid access token, otherwise 401 ``UNAUTHENTICATED``.
- Every event write produces a new quoted ``etag``; ``If-Match`` with another etag answers 412.
- ``PATCH`` updates only the fields sent; ``DELETE`` answers 204 and leaves a ``cancelled``
  tombstone, which ``events.list`` hides unless ``showDeleted=true`` and a second delete
  answers 410.
- ``events.list`` returns events overlapping ``[timeMin, timeMax)``, paginated with
  ``pageToken``/``nextPageToken``; ``nextSyncToken`` is only on the last page.
"""

import itertools
import json
from datetime import UTC, date, datetime, time
from typing import Any
from urllib.parse import parse_qs

import httpx

from tests.fakes.http.base import FakeHttpServer, json_response

API = "https://www.googleapis.com/calendar/v3"
TOKEN_URL = "https://oauth2.googleapis.com/token"  # noqa: S105


def _error(status: int, reason: str, message: str, google_status: str) -> httpx.Response:
    return json_response(
        status,
        {
            "error": {
                "code": status,
                "message": message,
                "errors": [{"domain": "global", "reason": reason, "message": message}],
                "status": google_status,
            }
        },
    )


def _instant(when: dict[str, Any]) -> datetime:
    """Return the instant an event ``start``/``end`` object stands for (calendar zone is UTC)."""
    if "dateTime" in when:
        return datetime.fromisoformat(when["dateTime"])
    return datetime.combine(date.fromisoformat(when["date"]), time(), UTC)


def _normalise(when: object) -> dict[str, Any] | None:
    """Validate a ``start``/``end`` object and render times in the calendar zone (UTC)."""
    if not isinstance(when, dict):
        return None
    if when.get("dateTime"):
        moment = datetime.fromisoformat(str(when["dateTime"]))
        if moment.tzinfo is None and "timeZone" not in when:
            return None  # Google needs an offset or an explicit time zone.
        utc = moment.astimezone(UTC).strftime("%Y-%m-%dT%H:%M:%SZ")
        return {"dateTime": utc, **({"timeZone": when["timeZone"]} if "timeZone" in when else {})}
    if when.get("date"):
        return {"date": date.fromisoformat(str(when["date"])).isoformat()}
    return None


class FakeGoogleCalendar(FakeHttpServer):
    """In-memory Google account with calendars and events."""

    def __init__(
        self,
        client_id: str = "client-id",
        client_secret: str = "client-secret",  # noqa: S107
        refresh_token: str = "refresh-token",  # noqa: S107
        account: str = "sam@example.com",
    ) -> None:
        """Start with the account's primary calendar and a shared family calendar."""
        super().__init__(("https://oauth2.googleapis.com", "https://www.googleapis.com"))
        self.client_id = client_id
        self.client_secret = client_secret
        self.refresh_token = refresh_token
        self.access_tokens: set[str] = set()
        self.calendars: dict[str, dict[str, Any]] = {}
        self.events: dict[str, dict[str, dict[str, Any]]] = {}
        self._serial = itertools.count(1)
        self.add_calendar(account, account, primary=True)
        self.add_calendar("family@group.calendar.google.com", "Family")
        self.route("POST", TOKEN_URL, self._token, public=True)
        self.route("GET", f"{API}/users/me/calendarList", self._calendar_list)
        self.route("GET", f"{API}/calendars/{{cal}}/events", self._list_events)
        self.route("POST", f"{API}/calendars/{{cal}}/events", self._insert_event)
        self.route("GET", f"{API}/calendars/{{cal}}/events/{{event_id}}", self._get_event)
        self.route("PATCH", f"{API}/calendars/{{cal}}/events/{{event_id}}", self._patch_event)
        self.route("DELETE", f"{API}/calendars/{{cal}}/events/{{event_id}}", self._delete_event)

    def add_calendar(self, calendar_id: str, summary: str, *, primary: bool = False) -> None:
        """Add a calendar to the account's calendar list."""
        self.calendars[calendar_id] = {
            "kind": "calendar#calendarListEntry",
            "etag": self._etag(),
            "id": calendar_id,
            "summary": summary,
            "timeZone": "UTC",
            "accessRole": "owner",
            **({"primary": True} if primary else {}),
        }
        self.events[calendar_id] = {}

    def authorised(self, request: httpx.Request) -> bool:
        """Accept access tokens issued by the token endpoint."""
        scheme, _, token = request.headers.get("authorization", "").partition(" ")
        return scheme == "Bearer" and token in self.access_tokens

    def unauthorised(self) -> httpx.Response:
        """Google's answer to a missing, expired or revoked access token."""
        return _error(
            401, "authError", "Request had invalid authentication credentials.", "UNAUTHENTICATED"
        )

    def not_found(self) -> httpx.Response:
        """Google's answer for an unknown calendar, event or endpoint."""
        return _error(404, "notFound", "Not Found", "NOT_FOUND")

    def _etag(self) -> str:
        return f'"{3_181_000_000_000_000 + next(self._serial)}"'

    def _stamp(self) -> str:
        return self.now.strftime("%Y-%m-%dT%H:%M:%S.") + f"{self.now.microsecond // 1000:03d}Z"

    def _token(self, request: httpx.Request) -> httpx.Response:
        form = {k: v[0] for k, v in parse_qs(request.content.decode()).items()}
        if form.get("client_id") != self.client_id or form.get("client_secret") != (
            self.client_secret
        ):
            return json_response(
                401, {"error": "invalid_client", "error_description": "Unauthorized"}
            )
        if form.get("grant_type") != "refresh_token":
            return json_response(400, {"error": "unsupported_grant_type"})
        if self.auth_expired or form.get("refresh_token") != self.refresh_token:
            return json_response(
                400,
                {
                    "error": "invalid_grant",
                    "error_description": "Token has been expired or revoked.",
                },
            )
        token = f"ya29.access-{next(self._serial)}"
        self.access_tokens.add(token)
        return json_response(
            200,
            {
                "access_token": token,
                "expires_in": 3599,
                "scope": "https://www.googleapis.com/auth/calendar",
                "token_type": "Bearer",
            },
        )

    def _calendar_list(self, request: httpx.Request) -> httpx.Response:  # noqa: ARG002
        return json_response(
            200,
            {
                "kind": "calendar#calendarList",
                "etag": self._etag(),
                "items": list(self.calendars.values()),
            },
        )

    def _list_events(self, request: httpx.Request, cal: str) -> httpx.Response:
        if cal not in self.events:
            return self.not_found()
        params = request.url.params
        time_min = datetime.fromisoformat(params["timeMin"]) if "timeMin" in params else None
        time_max = datetime.fromisoformat(params["timeMax"]) if "timeMax" in params else None
        if time_min and time_max and time_max <= time_min:
            return _error(400, "timeRangeEmpty", "The specified time range is empty.", "INVALID")
        show_deleted = params.get("showDeleted") == "true"
        matching = [
            e
            for e in self.events[cal].values()
            if (show_deleted or e["status"] != "cancelled")
            and (time_max is None or _instant(e["start"]) < time_max)
            and (time_min is None or _instant(e["end"]) > time_min)
        ]
        size = min(int(params.get("maxResults", "250")), 2500)
        offset = int(params.get("pageToken", "0"))
        body: dict[str, Any] = {
            "kind": "calendar#events",
            "etag": self._etag(),
            "summary": self.calendars[cal]["summary"],
            "timeZone": "UTC",
            "items": matching[offset : offset + size],
        }
        if offset + size < len(matching):
            body["nextPageToken"] = str(offset + size)
        else:
            body["nextSyncToken"] = f"sync-{next(self._serial)}"
        return json_response(200, body)

    def _apply(self, event: dict[str, Any], body: dict[str, Any]) -> httpx.Response | None:
        """Copy writable fields from ``body``; return an error answer when invalid."""
        for name in ("summary", "location", "description"):
            if name in body:
                if body[name]:
                    event[name] = str(body[name])
                else:
                    event.pop(name, None)  # Google omits empty fields from resources.
        for name in ("start", "end"):
            if name in body:
                when = _normalise(body[name])
                if when is None:
                    return _error(400, "required", f"Missing {name} time.", "INVALID_ARGUMENT")
                event[name] = when  # a time sent in a patch replaces the whole object
        if "recurrence" in body:
            event["recurrence"] = list(body["recurrence"])
        if "start" not in event or "end" not in event:
            return _error(400, "required", "Missing time.", "INVALID_ARGUMENT")
        if _instant(event["end"]) < _instant(event["start"]):
            return _error(400, "timeRangeEmpty", "The specified time range is empty.", "INVALID")
        event["etag"] = self._etag()
        event["updated"] = self._stamp()
        event["sequence"] = event.get("sequence", -1) + 1
        return None

    def _insert_event(self, request: httpx.Request, cal: str) -> httpx.Response:
        if cal not in self.events:
            return self.not_found()
        event_id = f"{next(self._serial):08d}evt"
        event: dict[str, Any] = {
            "kind": "calendar#event",
            "id": event_id,
            "status": "confirmed",
            "htmlLink": f"https://www.google.com/calendar/event?eid={event_id}",
            "created": self._stamp(),
            "creator": {"email": cal},
            "organizer": {"email": cal, "self": True},
            "iCalUID": f"{event_id}@google.com",
            "reminders": {"useDefault": True},
            "eventType": "default",
        }
        error = self._apply(event, json.loads(request.content))
        if error is not None:
            return error
        self.events[cal][event_id] = event
        return json_response(200, event)

    def _find(self, cal: str, event_id: str) -> dict[str, Any] | None:
        return self.events.get(cal, {}).get(event_id)

    def _get_event(self, request: httpx.Request, cal: str, event_id: str) -> httpx.Response:  # noqa: ARG002
        event = self._find(cal, event_id)
        return self.not_found() if event is None else json_response(200, event)

    def _patch_event(self, request: httpx.Request, cal: str, event_id: str) -> httpx.Response:
        event = self._find(cal, event_id)
        if event is None:
            return self.not_found()
        if_match = request.headers.get("if-match")
        if if_match is not None and if_match != event["etag"]:
            return _error(412, "conditionNotMet", "Precondition Failed", "FAILED_PRECONDITION")
        candidate = json.loads(json.dumps(event))
        error = self._apply(candidate, json.loads(request.content))
        if error is not None:
            return error
        self.events[cal][event_id] = candidate
        return json_response(200, candidate)

    def _delete_event(self, request: httpx.Request, cal: str, event_id: str) -> httpx.Response:
        event = self._find(cal, event_id)
        if event is None:
            return self.not_found()
        if event["status"] == "cancelled":
            return _error(410, "deleted", "Resource has been deleted", "GONE")
        if_match = request.headers.get("if-match")
        if if_match is not None and if_match != event["etag"]:
            return _error(412, "conditionNotMet", "Precondition Failed", "FAILED_PRECONDITION")
        event["status"] = "cancelled"
        event["etag"] = self._etag()
        event["updated"] = self._stamp()
        return httpx.Response(204)
