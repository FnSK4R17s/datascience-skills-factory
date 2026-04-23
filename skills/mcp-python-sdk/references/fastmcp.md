# FastMCP — High-Level Server API

Sources: `docs/README.md`, `docs/mcpio__docs__develop__build-server.md`,
`docs/migration.md`

## What FastMCP is

`FastMCP` (v1: `mcp.server.fastmcp.FastMCP`; v2: renamed to `MCPServer` at
`mcp.server.mcpserver.MCPServer`) is the recommended starting point for new
MCP servers. It provides decorator-driven registration and handles capability
declaration, JSON Schema generation from type annotations, and error wrapping.

The v2 rename is a mechanical change — `FastMCP` and `MCPServer` are
functionally identical except for transport parameter placement (see below).

## Basic structure

```python
from mcp.server.fastmcp import FastMCP

mcp = FastMCP("Demo")

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
    return f"Please write a {style} greeting for {name}."

if __name__ == "__main__":
    mcp.run(transport="streamable-http")
```

Source: `docs/README.md` quickstart example.

## Tool registration

FastMCP infers the JSON Schema input from Python type annotations. The
function docstring becomes the tool description. Both sync and async
functions are supported.

```python
from typing import Annotated
from pydantic import Field, BaseModel

class WeatherData(BaseModel):
    temperature: float
    condition: str

@mcp.tool()
def get_weather(
    city: Annotated[str, Field(description="City name")],
    unit: str = "celsius",
) -> WeatherData:
    """Get weather for a city — returns structured data."""
    return WeatherData(temperature=22.5, condition="sunny")
```

**Structured output** is automatic when the return type annotation is a
Pydantic model, `TypedDict`, dataclass with type hints, or `dict[str, T]`.
Primitive return types and generic containers are wrapped in `{"result": val}`.

To suppress structured output: `@mcp.tool(structured_output=False)`.

For full control, return `CallToolResult` directly:

```python
from mcp.types import CallToolResult, TextContent

@mcp.tool()
def advanced_tool() -> CallToolResult:
    return CallToolResult(
        content=[TextContent(type="text", text="visible to model")],
        _meta={"hidden": "client-only data"},
    )
```

`CallToolResult` must always be returned directly (no `Optional` or `Union`).
For empty results: `CallToolResult(content=[])`.

## Resource registration

Static URI (no parameters):

```python
@mcp.resource("config://settings")
def get_settings() -> str:
    return '{"theme": "dark"}'
```

Dynamic URI template (parameters extracted from URI pattern):

```python
@mcp.resource("file://documents/{name}")
def read_document(name: str) -> str:
    return f"Content of {name}"
```

## Prompt registration

```python
from mcp.server.fastmcp.prompts import base

@mcp.prompt(title="Code Review")
def review_code(code: str) -> str:
    return f"Please review this code:\n\n{code}"

@mcp.prompt(title="Debug Assistant")
def debug_error(error: str) -> list[base.Message]:
    return [
        base.UserMessage("I'm seeing this error:"),
        base.UserMessage(error),
        base.AssistantMessage("I'll help debug. What have you tried?"),
    ]
```

## Context object

Add `ctx: Context` (any parameter name, typed `Context`) to access server
internals within a handler. The framework injects it automatically.

```python
from mcp.server.fastmcp import Context, FastMCP

@mcp.tool()
async def long_task(name: str, ctx: Context, steps: int = 5) -> str:
    await ctx.info(f"Starting: {name}")
    for i in range(steps):
        await ctx.report_progress((i + 1) / steps, 1.0, message=f"Step {i+1}/{steps}")
        await ctx.debug(f"Completed step {i+1}")
    return f"Task '{name}' completed"
```

Context properties and methods:
- `ctx.request_id` — unique ID for the current request
- `ctx.client_id` — client ID if available
- `ctx.fastmcp` — the `FastMCP` server instance
- `ctx.session` — raw `ServerSession` for advanced use
- `ctx.request_context` — request-specific data and lifespan state
- `await ctx.debug/info/warning/error(message)` — send log to client
- `await ctx.report_progress(progress, total=None, message=None)` — progress
- `await ctx.read_resource(uri)` — read a resource from within a handler
- `await ctx.elicit(message, schema)` — request user input

In v2 (`MCPServer.Context`), log methods accept `data: Any` instead of
`message: str`. Bare `ctx.info("string")` still works; structured data is
passed as `data={"key": "val"}`.

## Lifespan (startup/teardown)

```python
from contextlib import asynccontextmanager
from dataclasses import dataclass

@dataclass
class AppContext:
    db: Database

@asynccontextmanager
async def app_lifespan(server: FastMCP):
    db = await Database.connect()
    try:
        yield AppContext(db=db)
    finally:
        await db.disconnect()

mcp = FastMCP("My App", lifespan=app_lifespan)

@mcp.tool()
def query_db(ctx: Context) -> str:
    db = ctx.request_context.lifespan_context.db
    return db.query()
```

Source: `docs/README.md` lifespan example.

## Composition and mounting

Mount sub-servers to split a large server into logical modules without
separate processes. Tools get prefixed with the mount name.

```python
main = FastMCP("main")
sub = FastMCP("sub-module")

@sub.tool()
def sub_tool(x: int) -> int:
    return x * 2

main.mount("math", sub)  # tool becomes "math/sub_tool"
```

Mounted servers share the parent's transport.

## Running the server

v1 syntax (transport params on the constructor or `run()`):

```python
mcp.run()                                       # stdio (default)
mcp.run(transport="streamable-http")            # HTTP on 127.0.0.1:8000
mcp.run(transport="sse")                        # deprecated SSE transport

# With CORS for browser clients (v1)
mcp = FastMCP("Demo", json_response=True)
```

v2 syntax (`MCPServer`, transport params moved to `run()` / app methods):

```python
from mcp.server.mcpserver import MCPServer

mcp = MCPServer("Demo")
mcp.run(transport="streamable-http", json_response=True, stateless_http=True)
mcp.run(transport="sse", host="0.0.0.0", port=9000, sse_path="/events")
```

Source: `docs/migration.md`.

## v2 (MCPServer) import changes

```python
# v1 imports
from mcp.server.fastmcp import FastMCP, Context
from mcp.server.fastmcp.prompts import base

# v2 imports (after rename)
from mcp.server.mcpserver import MCPServer, Context
from mcp.server.mcpserver.prompts.base import UserMessage, AssistantMessage
```

## Icons (v1 README)

```python
from mcp.server.fastmcp import FastMCP, Icon

icon = Icon(src="icon.png", mimeType="image/png", sizes="64x64")
mcp = FastMCP("My Server", icons=[icon])

@mcp.tool(icons=[icon])
def my_tool(): ...
```

## When to leave FastMCP for the low-level API

- Need custom request/response interception at protocol level.
- Need to register handlers that aren't supported by FastMCP decorators
  (e.g., `subscribe_resource`, `set_logging_level` — these require
  `mcp._mcp_server` workarounds in v1 or `_add_request_handler` in v2).
- Need middleware wrapping every incoming message.
- Prefer explicit control over capability negotiation.

See `references/low-level-server.md`.
