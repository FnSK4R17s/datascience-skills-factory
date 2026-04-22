# Testing MCP Servers

Testing MCP servers in Python has two layers:

1. **Unit layer** — test handler logic in isolation, no transport.
2. **Integration layer** — wire a real client and server through an in-process
   transport, exercise the full JSON-RPC exchange.

Both layers matter. Unit tests are fast but miss protocol-level bugs (capability
negotiation, message ordering, error code correctness). Integration tests catch
these but are slower and harder to parameterize.

## In-process transport

The SDK ships `mcp.server.memory` (sometimes imported via
`mcp.server.models`) with an in-memory transport that connects client and
server without network or subprocess overhead. This is the right tool for
integration tests.

```python
import pytest
from mcp import ClientSession
from mcp.server.fastmcp import FastMCP
from mcp.server.memory import create_connected_server_and_client_session

@pytest.fixture
async def server():
    mcp = FastMCP("test-server")

    @mcp.tool()
    async def add(x: int, y: int) -> int:
        """Add two numbers."""
        return x + y

    return mcp

@pytest.fixture
async def client(server):
    async with create_connected_server_and_client_session(server._server) as session:
        yield session
```

The exact import path for `create_connected_server_and_client_session` may
vary by SDK version — check the SDK changelog and search the package for the
current name if the above import fails.

## Writing async tests

The MCP SDK is fully async. Use pytest-anyio or pytest-asyncio:

```python
# pyproject.toml
[tool.pytest.ini_options]
asyncio_mode = "auto"  # pytest-asyncio auto mode

# Or with anyio
# anyio_backends = ["asyncio"]
```

```python
async def test_add_tool(client: ClientSession):
    await client.initialize()
    result = await client.call_tool("add", {"x": 3, "y": 4})
    assert not result.isError
    assert result.content[0].text == "7"
```

## Testing error paths

Verify that tools return proper error results (not exceptions) for invalid
inputs:

```python
async def test_tool_error(client: ClientSession):
    await client.initialize()
    result = await client.call_tool("divide", {"x": 1, "y": 0})
    assert result.isError
    # isError = True means the tool returned an error TextContent block
    # The session itself did not raise an exception
```

For protocol-level errors (wrong method, missing capability), expect
`McpError` to be raised:

```python
from mcp import McpError

async def test_unknown_tool(client: ClientSession):
    await client.initialize()
    with pytest.raises(McpError):
        await client.call_tool("nonexistent_tool", {})
```

## Mocking transport for unit tests

When you only want to test handler logic without any client involvement, call
the handler function directly:

```python
# FastMCP: extract the underlying function
from mypackage.server import mcp

async def test_add_handler_directly():
    # FastMCP stores the original function; call it directly
    # This skips schema validation and protocol wrapping
    result = await mcp._tool_manager.tools["add"].fn(x=3, y=4)
    assert result == 7
```

Direct handler calls skip schema validation and capability checking — useful
for unit testing logic but not for testing protocol conformance.

## Testing resources

```python
async def test_resource_read(client: ClientSession):
    await client.initialize()
    result = await client.read_resource("mydata://items/42")
    assert len(result.contents) == 1
    assert "42" in result.contents[0].text
```

## Testing prompts

```python
async def test_prompt_get(client: ClientSession):
    await client.initialize()
    result = await client.get_prompt("analyze", {"topic": "async"})
    assert len(result.messages) >= 1
    assert result.messages[0].role == "user"
```

## Checking capability negotiation

Verify the server declares the right capabilities:

```python
async def test_capabilities(client: ClientSession):
    result = await client.initialize()
    caps = result.capabilities
    assert caps.tools is not None       # tools registered
    assert caps.resources is not None   # resources registered
    assert caps.prompts is None         # no prompts registered
```

## Common test pitfalls

**Not calling `initialize()`.** Every client fixture must call
`await session.initialize()` before any operation. Forgetting this produces
confusing errors about unexpected message order.

**Sharing sessions across tests.** Each test should get a fresh session.
Use fixtures with function scope (pytest default).

**Asserting on content type before checking `isError`.** If `result.isError`
is True, `result.content` may still be populated with an error `TextContent`.
Check `isError` first, then inspect content.

**stdout pollution.** If any handler calls `print()`, it corrupts the stdio
transport. In tests using the in-process transport this is harmless, but the
habit will break stdio deployments. Use `ctx.info()` instead.
