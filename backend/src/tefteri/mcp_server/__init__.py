"""The MCP server that is built into tefteri.

An AI assistant that speaks the Model Context Protocol (Claude, for example) connects to
``/mcp`` with an API key. The tools here are a thin, careful layer over the REST API of the
app: each tool calls the API in the same process, with the key of the caller, so it gets the
same checks and the same data as the app itself.
"""

from tefteri.mcp_server.server import MCP_PATH, McpServer, build_mcp

__all__ = ["MCP_PATH", "McpServer", "build_mcp"]
