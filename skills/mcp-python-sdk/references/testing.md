# Testing and Debugging MCP Servers

Sources: `docs/testing.md`, `docs/migration.md`,
`docs/mcpio__docs__tools__debugging.md`,
`docs/mcpio__docs__tools__inspector.md`

## In-process testing (recommended)

The SDK provides an in-memory transport that connects a client and server
without network overhead. This is the fastest and most reliable way to test
MCP server logic.

### v2: `Client` class (preferred)

`mcp.client.Client` accepts a server instance directly:

```python
from mcp.client import Client
from mcp.server import MCPServer  # v2 name

async with Client(server, raise_exceptions=True) as client:
    result = await client.call_tool("add", {"a": 1, "b": 2})
    assert result.content[0].text == "3"
```

`raise_exceptions=True` surfaces server-side errors as Python exceptions
rather than returning `is_error=True` results.

### v2: pytest pattern

```python
import pytest
from mcp import Client
from mcp.types import CallToolResult, TextContent
from inline_snapshot import snapshot

from server import app  # your MCPServer or Server instance

@pytest.fixture
def anyio_backend():
    return "asyncio"

@pytest.fixture
async def client():
    async with Client(app, raise_exceptions=True) as c:
        yield c

@pytest.mark.anyio
async def test_call_add_tool(client: Client):
    result = await client.call_tool("add", {"a": 1, "b": 2})
    assert result == snapshot(
        CallToolResult(
            content=[TextContent(type="text", text="3")],
            structured_content={"result": 3},
        )
    )
```

Source: `docs/testing.md`. The `inline-snapshot` library is optional but
useful for snapshot assertions.

### v1: `create_connected_server_and_client_session`

In v1, the in-process helper was:

```python
from mcp.shared.memory import create_connected_server_and_client_session

async with create_connected_server_and_client_session(server) as session:
    result = await session.call_tool("my_tool", {"x": 1})
```

This is removed in v2 — use `Client(server)` instead.

### v2: low-level memory streams

For transport-level testing (when you need direct `ClientSession` access):

```python
import anyio
from mcp.client.session import ClientSession
from mcp.shared.memory import create_client_server_memory_streams

async with create_client_server_memory_streams() as (client_streams, server_streams):
    async with anyio.create_task_group() as tg:
        tg.start_soon(lambda: server.run(*server_streams, server.create_initialization_options()))
        async with ClientSession(*client_streams) as session:
            await session.initialize()
            result = await session.call_tool("my_tool", {"x": 1})
        tg.cancel_scope.cancel()
```

`create_client_server_memory_streams` remains available in v2 in
`mcp.shared.memory`.

## What to test

- Tool execution with valid inputs → correct output.
- Tool execution with invalid inputs → `is_error=True` or raised exception.
- Resource reads → expected content and MIME type.
- Prompt retrieval → correct message structure.
- Capabilities negotiation — verify `initialize_result.capabilities` reflects
  registered handlers.

## Dependency installation

```bash
# pytest + anyio required
pip install "mcp[cli]" pytest anyio

# optional: snapshot testing
pip install inline-snapshot
```

## Async test configuration

The SDK's async tests use `anyio`. Configure `anyio_backend` via fixture
or `pytest.ini`:

```ini
# pytest.ini or pyproject.toml
[tool.pytest.ini_options]
asyncio_mode = "auto"  # if using pytest-asyncio
```

Or use the `anyio_backend` fixture as shown above to select the backend
explicitly.

## Gotchas

- **`raise_exceptions=False` (default):** tool errors come back as
  `result.is_error=True` with error text in `result.content`. Don't assert
  on the happy path without checking `is_error` first.
- **Snapshot drift:** inline-snapshot auto-updates snapshots on first run;
  commit the generated snapshot values.
- **Lifespan in tests:** if your server has a `lifespan` context manager,
  `Client(server)` runs it end-to-end — ensure test fixtures clean up after
  themselves.

## MCP Inspector

Interactive UI for testing stdio and HTTP servers without writing client code:

```bash
# npm / PyPI package
npx @modelcontextprotocol/inspector uvx mcp-server-git --repository ~/code/mcp

# Locally developed Python server
npx @modelcontextprotocol/inspector uv --directory path/to/server run package-name
```

The Inspector lets you invoke tools, browse resources, test prompts, and watch
the notification stream. Use it as the first debugging step before integrating
with Claude Desktop or another host.

## Debugging common issues

### `-32602 Invalid params` errors

Usually a capability mismatch. Check the `initialize` exchange — one side is
sending a request the other hasn't declared support for (e.g. server sends
`sampling/createMessage` but client didn't declare `sampling` capability).

### stdio server not connecting

1. Verify stdout is not being written to (only JSON-RPC messages allowed).
2. Run the server command directly in a terminal to check for startup errors.
3. Check logs: `tail -f ~/Library/Logs/Claude/mcp*.log` (macOS).
4. Always use absolute paths for server scripts and environment variables.

### Environment variables missing

stdio servers inherit a limited set of env vars from the launch context.
Pass required vars explicitly in `claude_desktop_config.json`:

```json
{"mcpServers": {"myserver": {"command": "...", "env": {"API_KEY": "..."}}}}
```

### Testing changes

- Config changes: restart the MCP client fully (close the window is not enough
  for Claude Desktop — use Quit from the application menu).
- Server code changes: restart the client.
- During development: use MCP Inspector for rapid iteration without restarting.
