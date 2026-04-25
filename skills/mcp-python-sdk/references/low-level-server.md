# Low-Level Server

Sources: `docs/migration.md` (v2 handler API),
`docs/README.md` (v1 low-level section),
`docs/mcpio__specification__2025-11-25__server__index.md`

## What it is

The lowlevel `Server` class is the raw protocol layer. It provides no decorator
magic, no schema inference, no automatic wrapping — you construct and return full
MCP result types yourself.

**Use it when:**
- FastMCP's convenience layer is in the way.
- You need full control of result types and response structure.
- You need custom protocol extensions or middleware.
- You need handlers not exposed by FastMCP (e.g., `subscribe_resource`,
  `set_logging_level`).

Most servers should start with `FastMCP` and drop to lowlevel only for specific
handlers.

**Import paths:**
- v1: `mcp.server.lowlevel.server.Server`
- v2: `mcp.server.Server`

## v1 pattern (decorator-based)

In v1, handlers were registered via decorator methods:

```python
import asyncio
import mcp.types as types
import mcp.server.stdio
from mcp.server.lowlevel import NotificationOptions, Server
from mcp.server.models import InitializationOptions

server = Server("example-server")


@server.list_prompts()
async def handle_list_prompts() -> list[types.Prompt]:
    """List available prompts."""
    return [
        types.Prompt(
            name="example-prompt",
            description="An example prompt template",
            arguments=[
                types.PromptArgument(
                    name="arg1",
                    description="Example argument",
                    required=True,
                )
            ],
        )
    ]


@server.get_prompt()
async def handle_get_prompt(
    name: str,
    arguments: dict[str, str] | None,
) -> types.GetPromptResult:
    """Get a specific prompt by name."""
    if name != "example-prompt":
        raise ValueError(f"Unknown prompt: {name}")

    arg1_value = (arguments or {}).get("arg1", "default")

    return types.GetPromptResult(
        description="Example prompt",
        messages=[
            types.PromptMessage(
                role="user",
                content=types.TextContent(
                    type="text",
                    text=f"Prompt text with arg: {arg1_value}",
                ),
            )
        ],
    )


@server.list_tools()
async def handle_list_tools() -> list[types.Tool]:
    return [
        types.Tool(
            name="my_tool",
            description="A tool",
            inputSchema={
                "type": "object",
                "properties": {"x": {"type": "integer"}},
                "required": ["x"],
            },
        )
    ]


@server.call_tool()
async def handle_call_tool(
    name: str,
    arguments: dict,
) -> list[types.TextContent]:
    if name != "my_tool":
        raise ValueError(f"Unknown tool: {name}")
    return [types.TextContent(type="text", text=f"Result: {arguments['x'] * 2}")]


async def run():
    async with mcp.server.stdio.stdio_server() as (read_stream, write_stream):
        await server.run(
            read_stream,
            write_stream,
            InitializationOptions(
                server_name="example",
                server_version="0.1.0",
                capabilities=server.get_capabilities(
                    notification_options=NotificationOptions(),
                    experimental_capabilities={},
                ),
            ),
        )


if __name__ == "__main__":
    asyncio.run(run())
```

v1 decorators auto-wrapped return values: bare lists became result types,
dicts became `structured_content + TextContent`, etc.

## v1 — full tools + resources + lifespan example

```python
import asyncio
from collections.abc import AsyncIterator
from contextlib import asynccontextmanager
from typing import Any

import mcp.server.stdio
import mcp.types as types
from mcp.server.lowlevel import NotificationOptions, Server
from mcp.server.models import InitializationOptions


class Database:
    @classmethod
    async def connect(cls) -> "Database":
        return cls()

    async def disconnect(self) -> None:
        pass

    async def query(self, sql: str) -> list[dict[str, str]]:
        return [{"id": "1", "result": sql}]


@asynccontextmanager
async def server_lifespan(_server: Server) -> AsyncIterator[dict[str, Any]]:
    db = await Database.connect()
    try:
        yield {"db": db}
    finally:
        await db.disconnect()


server = Server("db-server", lifespan=server_lifespan)


@server.list_tools()
async def handle_list_tools() -> list[types.Tool]:
    return [
        types.Tool(
            name="query_db",
            description="Execute a database query",
            inputSchema={
                "type": "object",
                "properties": {
                    "sql": {"type": "string", "description": "SQL query"}
                },
                "required": ["sql"],
            },
        )
    ]


@server.call_tool()
async def handle_call_tool(
    name: str,
    arguments: dict[str, Any],
) -> list[types.TextContent]:
    if name != "query_db":
        raise ValueError(f"Unknown tool: {name}")

    # Access lifespan context via server.request_context
    ctx = server.request_context
    db: Database = ctx.lifespan_context["db"]
    results = await db.query(arguments["sql"])

    return [types.TextContent(type="text", text=str(results))]


@server.list_resources()
async def handle_list_resources() -> list[types.Resource]:
    from pydantic import AnyUrl
    return [
        types.Resource(
            uri=AnyUrl("db://schema"),
            name="Database Schema",
            description="Current database schema",
            mimeType="text/plain",
        )
    ]


@server.read_resource()
async def handle_read_resource(uri: Any) -> str:
    return "CREATE TABLE users (id INT, name TEXT);"


async def run():
    async with mcp.server.stdio.stdio_server() as (read, write):
        await server.run(
            read,
            write,
            InitializationOptions(
                server_name="db-server",
                server_version="0.1.0",
                capabilities=server.get_capabilities(
                    notification_options=NotificationOptions(),
                    experimental_capabilities={},
                ),
            ),
        )


if __name__ == "__main__":
    asyncio.run(run())
```

## v2 pattern (constructor `on_*` params)

In v2, all handlers are registered as `on_*` keyword arguments to the
constructor. Handlers receive `(ctx: ServerRequestContext, params: ...)` and
must return fully constructed result types. No auto-wrapping.

```python
from mcp.server import Server, ServerRequestContext
from mcp.types import (
    CallToolRequestParams,
    CallToolResult,
    ListToolsResult,
    PaginatedRequestParams,
    TextContent,
    Tool,
)


async def handle_list_tools(
    ctx: ServerRequestContext,
    params: PaginatedRequestParams | None,
) -> ListToolsResult:
    return ListToolsResult(tools=[
        Tool(
            name="my_tool",
            description="A tool",
            input_schema={  # v2: snake_case
                "type": "object",
                "properties": {"x": {"type": "integer"}},
                "required": ["x"],
            },
        ),
    ])


async def handle_call_tool(
    ctx: ServerRequestContext,
    params: CallToolRequestParams,
) -> CallToolResult:
    args = params.arguments or {}  # params.arguments can be None in v2
    if params.name != "my_tool":
        return CallToolResult(
            content=[TextContent(type="text", text=f"Unknown tool: {params.name}")],
            is_error=True,  # v2 snake_case
        )
    x = args.get("x", 0)
    return CallToolResult(
        content=[TextContent(type="text", text=str(x * 2))],
        is_error=False,
    )


server = Server(
    "my-server",
    on_list_tools=handle_list_tools,
    on_call_tool=handle_call_tool,
)
```

## v2 handler reference

All handlers: `(ctx: ServerRequestContext, params) -> result`.

| Constructor kwarg | `params` type | Return type |
|---|---|---|
| `on_list_tools` | `PaginatedRequestParams \| None` | `ListToolsResult` |
| `on_call_tool` | `CallToolRequestParams` | `CallToolResult` |
| `on_list_resources` | `PaginatedRequestParams \| None` | `ListResourcesResult` |
| `on_list_resource_templates` | `PaginatedRequestParams \| None` | `ListResourceTemplatesResult` |
| `on_read_resource` | `ReadResourceRequestParams` | `ReadResourceResult` |
| `on_subscribe_resource` | `SubscribeRequestParams` | `EmptyResult` |
| `on_unsubscribe_resource` | `UnsubscribeRequestParams` | `EmptyResult` |
| `on_list_prompts` | `PaginatedRequestParams \| None` | `ListPromptsResult` |
| `on_get_prompt` | `GetPromptRequestParams` | `GetPromptResult` |
| `on_completion` | `CompleteRequestParams` | `CompleteResult` |
| `on_set_logging_level` | `SetLevelRequestParams` | `EmptyResult` |
| `on_ping` | `RequestParams \| None` | `EmptyResult` |
| `on_progress` (notification) | `ProgressNotificationParams` | `None` |
| `on_roots_list_changed` | `NotificationParams \| None` | `None` |

All params and return types import from `mcp.types`.

## Return types: no auto-wrapping in v2

v2 requires fully constructed result types. No automatic wrapping.

### Text resource

```python
from mcp.types import ReadResourceResult, TextResourceContents

async def handle_read(
    ctx: ServerRequestContext,
    params: ReadResourceRequestParams,
) -> ReadResourceResult:
    return ReadResourceResult(contents=[
        TextResourceContents(
            uri=str(params.uri),  # v2: uri is str, not AnyUrl
            text="file contents here",
            mime_type="text/plain",
        )
    ])
```

### Binary resource (must base64-encode yourself)

```python
import base64
from mcp.types import BlobResourceContents, ReadResourceResult

async def handle_read_binary(
    ctx: ServerRequestContext,
    params: ReadResourceRequestParams,
) -> ReadResourceResult:
    image_data = b"\x89PNG..."  # your binary data
    return ReadResourceResult(contents=[
        BlobResourceContents(
            uri=str(params.uri),
            blob=base64.b64encode(image_data).decode("utf-8"),
            mime_type="image/png",
        )
    ])
```

### Structured output (v2)

```python
import json
from mcp.types import CallToolResult, TextContent

async def handle_call_tool(
    ctx: ServerRequestContext,
    params: CallToolRequestParams,
) -> CallToolResult:
    data = {"temperature": 22.5, "city": "London"}
    return CallToolResult(
        content=[TextContent(type="text", text=json.dumps(data, indent=2))],
        structured_content=data,  # v2 snake_case
    )
```

### Low-level server with outputSchema

```python
@server.list_tools()
async def list_tools() -> list[types.Tool]:
    return [
        types.Tool(
            name="get_weather",
            description="Get current weather",
            inputSchema={
                "type": "object",
                "properties": {"city": {"type": "string"}},
                "required": ["city"],
            },
            outputSchema={
                "type": "object",
                "properties": {
                    "temperature": {"type": "number"},
                    "condition": {"type": "string"},
                },
                "required": ["temperature", "condition"],
            },
        )
    ]


@server.call_tool()
async def call_tool(name: str, arguments: dict) -> dict:
    """Return a dict; low-level server validates against outputSchema and
    serializes to TextContent for backwards-compatible clients."""
    city = arguments["city"]
    return {"temperature": 22.5, "condition": "sunny"}
```

## ServerRequestContext (v2)

Available in all handlers as `ctx`:
- `ctx.session` — the active `ServerSession`
- `ctx.lifespan_context` — typed lifespan state
- `ctx.request_id` — unique request ID (None in notification handlers)
- `ctx.meta` — `RequestParamsMeta` TypedDict: `ctx.meta.get("progress_token")`

In v1, `ctx.meta` was a Pydantic model with attribute access
(`ctx.meta.progress_token`). In v2, it's a TypedDict — use `.get()`.

## Streamable HTTP from the lowlevel server (v2)

`streamable_http_app()` is now available directly on the lowlevel `Server`:

```python
from mcp.server import Server, ServerRequestContext
from mcp.types import ListToolsResult, PaginatedRequestParams

async def handle_list_tools(ctx, params) -> ListToolsResult:
    return ListToolsResult(tools=[])

server = Server("my-server", on_list_tools=handle_list_tools)

app = server.streamable_http_app(
    streamable_http_path="/mcp",
    json_response=False,
    stateless_http=False,
)
# server.session_manager available after calling streamable_http_app()
```

## Registering handlers not exposed by FastMCP/MCPServer (workaround)

Handlers like `subscribe_resource` and `set_logging_level` have no public
FastMCP/MCPServer API. Use `_add_request_handler` (private API):

```python
from mcp.server import ServerRequestContext
from mcp.types import EmptyResult, SetLevelRequestParams, SubscribeRequestParams


async def handle_set_level(
    ctx: ServerRequestContext,
    params: SetLevelRequestParams,
) -> EmptyResult:
    # Store the log level for filtering
    return EmptyResult()


async def handle_subscribe(
    ctx: ServerRequestContext,
    params: SubscribeRequestParams,
) -> EmptyResult:
    # Register subscription for params.uri
    return EmptyResult()


# For FastMCP/MCPServer (v2):
mcp._lowlevel_server._add_request_handler("logging/setLevel", handle_set_level)
mcp._lowlevel_server._add_request_handler("resources/subscribe", handle_subscribe)
```

This is private and may change. A public API is planned for future versions.

## Notification handlers (v2)

```python
from mcp.server import Server, ServerRequestContext
from mcp.types import ProgressNotificationParams


async def handle_progress(
    ctx: ServerRequestContext,
    params: ProgressNotificationParams,
) -> None:
    print(f"Progress: {params.progress}/{params.total}")


server = Server("my-server", on_progress=handle_progress)
```

## JSON-RPC message validation (v2)

Union message types are no longer `RootModel` subclasses. Use provided
`TypeAdapter` instances:

```python
from mcp.types import client_request_adapter, server_notification_adapter

request = client_request_adapter.validate_python(raw_data)
# No .root access needed — request is the actual type

notification = server_notification_adapter.validate_python(data)
```

Available adapters from `mcp.types`:
`client_request_adapter`, `server_request_adapter`,
`client_notification_adapter`, `server_notification_adapter`,
`client_result_adapter`, `server_result_adapter`, `jsonrpc_message_adapter`.

Sending notifications no longer needs wrapper types:

```python
# v1
await session.send_notification(ClientNotification(InitializedNotification()))

# v2
await session.send_notification(InitializedNotification())
```

## When to use lowlevel vs FastMCP

| Situation | Use |
|-----------|-----|
| New server, standard tool/resource/prompt model | FastMCP |
| Need full control of result types and response structure | Lowlevel |
| Custom protocol extensions or middleware | Lowlevel |
| subscribe_resource / logging handlers not in FastMCP | Lowlevel workaround or lowlevel `Server` |
| Testing via in-process transport | Either — see `testing.md` |
| Pagination with custom cursor format | Lowlevel (full control over result types) |

## Caution: uv mcp tools don't support lowlevel Server

```bash
# Works only with FastMCP:
uv run mcp dev server.py
uv run mcp run server.py

# Lowlevel servers must be run directly:
python server.py
uv run server.py
```
