"""Helpers for the tests of the MCP server: a real MCP client that talks to the app."""

import asyncio
import json
from collections.abc import AsyncIterator
from contextlib import asynccontextmanager
from typing import Any

from httpx import ASGITransport, AsyncClient
from mcp import ClientSession
from mcp.client.streamable_http import streamable_http_client
from mcp.types import CallToolResult

from tests.conftest import V1


async def make_key(api: AsyncClient, name: str = "Claude") -> str:
    r = await api.post(f"{V1}/me/api-keys", json={"name": name})
    assert r.status_code == 201, r.text
    key: str = r.json()["key"]
    return key


@asynccontextmanager
async def mcp_session(api: AsyncClient, key: str | None = None) -> AsyncIterator[ClientSession]:
    """A connected, initialized MCP client for the user of ``key`` (a new key by default)."""
    key = key or await make_key(api)
    http = AsyncClient(
        transport=ASGITransport(app=api.app),  # type: ignore[attr-defined]
        base_url="http://test",
        headers={"Authorization": f"Bearer {key}"},
    )
    async with (
        http,
        streamable_http_client("http://test/mcp", http_client=http) as (read, write, _),
        ClientSession(read, write) as session,
    ):
        # A client initializes once. The answer is kept for the tests that read it.
        session.initialize_result = await session.initialize()  # type: ignore[attr-defined]
        try:
            yield session
        finally:
            # The client sends "initialized" and goes on without waiting for the answer. A test
            # that ends at once would close the loop while the server still handles it.
            await asyncio.sleep(0.2)


def data(result: CallToolResult) -> Any:
    """The answer of a tool as data."""
    assert not result.isError, [c.model_dump() for c in result.content]
    if result.structuredContent is not None:
        structured = result.structuredContent
        return structured.get("result", structured) if set(structured) == {"result"} else structured
    return json.loads(result.content[0].text)  # type: ignore[union-attr]


async def call(session: ClientSession, name: str, **arguments: Any) -> Any:
    """Call a tool that must work, and return its data."""
    return data(await session.call_tool(name, arguments))


async def fail(session: ClientSession, name: str, **arguments: Any) -> str:
    """Call a tool that must fail, and return the message that the assistant would read."""
    result = await session.call_tool(name, arguments)
    assert result.isError, "the tool should have failed"
    return str(result.content[0].text)  # type: ignore[union-attr]
