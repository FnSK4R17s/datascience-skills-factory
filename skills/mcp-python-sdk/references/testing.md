# Testing and Debugging MCP Servers

Sources: `docs/testing.md`, `docs/migration.md`,
`docs/mcpio__docs__tools__debugging.md`,
`docs/mcpio__docs__tools__inspector.md`

## In-process testing (recommended)

The SDK provides an in-memory transport that connects a client and server
without network overhead. This is the fastest and most reliable way to test
MCP server logic.

## v2 testing with `Client` class (preferred when on v2/main)

`mcp.client.Client` accepts a server instance directly. No transport setup,
no ports, no subprocesses.

### Basic test

```python
# server.py
from mcp.server import MCPServer  # v2 name

app = MCPServer("Calculator")

@app.tool()
def add(a: int, b: int) -> int:
    """Add two numbers."""
    return a + b
```

```python
# test_server.py
import pytest
from inline_snapshot import snapshot
from mcp import Client
from mcp.types import CallToolResult, TextContent

from server import app


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
            structuredContent={"result": 3},
        )
    )
```

`raise_exceptions=True` surfaces server-side errors as Python exceptions
rather than returning `is_error=True` results.

Install dependencies:
```bash
pip install "mcp[cli]" pytest anyio pytest-anyio
pip install inline-snapshot  # optional but recommended for snapshot assertions
```

### Full pytest fixture pattern

```python
import pytest
from mcp import Client
from mcp.types import CallToolResult, TextContent

from mypackage.server import mcp  # your FastMCP or MCPServer instance


@pytest.fixture
def anyio_backend():
    return "asyncio"


@pytest.fixture
async def client():
    """Connected in-process client, reused across tests in a session."""
    async with Client(mcp, raise_exceptions=True) as c:
        yield c


@pytest.mark.anyio
async def test_tool_exists(client):
    tools = await client.list_tools()
    tool_names = [t.name for t in tools.tools]
    assert "add" in tool_names


@pytest.mark.anyio
async def test_add_tool_correct_output(client):
    result = await client.call_tool("add", {"a": 10, "b": 5})
    assert not result.is_error  # check no error first
    assert result.content[0].text == "15"


@pytest.mark.anyio
async def test_add_tool_structured_output(client):
    result = await client.call_tool("add", {"a": 3, "b": 4})
    assert result.structuredContent == {"result": 7}


@pytest.mark.anyio
async def test_resource_read(client):
    resource = await client.read_resource("config://settings")
    assert resource.contents[0].text is not None


@pytest.mark.anyio
async def test_prompt_retrieval(client):
    prompt = await client.get_prompt("greet_user", {"name": "Alice", "style": "friendly"})
    assert len(prompt.messages) > 0


@pytest.mark.anyio
async def test_tool_returns_error_on_bad_input(client):
    # With raise_exceptions=False (default), errors come back as is_error=True
    async with Client(mcp, raise_exceptions=False) as err_client:
        result = await err_client.call_tool("divide", {"a": 1, "b": 0})
    assert result.is_error
    assert "zero" in result.content[0].text.lower()


@pytest.mark.anyio
async def test_capabilities_negotiated(client):
    caps = client.initialize_result.capabilities
    assert caps.tools is not None  # server declared tools capability
```

## v1 in-process testing with `create_connected_server_and_client_session`

In v1, the in-process helper was:

```python
from mcp.shared.memory import create_connected_server_and_client_session
from mcp.server.fastmcp import FastMCP

mcp = FastMCP("Test Server")

@mcp.tool()
def add(a: int, b: int) -> int:
    return a + b

async def test_v1():
    async with create_connected_server_and_client_session(mcp._mcp_server) as session:
        result = await session.call_tool("add", {"a": 1, "b": 2})
        assert result.content[0].text == "3"
```

This is **removed in v2** — use `Client(server)` instead.

## Low-level memory streams (when you need direct ClientSession access)

For transport-level testing when you need the raw `ClientSession`:

```python
import anyio
from mcp.client.session import ClientSession
from mcp.shared.memory import create_client_server_memory_streams

async def test_with_memory_streams():
    async with create_client_server_memory_streams() as (client_streams, server_streams):
        async with anyio.create_task_group() as tg:
            # Run server in background
            tg.start_soon(
                lambda: server.run(
                    *server_streams,
                    server.create_initialization_options()
                )
            )
            # Run client
            async with ClientSession(*client_streams) as session:
                await session.initialize()
                result = await session.call_tool("my_tool", {"x": 1})
                assert not result.isError
            tg.cancel_scope.cancel()  # stop server after client is done
```

`create_client_server_memory_streams` is available in both v1 and v2 at
`mcp.shared.memory`.

## Testing servers with lifespan

If your server has a `lifespan` context manager, `Client(server)` runs it
end-to-end. Ensure test fixtures clean up after themselves:

```python
@pytest.fixture
async def client_with_db():
    """Fixture for server with database lifespan."""
    # The lifespan runs: DB connects, test runs, DB disconnects
    async with Client(mcp, raise_exceptions=True) as c:
        yield c
    # lifespan cleanup (db.disconnect) runs automatically on __aexit__
```

## Testing with sampling callbacks

If your server makes sampling calls (calls the LLM through the client), provide
a mock callback:

```python
from mcp.types import CreateMessageResult, TextContent

async def mock_sampling(context, params) -> CreateMessageResult:
    """Return a predictable LLM response for testing."""
    return CreateMessageResult(
        role="assistant",
        content=TextContent(type="text", text="mocked LLM response"),
        model="mock-model",
        stopReason="endTurn",
    )

async with Client(mcp, sampling_callback=mock_sampling) as client:
    result = await client.call_tool("generate_poem", {"topic": "spring"})
    assert result.content[0].text == "mocked LLM response"
```

## Testing with elicitation callbacks

```python
from mcp.types import ElicitResult

async def auto_accept_elicitation(context, params) -> ElicitResult:
    """Automatically accept all elicitation requests with defaults."""
    return ElicitResult(action="accept", content={"confirm": True})

async def auto_decline_elicitation(context, params) -> ElicitResult:
    return ElicitResult(action="decline")

# Test accept path
async with Client(mcp, elicitation_callback=auto_accept_elicitation) as client:
    result = await client.call_tool("book_table", {"date": "2024-12-25", "party_size": 4})
    assert "Booked" in result.content[0].text

# Test decline path
async with Client(mcp, elicitation_callback=auto_decline_elicitation) as client:
    result = await client.call_tool("book_table", {"date": "2024-12-25", "party_size": 4})
    assert "cancelled" in result.content[0].text.lower()
```

## What to test

- Tool execution with valid inputs → correct output and structure
- Tool execution with invalid inputs → `is_error=True` or raised exception
- Resource reads → expected content and MIME type
- Prompt retrieval → correct message structure and count
- Capabilities negotiation → `initialize_result.capabilities` reflects registered handlers
- Lifespan resources — ensure cleanup runs even when tests fail
- Sampling/elicitation paths — use mock callbacks for determinism

## Async test configuration

The SDK's async tests use `anyio`. Configure in `pytest.ini` or
`pyproject.toml`:

```toml
# pyproject.toml
[tool.pytest.ini_options]
asyncio_mode = "auto"  # if using pytest-asyncio
```

Or use the `anyio_backend` fixture to select explicitly:

```python
@pytest.fixture
def anyio_backend():
    return "asyncio"  # or "trio"
```

## MCP Inspector

Interactive UI for testing stdio and HTTP servers without writing client code:

```bash
# Test a local Python server
npx @modelcontextprotocol/inspector uv run server.py

# Test an HTTP server (start it first, then open Inspector and connect)
uv run server.py &
npx @modelcontextprotocol/inspector

# Add dependencies to the dev environment
npx @modelcontextprotocol/inspector uv --directory path/to/server run package-name
```

The Inspector lets you:
- Invoke tools and see results
- Browse resources and read their content
- Test prompts with different arguments
- Watch the full notification stream
- Inspect the raw JSON-RPC messages

Use it as the first debugging step before integrating with Claude Desktop.

## Debugging common issues

### `-32602 Invalid params` errors

Usually a capability mismatch. Check the `initialize` exchange — one side is
sending a request the other hasn't declared support for (e.g., server sends
`sampling/createMessage` but client didn't declare `sampling` capability).

Also check field names: in v2, `inputSchema` → `input_schema`, etc.

### stdio server not connecting

1. Verify stdout is not being written to (only JSON-RPC messages allowed in stdio).
2. Run the server command directly in a terminal to check for startup errors.
3. Check Claude Desktop logs: `tail -f ~/Library/Logs/Claude/mcp*.log` (macOS).
4. Always use absolute paths for server scripts and environment variables.

### Missing env vars on server side

stdio servers inherit a limited set of env vars from the launch context. Pass
required vars explicitly in `claude_desktop_config.json`:

```json
{
  "mcpServers": {
    "myserver": {
      "command": "python",
      "args": ["/absolute/path/to/server.py"],
      "env": {"API_KEY": "...", "DATABASE_URL": "..."}
    }
  }
}
```

### Config changes not taking effect

- Restart Claude Desktop **fully** — closing the window is not enough; use
  Quit from the application menu.
- Server code changes also require a full restart.

### Testing changes quickly

- During development, use MCP Inspector for rapid iteration without restarting
  Claude Desktop.
- Use `Client(server)` in pytest for fast, repeatable unit tests.

## Gotchas

- **`raise_exceptions=False` (default):** Tool errors come back as
  `result.is_error=True` with error text in `result.content`. Do not assert
  on the happy path without checking `is_error` first.
- **Snapshot drift:** `inline-snapshot` auto-updates snapshots on first run;
  commit the generated values.
- **Lifespan in tests:** `Client(server)` runs the lifespan end-to-end — ensure
  test fixtures provide any required infrastructure (mock DBs, etc.).
- **Context managers leak:** Forgetting `async with` on sessions or transports
  causes silent resource leaks and deadlocks in test teardown.
