# MCPServer — v2 Pre-Alpha API

Sources: `docs/migration.md`, `docs/testing.md`

> **Status**: MCPServer is the v2 rename of FastMCP. v2 is pre-alpha on `main`.
> v1 (`FastMCP`) is the current stable release.
> Use v1 for production. Use v2 only when targeting the `main` branch.

## What changed from FastMCP to MCPServer

The rename is mechanical with these additional breaking changes:
1. Transport params (`host`, `port`, `json_response`, `stateless_http`, etc.) moved from constructor to `run()` / `sse_app()` / `streamable_http_app()`
2. `get_context()` removed — use `ctx: Context` parameter injection instead
3. `Context` type parameter simplified: `Context[ServerSessionT, LifespanContextT]` → `Context[LifespanContextT]`
4. Log methods take `data: Any` instead of `message: str`
5. `mount_path` constructor param removed
6. `MCPServer.call_tool()`, `read_resource()`, `get_prompt()` now accept optional `context` param

See `references/migration-v1-to-v2.md` for the complete breaking-change catalog.

## Basic structure

```python
from mcp.server.mcpserver import MCPServer, Context

mcp = MCPServer("Test Server")


@mcp.tool()
def add(a: int, b: int) -> int:
    """Add two numbers."""
    return a + b


@mcp.resource("greeting://{name}")
def get_greeting(name: str) -> str:
    """Get a personalized greeting."""
    return f"Hello, {name}!"


@mcp.prompt()
def greet_user(name: str, style: str = "friendly") -> str:
    """Generate a greeting prompt."""
    return f"Write a {style} greeting for someone named {name}."


if __name__ == "__main__":
    # Transport params on run(), not constructor
    mcp.run(transport="streamable-http")
```

## Import paths in v2

```python
# Core server class and context
from mcp.server.mcpserver import MCPServer, Context

# Prompt message helpers
from mcp.server.mcpserver.prompts.base import UserMessage, AssistantMessage

# Media types
from mcp.server.mcpserver.utilities.types import Image, Audio
from mcp.server.mcpserver import Image, Audio  # also available here

# Exception types
from mcp.server.mcpserver.exceptions import ToolError, ResourceError
```

## Transport params in v2

All transport-specific configuration moves to the method that starts the server.
Only `name`, `auth`, `debug`, and `log_level` stay in the constructor.

```python
# v2 — run()
mcp = MCPServer("Demo")
mcp.run(transport="streamable-http", json_response=True, stateless_http=True)
mcp.run(transport="sse", host="0.0.0.0", port=9000, sse_path="/events")

# v2 — when mounting to Starlette
app = Starlette(routes=[
    Mount("/", app=mcp.streamable_http_app(json_response=True))
])
```

## Context injection in v2

```python
from mcp.server.mcpserver import Context

# Bare Context — works for most tools
@mcp.tool()
async def my_tool(x: int, ctx: Context) -> str:
    await ctx.info("Processing...")  # data: Any, not message: str
    return str(x)

# With explicit lifespan type
@dataclass
class AppState:
    db: Database

@mcp.tool()
async def db_tool(query: str, ctx: Context[AppState]) -> str:
    app: AppState = ctx.request_context.lifespan_context
    return str(app.db.query(query))
```

## Logging API change in v2

```python
# v1 (FastMCP)
await ctx.info("message string")
await ctx.info("message", extra={"host": "localhost"})

# v2 (MCPServer) — data: Any
await ctx.info("message string")           # bare strings still work
await ctx.info({"message": "Connection failed", "host": "localhost"})
await ctx.log(level="notice", data="hello")

# All 8 RFC-5424 levels
await ctx.log(level="debug", data="...")
await ctx.log(level="info", data="...")
await ctx.log(level="notice", data="...")
await ctx.log(level="warning", data="...")
await ctx.log(level="error", data="...")
await ctx.log(level="critical", data="...")
await ctx.log(level="alert", data="...")
await ctx.log(level="emergency", data="...")
```

## Lifespan in v2

Same pattern as v1, but with simplified Context type:

```python
from collections.abc import AsyncIterator
from contextlib import asynccontextmanager
from dataclasses import dataclass

from mcp.server.mcpserver import MCPServer, Context


@dataclass
class AppContext:
    db: Database


@asynccontextmanager
async def app_lifespan(server: MCPServer) -> AsyncIterator[AppContext]:
    db = await Database.connect()
    try:
        yield AppContext(db=db)
    finally:
        await db.disconnect()


mcp = MCPServer("My App", lifespan=app_lifespan)


@mcp.tool()
async def query_db(sql: str, ctx: Context[AppContext]) -> str:
    app: AppContext = ctx.request_context.lifespan_context
    return str(app.db.query(sql))
```

## Registering lowlevel handlers via MCPServer (v2 workaround)

MCPServer does not expose public APIs for `subscribe_resource`,
`unsubscribe_resource`, or `set_logging_level`. Use the private
`_add_request_handler`:

```python
from mcp.server import ServerRequestContext
from mcp.types import EmptyResult, SetLevelRequestParams, SubscribeRequestParams


async def handle_set_level(ctx: ServerRequestContext, params: SetLevelRequestParams) -> EmptyResult:
    # Store log level for server-side filtering
    return EmptyResult()


async def handle_subscribe(ctx: ServerRequestContext, params: SubscribeRequestParams) -> EmptyResult:
    # Register subscription for params.uri
    return EmptyResult()


mcp._lowlevel_server._add_request_handler("logging/setLevel", handle_set_level)
mcp._lowlevel_server._add_request_handler("resources/subscribe", handle_subscribe)
```

This is a private API and may change. A public API is planned.

## Testing with MCPServer (v2)

```python
import pytest
from mcp import Client
from mcp.types import CallToolResult, TextContent

from server import mcp  # your MCPServer instance


@pytest.fixture
def anyio_backend():
    return "asyncio"


@pytest.fixture
async def client():
    async with Client(mcp, raise_exceptions=True) as c:
        yield c


@pytest.mark.anyio
async def test_add_tool(client: Client):
    result = await client.call_tool("add", {"a": 3, "b": 4})
    assert not result.is_error
    assert result.content[0].text == "7"
    assert result.structured_content == {"result": 7}
```

See `references/testing.md` for the full pytest pattern.

## Decision guide

| Scenario | Use |
|----------|-----|
| Starting a new server today, stable production | FastMCP (v1) |
| Experimenting with v2 features or migrating | MCPServer (v2) |
| Need full protocol control | lowlevel `Server` |
| Need subscribe_resource or set_logging_level | lowlevel `Server` or private workaround |

Pick one and commit. Do not mix `FastMCP` and `MCPServer` imports.
