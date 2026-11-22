"""Builds the MCP server and the ASGI app that serves it at ``/mcp``."""

import asyncio
from collections.abc import AsyncIterator
from contextlib import asynccontextmanager, suppress
from dataclasses import dataclass
from typing import Any

from mcp.server.fastmcp import FastMCP
from mcp.server.transport_security import TransportSecuritySettings

from tefteri.auth.service import AuthService
from tefteri.mcp_server import prompts, tools
from tefteri.mcp_server.auth import Asgi, RequireApiKey

SHUTDOWN_SECONDS = 5.0
"""How long the protocol gets to finish its calls when the app stops."""

MCP_PATH = "/mcp"
"""Where the server is: ``https://<your server>/mcp``."""

INSTRUCTIONS = """\
Tefteri is the user's planner: tasks (kept in their task app), a calendar, daily notes, and a
weekly, monthly and annual review. These tools read and change it.

Start with get_overview: it says what day it is for the user, and which calendars and projects
they have. Times that you receive are local times of the user. Times that you send are local
unless they carry an offset: 2030-03-10T14:30 is 14:30 where the user lives.

To plan, use get_day, get_week, list_tasks and find_free_time, then schedule_task and
create_event. For a review, call get_weekly_review, get_monthly_review or get_annual_review,
base what you say on the numbers in them, and ask the user before you save anything with
submit_weekly_review, save_monthly_review or save_annual_review_note. Ask before you delete.
"""


@dataclass
class McpServer:
    """The MCP server: the ASGI app for ``/mcp`` and the manager that must run with the app."""

    asgi: Asgi
    server: FastMCP

    @asynccontextmanager
    async def run(self) -> AsyncIterator[None]:
        """Keep the protocol running while the app runs.

        The session manager of the protocol holds a task group, which must be entered and left in
        one task. It runs in a task of its own, so that it does not matter which task starts and
        stops the app.
        """
        started = asyncio.Event()
        stop = asyncio.Event()

        async def hold() -> None:
            async with self.server.session_manager.run():
                started.set()
                await stop.wait()

        task = asyncio.create_task(hold(), name="mcp-sessions")
        ready = asyncio.create_task(started.wait())
        await asyncio.wait({task, ready}, return_when=asyncio.FIRST_COMPLETED)
        if task.done():
            ready.cancel()
            task.result()  # raises why it could not start
        try:
            yield
        finally:
            stop.set()
            # A call that is still running when the app stops must not keep the app from
            # stopping: give the protocol a few seconds, then cancel it.
            await asyncio.wait({task}, timeout=SHUTDOWN_SECONDS)
            if not task.done():
                task.cancel()
            with suppress(asyncio.CancelledError):
                await task


def build_mcp(app: Any, auth: AuthService, session_factory: Any) -> McpServer:
    """Build the server for ``app``. Its tools call the API of ``app`` with the key of the call."""
    server = FastMCP(
        name="tefteri",
        instructions=INSTRUCTIONS,
        # A call stands alone: no session to keep, so it works behind any proxy or restart.
        stateless_http=True,
        json_response=True,
        streamable_http_path="/",
        # Tefteri runs under any host name, and every call needs an API key anyway.
        transport_security=TransportSecuritySettings(enable_dns_rebinding_protection=False),
    )
    tools.register(server, app)
    prompts.register(server)
    inner = server.streamable_http_app().routes[0].endpoint  # type: ignore[attr-defined]
    return McpServer(RequireApiKey(inner, auth, session_factory), server)
