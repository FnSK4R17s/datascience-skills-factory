# Client Concepts

Sources: `docs/mcpio__docs__learn__client-concepts.md`,
`docs/mcpio__docs__develop__build-client.md`,
`docs/mcpio__specification__2025-11-25__client__sampling.md`,
`docs/mcpio__specification__2025-11-25__client__roots.md`,
`docs/mcpio__specification__2025-11-25__client__elicitation.md`,
`docs/migration.md`

## Host vs client

The **host** is the application users interact with (Claude.ai, an IDE). The
**client** is the protocol-level component: one client per server connection.
The host manages multiple clients and the overall user experience.

## Sessions

A session covers one connected client-server pair. The Python SDK uses async
context managers to manage session lifecycle:

```python
from mcp import ClientSession, StdioServerParameters
from mcp.client.stdio import stdio_client

server_params = StdioServerParameters(command="python", args=["server.py"])

async with stdio_client(server_params) as (read, write):
    async with ClientSession(read, write) as session:
        await session.initialize()
        tools = await session.list_tools()
        result = await session.call_tool("my_tool", {"arg": "value"})
```

`async with` is required — skipping it leaks connections and deadlocks tests.

### High-level `Client` (v2 / testing)

v2 introduces `mcp.client.Client`, which accepts a server instance directly
(no transport setup needed):

```python
from mcp.client import Client

async with Client(server) as client:
    result = await client.call_tool("my_tool", {"x": 1})
```

This is the recommended pattern for in-process testing (see `testing.md`).

## Discovery

After `initialize()`, the client can discover what the server offers:

```python
tools = await session.list_tools()           # list_tools().tools
resources = await session.list_resources()   # list_resources().resources
templates = await session.list_resource_templates()
prompts = await session.list_prompts()
```

In v2, the cursor-based pagination parameter changed:

```python
# v2 pagination (use PaginatedRequestParams)
from mcp.types import PaginatedRequestParams
tools = await session.list_tools(params=PaginatedRequestParams(cursor="token"))
```

Server capabilities from the `initialize` result:

```python
# v1
caps = session.get_server_capabilities()

# v2
result = session.initialize_result
caps = result.capabilities
server_info = result.server_info
```

## Calling tools

```python
result = await session.call_tool("tool_name", {"param": "value"})
# result.content — list of content blocks (TextContent, etc.)
# result.is_error — bool (v2 snake_case; v1 uses isError)
```

Check `result.is_error` before using the content.

## Reading resources

```python
resource = await session.read_resource("file:///path/to/file")
# resource.contents — list of TextResourceContents or BlobResourceContents
```

In v2, the `uri` parameter accepts plain strings (not `AnyUrl`).

## Invoking prompts

```python
prompt = await session.get_prompt("prompt_name", {"arg": "value"})
# prompt.messages — list of PromptMessage
```

## Sampling (client-side feature)

Sampling allows a **server** to request LLM completions through the client.
The client controls user approval and model access. This is a server-initiated
call — the client must declare `sampling` capability and provide a callback.

Flow: server sends `sampling/createMessage` → client shows user the request
for optional approval → client calls the LLM → client optionally shows the
response for approval → client returns the result to the server.

Client must declare `sampling` in its capability list during `initialize`.

## Elicitation (client-side feature)

Servers can request structured user input mid-operation. The client presents
UI and validates the response against the schema the server provides. The
client must declare `elicitation` capability.

Privacy rule: elicitation must never request passwords or API keys. Clients
should warn about suspicious requests and let users review data before sending.

## Roots

Roots let clients tell servers which filesystem directories are in scope.
They are advisory, not a security boundary — servers should respect them
for well-behaved operations, but OS-level permissions enforce actual access.

Roots use `file://` URIs only. The list can change dynamically; servers
receive `roots/list_changed` notifications.

```python
# Roots are passed as client capabilities during initialization
# Application code sets them; exact API depends on the client implementation
```

## Error handling

Wrap all tool calls and resource reads:

```python
from mcp.shared.exceptions import MCPError  # v2; v1 uses McpError

try:
    result = await session.call_tool("my_tool", args)
except MCPError as e:
    print(f"Protocol error: {e.message}")
```

Common errors: `FileNotFoundError` (server path), `Connection refused`
(server not running), `Tool execution failed` (missing env vars on server).

## v1 → v2 client API changes

Key renames that cause silent failures at runtime:

| v1 | v2 |
|----|----|
| `result.isError` | `result.is_error` |
| `tools.nextCursor` | `tools.next_cursor` |
| `tool.inputSchema` | `tool.input_schema` |
| `session.list_tools(cursor=...)` | `session.list_tools(params=PaginatedRequestParams(cursor=...))` |
| `session.get_server_capabilities()` | `session.initialize_result.capabilities` |
| `McpError` | `MCPError` (from `mcp.shared.exceptions` or top-level `mcp`) |
| `McpError(ErrorData(...))` | `MCPError(code, message)` |

Old camelCase names still work as constructor kwargs (Pydantic `populate_by_name=True`),
but attribute access must use snake_case. Source: `docs/migration.md`.
