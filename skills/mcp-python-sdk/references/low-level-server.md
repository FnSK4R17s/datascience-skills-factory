# Low-Level Server

Sources: `docs/migration.md` (v2 handler API),
`docs/README.md` (v1 section "Low-Level Server"),
`docs/mcpio__specification__2025-11-25__server__index.md`

## What it is

The lowlevel `Server` class (`mcp.server.Server` in v2; previously
`mcp.server.lowlevel.server.Server`) is the raw protocol layer. It provides
no decorator magic, no schema inference, no automatic wrapping — you construct
and return full MCP result types yourself.

Use it when FastMCP's convenience layer is in the way. Most servers should
start with `FastMCP` / `MCPServer` and drop to lowlevel only for specific
handlers.

## v1 pattern (decorator-based)

In v1, handlers were registered via decorator methods:

```python
from mcp.server.lowlevel.server import Server
import mcp.types as types

server = Server("my-server")

@server.list_tools()
async def handle_list_tools():
    return [types.Tool(name="my_tool", description="A tool", inputSchema={})]

@server.call_tool()
async def handle_call_tool(name: str, arguments: dict):
    return [types.TextContent(type="text", text=f"Called {name}")]
```

v1 decorators auto-wrapped return values: bare lists became result types,
dicts became `structured_content + TextContent`, etc.

## v2 pattern (constructor `on_*` params)

In v2, all handlers are registered as `on_*` keyword arguments to the
constructor. Handlers receive `(ctx: ServerRequestContext, params: ...)` and
must return fully constructed result types:

```python
from mcp.server import Server, ServerRequestContext
from mcp.types import (
    CallToolRequestParams, CallToolResult,
    ListToolsResult, PaginatedRequestParams,
    TextContent, Tool,
)

async def handle_list_tools(
    ctx: ServerRequestContext,
    params: PaginatedRequestParams | None,
) -> ListToolsResult:
    return ListToolsResult(tools=[
        Tool(name="my_tool", description="A tool", input_schema={}),
    ])

async def handle_call_tool(
    ctx: ServerRequestContext,
    params: CallToolRequestParams,
) -> CallToolResult:
    return CallToolResult(
        content=[TextContent(type="text", text=f"Called {params.name}")],
        is_error=False,
    )

server = Server(
    "my-server",
    on_list_tools=handle_list_tools,
    on_call_tool=handle_call_tool,
)
```

Note: `params.arguments` can be `None` in v2 — use `params.arguments or {}`.

## Handler reference (v2)

All handlers: `(ctx: ServerRequestContext, params) -> result`.

| Constructor kwarg | `params` type | Return type |
|---|---|---|
| `on_list_tools` | `PaginatedRequestParams \| None` | `ListToolsResult` |
| `on_call_tool` | `CallToolRequestParams` | `CallToolResult` |
| `on_list_resources` | `PaginatedRequestParams \| None` | `ListResourcesResult` |
| `on_list_resource_templates` | `PaginatedRequestParams \| None` | `ListResourceTemplatesResult` |
| `on_read_resource` | `ReadResourceRequestParams` | `ReadResourceResult` |
| `on_subscribe_resource` | `SubscribeRequestParams` | `EmptyResult` |
| `on_list_prompts` | `PaginatedRequestParams \| None` | `ListPromptsResult` |
| `on_get_prompt` | `GetPromptRequestParams` | `GetPromptResult` |
| `on_completion` | `CompleteRequestParams` | `CompleteResult` |
| `on_set_logging_level` | `SetLevelRequestParams` | `EmptyResult` |
| `on_ping` | `RequestParams \| None` | `EmptyResult` |
| `on_progress` (notification) | `ProgressNotificationParams` | `None` |

All params and return types are importable from `mcp.types`.

## Return types: no auto-wrapping in v2

v2 removes all magic wrapping. Build the complete result type yourself:

```python
# Text content in a read_resource handler
from mcp.types import ReadResourceResult, TextResourceContents

async def handle_read(ctx, params) -> ReadResourceResult:
    return ReadResourceResult(contents=[
        TextResourceContents(
            uri=str(params.uri),
            text="file contents",
            mime_type="text/plain",
        )
    ])

# Binary content — you must base64-encode yourself
import base64
from mcp.types import BlobResourceContents

async def handle_read_binary(ctx, params) -> ReadResourceResult:
    return ReadResourceResult(contents=[
        BlobResourceContents(
            uri=str(params.uri),
            blob=base64.b64encode(data).decode("utf-8"),
            mime_type="image/png",
        )
    ])
```

## ServerRequestContext

Available in all handlers as `ctx`:
- `ctx.session` — the active `ServerSession`
- `ctx.lifespan_context` — typed lifespan state (server-side)
- `ctx.request_id` — unique request ID (None in notification handlers)
- `ctx.meta` — `RequestParamsMeta` TypedDict with `progress_token`, etc.

In v2, `ctx.meta` is a TypedDict — access via `ctx.meta.get("progress_token")`
not attribute access.

## Streamable HTTP from the lowlevel server (v2)

v2 adds `streamable_http_app()` directly on the lowlevel `Server`:

```python
app = server.streamable_http_app(
    streamable_http_path="/mcp",
    json_response=False,
    stateless_http=False,
)
# server.session_manager available after calling streamable_http_app()
```

## Registering handlers not exposed by MCPServer (workaround)

Handlers like `subscribe_resource` and `set_logging_level` have no public
FastMCP/MCPServer API. Use `_add_request_handler` (v2 private API):

```python
from mcp.server import ServerRequestContext
from mcp.types import EmptyResult, SetLevelRequestParams

async def handle_set_level(ctx: ServerRequestContext, params: SetLevelRequestParams) -> EmptyResult:
    return EmptyResult()

mcp._lowlevel_server._add_request_handler("logging/setLevel", handle_set_level)
```

This is private and may change. A public API is planned.

## JSON-RPC message validation (v2)

Union message types are no longer `RootModel` subclasses. Validate with
provided `TypeAdapter` instances:

```python
from mcp.types import client_request_adapter

request = client_request_adapter.validate_python(raw_data)
# No .root access needed
```

Sending notifications/requests — no longer need wrapper types:

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
| Subscribe/logging handlers not in FastMCP | Lowlevel workaround or lowlevel `Server` |
| Testing via in-process transport | Either — see `testing.md` |
