"""Building blocks for stateful fake HTTP servers served through ``respx``."""

import json
import re
from collections.abc import Callable
from datetime import UTC, datetime, timedelta
from typing import Any
from urllib.parse import unquote

import httpx
import respx

Handler = Callable[..., httpx.Response]

# Every fake server starts at the same instant, so recorded timestamps are reproducible.
START = datetime(2026, 11, 2, 8, 0, tzinfo=UTC)
# Simulated time spent per handled request. Small enough that consecutive writes fall into
# the same second, which is what a fast client sees from apps with second-resolution stamps.
REQUEST_DURATION = timedelta(milliseconds=7)


def json_response(status: int, body: Any, headers: dict[str, str] | None = None) -> httpx.Response:
    """Build a JSON answer the way the real apps send it."""
    return httpx.Response(
        status,
        content=json.dumps(body).encode(),
        headers={"content-type": "application/json; charset=utf-8", **(headers or {})},
    )


class FakeHttpServer:
    """A fake app: in-memory state behind routes matched on ``METHOD url-template``.

    Subclasses register their endpoints with :meth:`route` and implement
    :meth:`authorised` and the error bodies. Two switches simulate outages:
    ``unavailable`` (connection refused) and ``auth_expired`` (credentials revoked).
    Requests to an endpoint that is not modelled get the app's 404, so an adapter
    calling an unexpected endpoint fails loudly instead of being served a guess.
    """

    def __init__(self, hosts: tuple[str, ...]) -> None:
        """Serve the given host names (``scheme://host``)."""
        self.hosts = hosts
        self.unavailable = False
        self.auth_expired = False
        self.requests: list[httpx.Request] = []
        self.now = START
        self._routes: list[tuple[str, re.Pattern[str], Handler, bool]] = []

    def route(self, method: str, template: str, handler: Handler, *, public: bool = False) -> None:
        """Serve ``method template``; ``{name}`` parts of the template become handler kwargs."""
        pattern = re.sub(r"\\\{(\w+)\\\}", r"(?P<\1>[^/]+)", re.escape(template))
        self._routes.append((method, re.compile(pattern), handler, public))

    def mount(self, router: respx.MockRouter) -> None:
        """Answer every request to this server's hosts from ``router``."""
        for host in self.hosts:
            router.route(url__startswith=host).mock(side_effect=self._dispatch)

    def authorised(self, request: httpx.Request) -> bool:
        """Return whether the request carries valid credentials."""
        raise NotImplementedError

    def unauthorised(self) -> httpx.Response:
        """Answer a request with missing or revoked credentials."""
        raise NotImplementedError

    def not_found(self) -> httpx.Response:
        """Answer a request for an unknown endpoint or item."""
        raise NotImplementedError

    def _dispatch(self, request: httpx.Request) -> httpx.Response:
        self.requests.append(request)
        if self.unavailable:
            raise httpx.ConnectError("connection refused", request=request)
        self.now += REQUEST_DURATION
        url = f"{request.url.scheme}://{request.url.host}{unquote(request.url.path)}"
        for method, pattern, handler, public in self._routes:
            match = pattern.fullmatch(url)
            if match is None or method != request.method:
                continue
            if not public and (self.auth_expired or not self.authorised(request)):
                return self.unauthorised()
            return handler(request, **match.groupdict())
        return self.not_found()
