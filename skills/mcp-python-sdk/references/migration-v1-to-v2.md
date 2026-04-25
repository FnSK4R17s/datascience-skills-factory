# Migration Guide: v1 to v2

Sources: `docs/migration.md`, `docs/mcpio__specification__2025-11-25__changelog.md`

## Overview

v2 of the Python MCP SDK (pre-alpha on `main`) introduces breaking changes to
improve API consistency and align with the spec. v1.x remains the current
stable release. **Pick one and commit — do not mix patterns.**

## Quick reference: most impactful changes

| Category | Change | Impact |
|----------|--------|--------|
| Class rename | `FastMCP` → `MCPServer`, `from mcp.server.fastmcp` → `from mcp.server.mcpserver` | All import statements |
| Field names | `isError` → `is_error`, `inputSchema` → `input_schema`, `nextCursor` → `next_cursor` | All attribute access |
| Context method removed | `mcp.get_context()` → `ctx: Context` parameter injection | All tools using context |
| Transport params | Constructor params `host`, `port`, `json_response`, etc. → moved to `run()` | All HTTP servers |
| streamable HTTP client | `streamablehttp_client` (3-tuple) → `streamable_http_client` (2-tuple) | All HTTP clients |
| Testing | `create_connected_server_and_client_session` → `Client(server)` | All tests |
| Error class | `McpError(ErrorData(...))` → `MCPError(code, message)` | Error handling |
| Pagination | `list_tools(cursor=...)` → `list_tools(params=PaginatedRequestParams(cursor=...))` | Pagination code |
| Lowlevel handlers | Decorator methods → constructor `on_*` kwargs | All lowlevel servers |
| URI type | `AnyUrl` → `str` for resource URIs | Resource read calls |

## Breaking change details

### FastMCP renamed to MCPServer

```python
# v1
from mcp.server.fastmcp import FastMCP
mcp = FastMCP("Demo")

# v2
from mcp.server.mcpserver import MCPServer, Context
mcp = MCPServer("Demo")
```

All submodules under `mcp.server.fastmcp.*` move to `mcp.server.mcpserver.*`
with the same structure. Common renames:

```python
# v1 imports                         # v2 imports
from mcp.server.fastmcp import FastMCP, Context
from mcp.server.fastmcp.prompts import base
                                     from mcp.server.mcpserver import MCPServer, Context
                                     from mcp.server.mcpserver.prompts.base import UserMessage, AssistantMessage

# Image, Audio
from mcp.server.fastmcp import Image  from mcp.server.mcpserver import Image, Audio

# Exceptions
from mcp.server.fastmcp.exceptions import ToolError, ResourceError
                                     from mcp.server.mcpserver.exceptions import ToolError, ResourceError
```

### Transport params move out of constructor

v1 accepted `host`, `port`, `json_response`, `stateless_http`, etc. in the
`FastMCP` constructor. In v2 they move to `run()`, `sse_app()`, and
`streamable_http_app()`.

```python
# v1 — transport params in constructor
from mcp.server.fastmcp import FastMCP

mcp = FastMCP("Demo", json_response=True, stateless_http=True)
mcp.run(transport="streamable-http")

mcp = FastMCP("Server", host="0.0.0.0", port=9000, sse_path="/events")
mcp.run(transport="sse")

# v2 — transport params in run()
from mcp.server.mcpserver import MCPServer

mcp = MCPServer("Demo")
mcp.run(transport="streamable-http", json_response=True, stateless_http=True)

mcp = MCPServer("Server")
mcp.run(transport="sse", host="0.0.0.0", port=9000, sse_path="/events")
```

For mounted apps:
```python
# v1
mcp = FastMCP("App", json_response=True)
app = Starlette(routes=[Mount("/", app=mcp.streamable_http_app())])

# v2
mcp = MCPServer("App")
app = Starlette(routes=[Mount("/", app=mcp.streamable_http_app(json_response=True))])
```

`mount_path` constructor param is also removed in v2. It was redundant because
ASGI `root_path` mechanism (set by Starlette's `Mount`) already handles it.

### `get_context()` removed — use parameter injection

```python
# v1
@mcp.tool()
async def my_tool(x: int) -> str:
    ctx = mcp.get_context()  # REMOVED in v2
    await ctx.info("Processing...")
    return str(x)

# v2 — context injected as parameter
from mcp.server.mcpserver import Context

@mcp.tool()
async def my_tool(x: int, ctx: Context) -> str:
    await ctx.info("Processing...")
    return str(x)
```

### Field names: camelCase → snake_case

All Pydantic model fields use snake_case for Python attribute access. JSON
wire format is unchanged (still camelCase via aliases). `populate_by_name=True`
means constructor kwargs still accept camelCase, but attribute access must use
snake_case.

| v1 (camelCase) | v2 (snake_case) |
|----------------|-----------------|
| `inputSchema` | `input_schema` |
| `outputSchema` | `output_schema` |
| `isError` | `is_error` |
| `nextCursor` | `next_cursor` |
| `mimeType` | `mime_type` |
| `structuredContent` | `structured_content` |
| `serverInfo` | `server_info` |
| `protocolVersion` | `protocol_version` |
| `uriTemplate` | `uri_template` |
| `listChanged` | `list_changed` |
| `progressToken` | `progress_token` |

```python
# v1
result = await session.call_tool("my_tool", {"x": 1})
if result.isError:
    ...
tools = await session.list_tools()
cursor = tools.nextCursor
schema = tools.tools[0].inputSchema

# v2
result = await session.call_tool("my_tool", {"x": 1})
if result.is_error:
    ...
tools = await session.list_tools()
cursor = tools.next_cursor
schema = tools.tools[0].input_schema
```

### streamablehttp_client removed

```python
# v1
from mcp.client.streamable_http import streamablehttp_client

async with streamablehttp_client(
    url="http://localhost:8000/mcp",
    headers={"Authorization": "Bearer token"},
    timeout=30,
    sse_read_timeout=300,
    auth=my_auth,
) as (read_stream, write_stream, get_session_id):
    session_id = get_session_id()
    ...

# v2 — configure via httpx.AsyncClient, 2-tuple return
import httpx
from mcp.client.streamable_http import streamable_http_client

http_client = httpx.AsyncClient(
    headers={"Authorization": "Bearer token"},
    timeout=httpx.Timeout(30, read=300),
    auth=my_auth,
    follow_redirects=True,  # v1 set this internally; must be explicit in v2
)

async with http_client:
    async with streamable_http_client(
        url="http://localhost:8000/mcp",
        http_client=http_client,
    ) as (read_stream, write_stream):
        ...
```

To capture session ID in v2 (via httpx event hooks):
```python
captured_ids: list[str] = []

async def capture(response: httpx.Response) -> None:
    sid = response.headers.get("mcp-session-id")
    if sid:
        captured_ids.append(sid)

http_client = httpx.AsyncClient(event_hooks={"response": [capture]}, follow_redirects=True)
```

### Removed type aliases

| Removed | Replacement |
|---------|-------------|
| `Content` | `ContentBlock` |
| `ResourceReference` | `ResourceTemplateReference` |
| `Cursor` | `str` directly |
| `McpError` | `MCPError` (also from top-level `mcp`) |

### MCPError constructor changed

```python
# v1
from mcp.shared.exceptions import McpError
from mcp.types import ErrorData, INVALID_REQUEST

raise McpError(ErrorData(code=INVALID_REQUEST, message="bad input"))

# Catching v1
try:
    ...
except McpError as e:
    print(f"Error: {e.error.message}")

# v2
from mcp.shared.exceptions import MCPError
from mcp.types import INVALID_REQUEST

raise MCPError(INVALID_REQUEST, "bad input")
# or from existing ErrorData:
raise MCPError.from_error_data(error_data)

# Catching v2
try:
    ...
except MCPError as e:
    print(f"Error: {e.message}")  # direct attribute, not .error.message
```

`MCPError` is also exported from the top-level `mcp` package: `from mcp import MCPError`.

### Pagination API changed

```python
# v1 — cursor as positional/keyword parameter
result = await session.list_resources(cursor="next_page_token")
result = await session.list_tools(cursor="next_page_token")

# v2 — params object
from mcp.types import PaginatedRequestParams

result = await session.list_resources(params=PaginatedRequestParams(cursor="next_page_token"))
result = await session.list_tools(params=PaginatedRequestParams(cursor="next_page_token"))
```

Also: `ClientSessionGroup.call_tool()` `args` parameter → `arguments`:
```python
# v1
result = await session_group.call_tool("my_tool", args={"key": "value"})
# v2
result = await session_group.call_tool("my_tool", arguments={"key": "value"})
```

### ClientSession.get_server_capabilities() replaced

```python
# v1
capabilities = session.get_server_capabilities()

# v2
result = session.initialize_result  # stores full InitializeResult
if result is not None:
    capabilities = result.capabilities
    server_info = result.server_info
    instructions = result.instructions
    version = result.protocol_version
```

`Client.initialize_result` (high-level) is non-nullable — guaranteed inside
context manager. Replaces `Client.server_capabilities` from v1.

### Resource URI type: AnyUrl → str

```python
# v1
from pydantic import AnyUrl
resource = Resource(name="test", uri=AnyUrl("users/me"))  # fails validation
await client.read_resource(AnyUrl("test://resource"))

# v2 — plain strings
resource = Resource(name="test", uri="users/me")  # works
resource = Resource(name="test", uri="custom://scheme")  # works
await client.read_resource("test://resource")
# If you have an AnyUrl from elsewhere: str(my_any_url)
```

Affected types: `Resource.uri`, `ReadResourceRequestParams.uri`,
`TextResourceContents.uri`, `BlobResourceContents.uri`,
`SubscribeRequestParams.uri`, `UnsubscribeRequestParams.uri`.

### In-process testing helper removed

```python
# v1
from mcp.shared.memory import create_connected_server_and_client_session

async with create_connected_server_and_client_session(server) as session:
    result = await session.call_tool("my_tool", {"x": 1})

# v2
from mcp.client import Client

async with Client(server) as client:
    result = await client.call_tool("my_tool", {"x": 1})
```

`create_client_server_memory_streams` is still available in v2 for transport-
level testing with direct `ClientSession` access.

### Lowlevel Server: decorator handlers → constructor on_* params

```python
# v1 — decorator-based handlers
from mcp.server.lowlevel.server import Server

server = Server("my-server")

@server.list_tools()
async def handle_list_tools():
    return [types.Tool(name="my_tool", description="A tool", inputSchema={})]

@server.call_tool()
async def handle_call_tool(name: str, arguments: dict):
    return [types.TextContent(type="text", text=f"Called {name}")]

# v2 — constructor on_* params with (ctx, params) signature
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
        Tool(name="my_tool", description="A tool", input_schema={})
    ])

async def handle_call_tool(
    ctx: ServerRequestContext,
    params: CallToolRequestParams,
) -> CallToolResult:
    args = params.arguments or {}  # can be None in v2
    return CallToolResult(
        content=[TextContent(type="text", text=f"Called {params.name}")],
        is_error=False,
    )

server = Server("my-server", on_list_tools=handle_list_tools, on_call_tool=handle_call_tool)
```

v2 removes all return value auto-wrapping from the lowlevel server. Handlers
must return the complete result type. See `references/low-level-server.md` for
the full handler reference table and patterns.

### Lowlevel Server: request_context property removed

```python
# v1 — ambient context via property
@server.call_tool()
async def handle_call_tool(name: str, arguments: dict):
    ctx = server.request_context  # or request_ctx.get()
    await ctx.session.send_log_message(level="info", data="Processing...")
    return [types.TextContent(type="text", text="Done")]

# v2 — context passed as first arg to handler
async def handle_call_tool(ctx: ServerRequestContext, params: CallToolRequestParams) -> CallToolResult:
    await ctx.session.send_log_message(level="info", data="Processing...")
    return CallToolResult(
        content=[TextContent(type="text", text="Done")],
        is_error=False,
    )
```

### Logging API: message → data

```python
# v1
await ctx.info("Connection failed", extra={"host": "localhost"})
await ctx.log(level="info", message="hello")

# v2 — data: Any instead of message: str; extra removed
await ctx.info({"message": "Connection failed", "host": "localhost"})
await ctx.log(level="info", data="hello")
await ctx.log(level="notice", data={"structured": "data"})
```

Bare string positional calls (`await ctx.info("hello")`) are unaffected.

All 8 RFC-5424 levels now supported via `ctx.log()`: `debug`, `info`, `notice`,
`warning`, `error`, `critical`, `alert`, `emergency`.

### Context type parameter simplified

```python
# v1
from mcp.server.session import ServerSession
async def my_tool(ctx: Context[ServerSession, None]) -> str: ...

# v2 — ServerSessionT parameter removed
async def my_tool(ctx: Context) -> str: ...
# or with explicit lifespan type:
async def my_tool(ctx: Context[MyLifespanState]) -> str: ...
```

### Union types: RootModel → TypeAdapter

```python
# v1
from mcp.types import ClientRequest, ServerNotification

request = ClientRequest.model_validate(data)
actual = request.root  # unwrap RootModel

notification = ServerNotification.model_validate(data)
actual_notification = notification.root

# v2 — TypeAdapter
from mcp.types import client_request_adapter, server_notification_adapter

request = client_request_adapter.validate_python(data)
# No .root access needed

notification = server_notification_adapter.validate_python(data)
```

Sending without wrapper:
```python
# v1
await session.send_notification(ClientNotification(InitializedNotification()))
await session.send_request(ClientRequest(PingRequest()), EmptyResult)

# v2
await session.send_notification(InitializedNotification())
await session.send_request(PingRequest(), EmptyResult)
```

### ProgressContext removed

```python
# v1
from mcp.shared.progress import progress

with progress(ctx, total=100) as p:
    await p.progress(25)

# v2 — use ctx.report_progress() or session.send_progress_notification()
@mcp.tool()
async def my_tool(x: int, ctx: Context) -> str:
    await ctx.report_progress(25, 100)
    return "done"
```

### Experimental tasks: decorator handlers removed

```python
# v1
server.experimental.enable_tasks()

@server.experimental.get_task()
async def custom_get_task(request: GetTaskRequest) -> GetTaskResult:
    ...

# v2 — override via on_* kwargs
async def custom_get_task(ctx: ServerRequestContext, params: GetTaskRequestParams) -> GetTaskResult:
    ...

server.experimental.enable_tasks(on_get_task=custom_get_task)
```

## Spec changelog (2025-11-25)

Key spec additions in the version v2 targets:

- Icons on tools, resources, prompts, and server implementation
- URL-mode elicitation (redirect users to external URLs)
- Tool calling in sampling (`tools` and `toolChoice` params)
- Tasks (experimental) for deferred result retrieval
- Incremental scope consent via `WWW-Authenticate`
- OAuth Client ID Metadata Documents for client registration
- OIDC Discovery support for authorization server discovery

## New features in v2

### `streamable_http_app()` on lowlevel Server

```python
from mcp.server import Server, ServerRequestContext
from mcp.types import ListToolsResult, PaginatedRequestParams

async def handle_list_tools(ctx, params) -> ListToolsResult:
    return ListToolsResult(tools=[...])

server = Server("my-server", on_list_tools=handle_list_tools)

app = server.streamable_http_app(
    streamable_http_path="/mcp",
    json_response=False,
    stateless_http=False,
)
# server.session_manager available after this call
```

### Extra fields no longer allowed on top-level types

```python
# Now raises ValidationError
params = CallToolRequestParams(
    name="my_tool",
    arguments={},
    unknown_field="value",  # ValidationError: extra fields not permitted
)

# Extra fields still allowed in _meta
params = CallToolRequestParams(
    name="my_tool",
    arguments={},
    _meta={"my_custom_key": "value"},  # OK
)
```

### `subscribe` capability now correctly reported

Previously, the lowlevel `Server` hardcoded `subscribe=False` even when a
`subscribe_resource()` handler was registered. In v2, it dynamically reports
`True` when `on_subscribe_resource` handler is provided.
