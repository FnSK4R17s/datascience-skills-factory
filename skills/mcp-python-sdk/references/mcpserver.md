# MCPServer — v2 Pre-Alpha API

Sources: `docs/index.md` (v2 index), `docs/migration.md`

> **Status**: MCPServer is the v2 rename of FastMCP. v2 is pre-alpha on `main`.
> v1 (`FastMCP`) is the current stable release.

## What changed in v2

`MCPServer` is `FastMCP` with:
- Moved transport params from constructor to `run()` / `sse_app()` / `streamable_http_app()`
- `get_context()` removed — use `ctx: Context` parameter injection instead
- `Context` type parameter simplified to `Context[LifespanContextT]`
- Log methods take `data: Any` instead of `message: str`
- `mount_path` constructor param removed

See `references/migration-v1-to-v2.md` for the complete breaking-change catalog.

## Basic structure (v2)

```python
from mcp.server.mcpserver import MCPServer

mcp = MCPServer("Test Server", json_response=True)

@mcp.tool()
def add(a: int, b: int) -> int:
    """Add two numbers"""
    return a + b

@mcp.resource("greeting://{name}")
def get_greeting(name: str) -> str:
    """Get a personalized greeting"""
    return f"Hello, {name}!"

@mcp.prompt()
def greet_user(name: str, style: str = "friendly") -> str:
    """Generate a greeting prompt"""
    return f"Write a {style} greeting for someone named {name}."

if __name__ == "__main__":
    mcp.run(transport="streamable-http")
```

Source: `docs/index.md` quickstart.

## Import paths in v2

```python
# v2 imports
from mcp.server.mcpserver import MCPServer, Context
from mcp.server.mcpserver.prompts.base import UserMessage, AssistantMessage
from mcp.server.mcpserver.utilities.types import Image, Audio
from mcp.server.mcpserver.exceptions import ToolError, ResourceError
```

## Transport params in v2

All transport-specific configuration moves to the method that starts the server:

```python
mcp = MCPServer("Demo")  # only name, auth, debug, log_level stay in constructor
mcp.run(transport="streamable-http", json_response=True, stateless_http=True)
mcp.run(transport="sse", host="0.0.0.0", port=9000, sse_path="/events")
```

When mounting in a Starlette app:

```python
app = Starlette(routes=[
    Mount("/", app=mcp.streamable_http_app(json_response=True))
])
```

## Context injection in v2

```python
from mcp.server.mcpserver import Context

@mcp.tool()
async def my_tool(x: int, ctx: Context) -> str:
    await ctx.info("Processing...")  # data: Any, not message: str
    return str(x)

# With explicit lifespan type:
@mcp.tool()
async def typed_tool(x: int, ctx: Context[MyLifespanState]) -> str:
    db = ctx.request_context.lifespan_context.db
    return db.query()
```

## Server.call_tool / read_resource / get_prompt with context param (v2)

These methods now accept an optional `context: Context | None = None`:

```python
# Called automatically during request handling
# If you invoke them directly and omit context, a contextless Context is built
# Tools that don't use ctx work fine; ctx.session etc. will raise without active request
```

## Registering lowlevel handlers via MCPServer (v2 workaround)

MCPServer does not expose public APIs for `subscribe_resource`,
`unsubscribe_resource`, or `set_logging_level`. Use the private
`_add_request_handler`:

```python
mcp._lowlevel_server._add_request_handler("logging/setLevel", handle_set_level)
```

This is private and subject to change. A public API is planned.

## Testing with MCPServer (v2)

```python
from mcp import Client

async with Client(mcp, raise_exceptions=True) as client:
    result = await client.call_tool("add", {"a": 1, "b": 2})
```

See `references/testing.md` for the full pytest pattern.

## Decision guide

| Scenario | Use |
|----------|-----|
| Starting a new server today, stable production | FastMCP (v1 stable) |
| Experimenting with v2 features or migrating | MCPServer (v2 pre-alpha) |
| Need full protocol control | lowlevel `Server` |

Pick one and commit. Do not mix `FastMCP` and `MCPServer` imports.
