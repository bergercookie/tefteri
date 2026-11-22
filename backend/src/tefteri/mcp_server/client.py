"""Calls the REST API of the app from inside the app, as the user of an API key."""

import re
from collections.abc import Callable, Mapping
from datetime import UTC, date, datetime, time, timedelta
from typing import Any
from zoneinfo import ZoneInfo

import httpx
from mcp.server.fastmcp.exceptions import ToolError

API_PREFIX = "/api/v1"

_UTC_TEXT = re.compile(r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?(Z|\+00:00)$")


def _detail(response: httpx.Response) -> str:
    """The message of an error answer, in words that an assistant can act on."""
    try:
        body = response.json()
    except ValueError:
        return f"The request failed with status {response.status_code}."
    detail = body.get("detail") if isinstance(body, dict) else None
    if isinstance(detail, list):
        parts = []
        for item in detail:
            where = ".".join(str(p) for p in item.get("loc", [])[1:])
            parts.append(f"{where}: {item.get('msg')}" if where else str(item.get("msg")))
        return "Invalid input: " + "; ".join(parts)
    if isinstance(detail, str) and detail:
        return detail
    return f"The request failed with status {response.status_code}."


def localize[T](value: T, zone: ZoneInfo) -> T:
    """Turn every UTC time in ``value`` into the local time of the user, and drop the nulls.

    The API sends times as UTC (``2030-03-10T12:30:00Z``). An assistant reads local times with
    their offset (``2030-03-10T14:30:00+02:00``) much more reliably.
    """
    if isinstance(value, dict):
        return {k: localize(v, zone) for k, v in value.items() if v is not None}  # type: ignore[return-value]
    if isinstance(value, list):
        return [localize(v, zone) for v in value]  # type: ignore[return-value]
    if isinstance(value, str) and _UTC_TEXT.match(value):
        moment = datetime.fromisoformat(value.replace("Z", "+00:00"))
        return moment.astimezone(zone).replace(microsecond=0).isoformat()  # type: ignore[return-value]
    return value


def parse_day(text: str | None, zone: ZoneInfo, today: date) -> date:
    """A day as ``YYYY-MM-DD``; no text means today."""
    if text is None or not text.strip():
        return today
    try:
        return date.fromisoformat(text.strip()[:10])
    except ValueError as exc:
        raise ToolError(f"{text!r} is not a date. Use YYYY-MM-DD, for example 2030-03-10.") from exc


def parse_moment(text: str, zone: ZoneInfo) -> tuple[datetime, bool]:
    """Read a date or a time. Returns the UTC time and whether the text was a date only.

    A time without an offset is a time of the user (``2030-03-10T14:30`` is 14:30 where the user
    lives). A time with an offset or ``Z`` keeps it.
    """
    raw = text.strip()
    try:
        if len(raw) == 10:
            day = date.fromisoformat(raw)
            return datetime.combine(day, time(0), tzinfo=zone).astimezone(UTC), True
        moment = datetime.fromisoformat(raw.replace("Z", "+00:00"))
    except ValueError as exc:
        raise ToolError(
            f"{text!r} is not a date or time. Use YYYY-MM-DD or YYYY-MM-DDTHH:MM, for example "
            "2030-03-10T14:30."
        ) from exc
    if moment.tzinfo is None:
        moment = moment.replace(tzinfo=zone)
    return moment.astimezone(UTC), False


def iso(moment: datetime) -> str:
    """UTC text that the API reads."""
    return moment.astimezone(UTC).isoformat().replace("+00:00", "Z")


def day_window(day: date, days: int, zone: ZoneInfo) -> tuple[str, str]:
    """The UTC start and end of ``days`` local days from ``day``."""
    start = datetime.combine(day, time(0), tzinfo=zone)
    end = datetime.combine(day + timedelta(days=days), time(0), tzinfo=zone)
    return iso(start), iso(end)


class Api:
    """A caller of the app's own API, signed in with the API key of the request."""

    def __init__(self, app: Any, authorization: str) -> None:
        """Use ``authorization`` (the whole ``Authorization`` header) for every call."""
        self._http = httpx.AsyncClient(
            transport=httpx.ASGITransport(app=app),
            base_url="http://tefteri",
            headers={"Authorization": authorization},
            timeout=60,
        )
        self.zone = ZoneInfo("UTC")
        self.now = datetime.now(UTC)
        self.username = ""
        self._clock: Callable[[], datetime] = lambda: datetime.now(UTC)

    def use_clock(self, clock: Callable[[], datetime]) -> None:
        """Use the clock of the app (a test moves it)."""
        self._clock = clock

    async def open(self) -> "Api":
        """Learn who the user is and what time it is for them."""
        me = await self.get("/auth/me")
        self.zone = ZoneInfo(me.get("timezone") or "UTC")
        self.username = str(me.get("username", ""))
        self.now = self._clock().astimezone(self.zone)
        return self

    @property
    def today(self) -> date:
        """Today, for the user."""
        return self.now.date()

    async def close(self) -> None:
        """Release the client."""
        await self._http.aclose()

    async def request(
        self,
        method: str,
        path: str,
        *,
        params: Mapping[str, Any] | None = None,
        json: Any = None,
    ) -> Any:
        """Call the API; an error becomes a ``ToolError`` with the message of the API."""
        response = await self._http.request(method, API_PREFIX + path, params=params, json=json)
        if response.status_code >= 400:
            raise ToolError(_detail(response))
        if response.status_code == 204 or not response.content:
            return None
        return response.json()

    async def get(self, path: str, **params: Any) -> Any:
        """``GET``; parameters that are ``None`` are left out."""
        return await self.request(
            "GET", path, params={k: v for k, v in params.items() if v is not None}
        )

    async def post(self, path: str, json: Any = None) -> Any:
        """``POST``."""
        return await self.request("POST", path, json=json)

    async def put(self, path: str, json: Any = None) -> Any:
        """``PUT``."""
        return await self.request("PUT", path, json=json)

    async def patch(self, path: str, json: Any = None) -> Any:
        """``PATCH``."""
        return await self.request("PATCH", path, json=json)

    async def delete(self, path: str) -> Any:
        """``DELETE``."""
        return await self.request("DELETE", path)

    def local[T](self, value: T) -> T:
        """``localize`` for this user."""
        return localize(value, self.zone)
