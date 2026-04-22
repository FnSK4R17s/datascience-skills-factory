# Low-Level Server API

The `mcp.server.Server` class gives direct access to the protocol layer.
Use it when FastMCP's decorator model is too constraining — you need dynamic
handler registration, custom capability negotiation, or middleware.

## Basic structure

```python
from mcp.server import Server
from mcp.server.models import InitializationOptions
from mcp import types
import mcp.server.stdio as stdio_transport

app = Server("my-server")

@app.list_tools()
async def handle_list_tools() -> list[types.Tool]:
    return [
        types.Tool(
            name="my_tool",
            description="Does something",
            inputSchema={
                "type": "object",
                "properties": {"param": {"type": "string"}},
                "required": ["param"],
            },
        )
    ]

@app.call_tool()
async def handle_call_tool(
    name: str, arguments: dict | None
) -> list[types.TextContent | types.ImageContent | types.EmbeddedResource]:
    if name == "my_tool":
        param = (arguments or {}).get("param", "")
        return [types.TextContent(type="text", text=f"result: {param}")]
    raise ValueError(f"Unknown tool: {name}")

async def run():
    async with stdio_transport.stdio_server() as (read, write):
        await app.run(
            read,
            write,
            InitializationOptions(
                server_name="my-server",
                server_version="0.1.0",
                capabilities=app.get_capabilities(
                    notification_options=types.NotificationOptions(),
                    experimental_capabilities={},
                ),
            ),
        )

if __name__ == "__main__":
    import asyncio
    asyncio.run(run())
```

## Handler decorators

The `Server` class exposes decorators for each protocol method:

| Decorator | Protocol method |
|-----------|----------------|
| `@app.list_tools()` | `tools/list` |
| `@app.call_tool()` | `tools/call` |
| `@app.list_resources()` | `resources/list` |
| `@app.list_resource_templates()` | `resources/templates/list` |
| `@app.read_resource()` | `resources/read` |
| `@app.subscribe_resource()` | `resources/subscribe` |
| `@app.unsubscribe_resource()` | `resources/unsubscribe` |
| `@app.list_prompts()` | `prompts/list` |
| `@app.get_prompt()` | `prompts/get` |
| `@app.set_logging_level()` | `logging/setLevel` |
| `@app.completion()` | `completion/complete` |

Only register handlers for primitives you include in capabilities.

## Capabilities declaration

```python
from mcp.server.models import InitializationOptions
from mcp import types

capabilities = app.get_capabilities(
    notification_options=types.NotificationOptions(
        tools_changed=True,       # server will send tools/list_changed
        resources_changed=True,   # server will send resources/list_changed
        prompts_changed=True,
    ),
    experimental_capabilities={},
)
```

`get_capabilities()` inspects which handler decorators you've registered and
builds the capability map. If you register a `list_tools` handler, tools are
in capabilities. If you don't register one, they aren't — regardless of what
you pass to `InitializationOptions`.

## Sending notifications

Notify the client when state changes without waiting for a request:

```python
from mcp.server import Server

# Inside a handler or background task:
await app.request_context.session.send_resource_updated(
    types.ResourceUpdatedNotification(
        method="notifications/resources/updated",
        params=types.ResourceUpdatedParams(uri="mydata://items/42"),
    )
)
```

Or use the typed helper methods available on the session object.

## Error handling

Raise `McpError` to send a structured error response:

```python
from mcp import McpError, types

@app.call_tool()
async def handle_call_tool(name: str, arguments: dict | None):
    if name not in KNOWN_TOOLS:
        raise McpError(
            error=types.ErrorData(
                code=types.INVALID_PARAMS,
                message=f"Unknown tool: {name}",
            )
        )
```

Unhandled exceptions propagate as `InternalError`. Catch at the handler
boundary — do not let exceptions cross the protocol layer silently.

## Request context

The `RequestContext` is available during any handler call:

```python
@app.call_tool()
async def handle_call_tool(name: str, arguments: dict | None):
    ctx = app.request_context
    client_info = ctx.meta.clientInfo  # name, version
    session = ctx.session              # active ServerSession
    ...
```

## Dynamic tool registration

Unlike FastMCP (which reads registrations at class instantiation), the
low-level server dispatches every `tools/call` to your single `call_tool`
handler. Implement dynamic dispatch inside the handler:

```python
TOOLS: dict[str, callable] = {}

def register_tool(name: str, fn: callable, schema: dict):
    TOOLS[name] = fn
    SCHEMAS[name] = schema

@app.list_tools()
async def list_tools():
    return [
        types.Tool(name=k, inputSchema=v, description="")
        for k, v in SCHEMAS.items()
    ]

@app.call_tool()
async def call_tool(name: str, arguments: dict | None):
    fn = TOOLS.get(name)
    if fn is None:
        raise McpError(error=types.ErrorData(code=types.METHOD_NOT_FOUND, message=name))
    return await fn(**(arguments or {}))
```

## Mixing FastMCP and low-level

Do not mix. FastMCP wraps a low-level `Server` internally; accessing its
`._server` attribute for customization is unsupported and breaks across SDK
versions. If you need low-level control, start from `Server` directly.
