# Migration Guide: v1 to v2

Sources: `docs/migration.md`, `docs/mcpio__specification__2025-11-25__changelog.md`

## Overview

v2 of the Python MCP SDK (pre-alpha on `main`) introduces breaking changes to
improve API consistency and align with the spec. v1.x remains the current stable
release. **Pick one and commit — do not mix patterns.**

## Key Breaking Changes

### FastMCP renamed to MCPServer

```python
# v1
from mcp.server.fastmcp import FastMCP
mcp = FastMCP("Demo")

# v2
from mcp.server.mcpserver import MCPServer, Context
mcp = MCPServer("Demo")
```

All submodules under `mcp.server.fastmcp.*` move to `mcp.server.mcpserver.*`.
Common renames: `Image`, `Audio` from `mcp.server.mcpserver`; `UserMessage`,
`AssistantMessage` from `mcp.server.mcpserver.prompts.base`.

### Transport params move out of constructor

v1 accepted `host`, `port`, `json_response`, `stateless_http`, etc. in the
constructor. In v2 they move to `run()`, `sse_app()`, and `streamable_http_app()`.

```python
# v2
mcp = MCPServer("Demo")
mcp.run(transport="streamable-http", json_response=True, stateless_http=True)
```

### `get_context()` removed

In v2, `MCPServer.get_context()` is gone. Context is now injected as a typed
parameter:

```python
# v2
from mcp.server.mcpserver import Context

@mcp.tool()
async def my_tool(x: int, ctx: Context) -> str:
    await ctx.info("Processing...")
    return str(x)
```

The `Context` type parameter simplified: `Context[ServerSessionT, LifespanContextT]`
→ `Context[LifespanContextT]`. Bare `Context` works for most tools.

### Field names: camelCase → snake_case

All Pydantic model fields use snake_case for Python attribute access. The JSON
wire format is unchanged (still camelCase via aliases).

| v1 (camelCase) | v2 (snake_case) |
|----------------|-----------------|
| `inputSchema` | `input_schema` |
| `outputSchema` | `output_schema` |
| `isError` | `is_error` |
| `nextCursor` | `next_cursor` |
| `mimeType` | `mime_type` |
| `structuredContent` | `structured_content` |
| `serverInfo` | `server_info` |
| `uriTemplate` | `uri_template` |
| `progressToken` | `progress_token` |

`populate_by_name=True` is set, so old camelCase names still work as constructor
kwargs but attribute access must use snake_case.

### streamablehttp_client removed

The deprecated `streamablehttp_client` is gone. Use `streamable_http_client`.
The function now returns a 2-tuple `(read_stream, write_stream)` instead of 3.
To capture the session ID, use httpx event hooks on the response.

Configure headers/timeouts/auth on the `httpx.AsyncClient`, not on the transport:

```python
import httpx
from mcp.client.streamable_http import streamable_http_client

http_client = httpx.AsyncClient(
    headers={"Authorization": "Bearer token"},
    timeout=httpx.Timeout(30, read=300),
    follow_redirects=True,
)
async with http_client:
    async with streamable_http_client(url, http_client=http_client) as (read, write):
        ...
```

### Removed type aliases

| Removed | Replacement |
|---------|-------------|
| `Content` | `ContentBlock` |
| `ResourceReference` | `ResourceTemplateReference` |
| `Cursor` | `str` directly |
| `McpError` | `MCPError` (also exported from top-level `mcp`) |

### MCPError constructor changed

```python
# v1
raise McpError(ErrorData(code=INVALID_REQUEST, message="bad input"))

# v2
from mcp.shared.exceptions import MCPError
raise MCPError(INVALID_REQUEST, "bad input")
# or from existing ErrorData:
raise MCPError.from_error_data(error_data)
```

### Pagination API changed

Remove the `cursor` positional param from list methods:

```python
# v2
from mcp.types import PaginatedRequestParams

result = await session.list_tools(params=PaginatedRequestParams(cursor="token"))
```

### ClientSession API

- `get_server_capabilities()` removed → use `session.initialize_result.capabilities`
- `ClientSessionGroup.call_tool()` `args` param removed → use `arguments`

### Lowlevel Server: constructor-only handlers

The lowlevel `Server` no longer uses decorator methods. Handlers are passed as
`on_*` kwargs to the constructor. Each handler receives `(ctx: ServerRequestContext, params)` and returns the full result type.

```python
# v2
async def handle_list_tools(ctx, params) -> ListToolsResult:
    return ListToolsResult(tools=[...])

server = Server("my-server", on_list_tools=handle_list_tools)
```

All request context is now passed as `ctx` argument — the `server.request_context`
property and `request_ctx` contextvar are removed.

### Resource URI type: AnyUrl → str

URI fields now accept plain strings. Remove `AnyUrl` wrapping:

```python
# v2
resource = Resource(name="test", uri="users/me")  # plain string
await client.read_resource("test://resource")
```

### Union types: RootModel → TypeAdapter

`ClientRequest`, `ServerNotification`, etc. are no longer `RootModel` subclasses.
Use the provided `TypeAdapter` instances:

```python
from mcp.types import client_request_adapter
request = client_request_adapter.validate_python(data)
```

Send without wrapping:
```python
await session.send_notification(InitializedNotification())  # not ClientNotification(...)
```

### Logging API change

`ctx.info()`, `ctx.debug()`, etc. take `data: Any` instead of `message: str`.
`ctx.log()` accepts all 8 RFC-5424 levels.

```python
# v2
await ctx.info({"message": "Connection failed", "host": "localhost"})
await ctx.log(level="notice", data="hello")
```

### in-process testing helper removed

`create_connected_server_and_client_session` is removed. Use `mcp.client.Client`:

```python
from mcp.client import Client

async with Client(server) as client:
    result = await client.call_tool("my_tool", {"x": 1})
```

### Experimental tasks: decorator handlers removed

`@server.experimental.get_task()` etc. are gone. Override defaults via `on_*` kwargs:

```python
server.experimental.enable_tasks(on_get_task=custom_get_task)
```

## Spec changelog (2025-11-25)

Key spec additions in the version the SDK targets:

- Icons on tools, resources, prompts, and implementation
- URL-mode elicitation
- Tool calling in sampling (`tools` and `toolChoice` params)
- Tasks (experimental) for deferred result retrieval
- Incremental scope consent via `WWW-Authenticate`
- OAuth Client ID Metadata Documents for client registration
- OIDC Discovery support for authorization server discovery
