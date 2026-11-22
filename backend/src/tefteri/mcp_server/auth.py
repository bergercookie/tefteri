"""Checks the API key of every call to ``/mcp`` before the MCP protocol sees it."""

import json
from collections.abc import Awaitable, Callable, MutableMapping
from typing import Any

from tefteri.auth.service import AuthService
from tefteri.db.session import session_scope
from tefteri.security.tokens import API_KEY_PREFIX

Scope = MutableMapping[str, Any]
Receive = Callable[[], Awaitable[MutableMapping[str, Any]]]
Send = Callable[[MutableMapping[str, Any]], Awaitable[None]]
Asgi = Callable[[Scope, Receive, Send], Awaitable[None]]


class RequireApiKey:
    """Lets a call through only with a valid API key. Anything else gets a clear 401."""

    def __init__(self, inner: Asgi, auth: AuthService, session_factory: Any) -> None:
        """Wrap ``inner``; keys are checked with ``auth`` on sessions from ``session_factory``."""
        self._inner = inner
        self._auth = auth
        self._factory = session_factory

    async def __call__(self, scope: Scope, receive: Receive, send: Send) -> None:
        """Check the ``Authorization`` header, then pass the call on."""
        if scope["type"] != "http":
            await self._inner(scope, receive, send)
            return
        headers = {k.decode().lower(): v.decode() for k, v in scope.get("headers", [])}
        scheme, _, token = headers.get("authorization", "").partition(" ")
        if scheme.lower() != "bearer" or not token.startswith(API_KEY_PREFIX):
            await self._refuse(
                send,
                "This is the MCP server of tefteri. Send an API key as 'Authorization: Bearer "
                "tft_...'. Make one in Settings, API keys.",
            )
            return
        async with session_scope(self._factory) as db:
            user = await self._auth.authenticate_api_key(db, token)
        if user is None:
            await self._refuse(send, "This API key is not valid. It may have been revoked.")
            return
        await self._inner(scope, receive, send)

    @staticmethod
    async def _refuse(send: Send, message: str) -> None:
        body = json.dumps({"code": "not_authenticated", "detail": message}).encode()
        await send(
            {
                "type": "http.response.start",
                "status": 401,
                "headers": [
                    (b"content-type", b"application/json"),
                    (b"www-authenticate", b'Bearer realm="tefteri"'),
                    (b"content-length", str(len(body)).encode()),
                ],
            }
        )
        await send({"type": "http.response.body", "body": body})
