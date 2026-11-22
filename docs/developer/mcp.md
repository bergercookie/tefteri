# The MCP server and API keys

Tefteri has a built-in MCP server at `/mcp`. An AI assistant connects to it with an API key. This
page tells how it works, how it is tested, and how to add a tool.

## API keys

A key is a long random text that starts with `tft_`. The table `api_keys` keeps only its SHA-256
digest, a short prefix and the time of its last use. The key is shown once, when it is made.

`/me/api-keys` makes, lists and revokes keys. Each user has at most 20 keys.

`current_user` in `api/deps.py` accepts a login token or an API key. A request with a key is marked
(`request.state.via_api_key`). The dependency `SessionUser` refuses such a request. It guards the
routes that a leaked key must not use: keys, password change, users and the export of settings with
credentials.

## The MCP server

The package `tefteri/mcp_server` uses the official MCP SDK (`mcp`, version 1). The server is
stateless: each call stands alone, and the answer is JSON. This works behind any proxy and after a
restart.

- `server.py` builds the server and its ASGI app. `main.py` adds the route `/mcp` and keeps the
  session manager of the SDK running with the app.
- `auth.py` checks the API key of each call before the protocol sees it, and answers a clear 401.
- `client.py` calls the REST API of the app in the same process (an ASGI transport), with the key
  of the call. A tool is a thin layer over the API, so it gets the same checks, the same data and
  the same errors as the app. It also turns UTC times into the local time of the user and the other
  way round.
- `tools.py` has the tools, `prompts.py` has the prompts, `calendar_view.py` has the pure helpers
  (one event once, the free time of a day).

### Rules for a tool

- The name is a verb and a noun. The description says when to use the tool and what it returns.
- A tool that only reads has `readOnlyHint`. A tool that deletes has `destructiveHint`.
- A tool that saves a review asks for the decisions of the user in its description, and a risky save
  has a preview.
- A failure is a message that says what to do next: the list of projects when a name is not known,
  the format of a date when a date is wrong.
- Times that go in without an offset are in the time zone of the user. Times that come out have the
  offset of the user.

### Add a tool

1. Add a function with `@mcp.tool(annotations=...)` in `tools.py`. Call the API with `_session`.
2. Add it to the list of tools in `tests/integration/test_mcp_server.py`, and test the workflow that
   uses it.
3. Add it to the table in the user guide.
4. If a prompt should use it, change `prompts.py`. A test checks that a prompt names only tools
   that exist.

## Tests

`tests/integration/test_mcp_server.py` uses the real MCP client of the SDK. It talks to the app in
the same process. It tests the protocol, the authentication, and the workflows of a user: a task
from idea to done, events, free time, the three reviews, errors and time zones.
`tests/integration/test_api_keys.py` tests the keys. Run both with `just backend::test`.
