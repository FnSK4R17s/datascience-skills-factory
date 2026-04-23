# Server Concepts

Sources: `docs/README.md`, `docs/mcpio__docs__learn__server-concepts.md`,
`docs/mcpio__specification__2025-11-25__basic__lifecycle.md`,
`docs/mcpio__specification__2025-11-25__server__tools.md`,
`docs/mcpio__specification__2025-11-25__server__resources.md`,
`docs/mcpio__specification__2025-11-25__server__prompts.md`,
`docs/mcpio__specification__2025-11-25__server__utilities__completion.md`,
`docs/mcpio__specification__2025-11-25__server__utilities__logging.md`,
`docs/mcpio__specification__2025-11-25__server__utilities__pagination.md`,
`docs/mcpio__specification__2025-11-25__basic__index.md`

## The three primitives

MCP servers expose exactly three primitive types. Each has a distinct control
model.

| Primitive | Analogy | Who invokes | Side effects allowed |
|-----------|---------|-------------|----------------------|
| **Tools** | POST endpoint | Model (autonomous) | Yes |
| **Resources** | GET endpoint | Application | No (read-only) |
| **Prompts** | Template | User (explicit) | No |

### Tools

Functions the LLM can call. Define inputs via JSON Schema (inferred from type
annotations by FastMCP). The model decides when to call them based on context.

Protocol operations: `tools/list`, `tools/call`.

Tools may require user consent before execution — MCP emphasizes human
oversight. Approval dialogs, permission settings, and activity logs are
common patterns in host applications.

**Structured output** (v1 FastMCP): if the return type annotation is a
Pydantic `BaseModel`, `TypedDict`, dataclass with type hints, or
`dict[str, T]`, FastMCP auto-generates `outputSchema` and validates the
return value. Primitives (`str`, `int`, etc.) and generic containers are
wrapped in `{"result": value}`. Classes without type hints cannot be used for
structured output.

To suppress structured output on a typed return: pass `structured_output=False`
to `@mcp.tool()`.

For full protocol control, return `CallToolResult` directly — it accepts a
`_meta` field that is passed to the client application without being exposed
to the model.

### Resources

Read-only data sources. Clients (not the model) decide which resources to
load into context. Two patterns:

- **Direct resources** — fixed URIs, e.g. `config://settings`.
- **Resource templates** — URI templates with `{param}` placeholders,
  e.g. `file:///{path}`. FastMCP maps template parameters to function
  arguments automatically.

Protocol operations: `resources/list`, `resources/templates/list`,
`resources/read`, `resources/subscribe` (for change notifications).

Each resource declares a MIME type for content handling. Resources support
parameter completion — clients can suggest valid values as users type.

### Prompts

Parameterized instruction templates. User-invoked (slash commands, command
palettes, context menus). Prompts can reference resources and tools to create
comprehensive workflows. They also support parameter completion.

Protocol operations: `prompts/list`, `prompts/get`.

## Capabilities

Capabilities are declared during the `initialize` handshake and cannot be
added retroactively. FastMCP infers capabilities from registered decorators —
if you register a `@mcp.tool()`, the server advertises `tools` capability
automatically.

Key server capabilities:

| Capability | Meaning |
|-----------|---------|
| `tools` | Server exposes callable tools |
| `resources` | Server provides readable resources |
| `prompts` | Server offers prompt templates |
| `logging` | Server emits structured log messages |
| `completions` | Server supports argument autocompletion |

Sub-capabilities: `listChanged` (push notifications when the list changes),
`subscribe` (resources only — notify on specific resource changes).

## Lifecycle

Three mandatory phases:

1. **Initialization** — client sends `initialize` with its protocol version
   and capabilities; server responds with its own; client sends `initialized`
   notification. Neither side may send operation requests until this completes.

2. **Operation** — normal request/response and notification exchange, subject
   to negotiated capabilities.

3. **Shutdown** — client closes the transport (stdin for stdio; HTTP
   connection for HTTP). No protocol-level shutdown message is defined.

**Version negotiation**: client proposes its latest version; server accepts
or counters with its own latest. If the client does not support the server's
version, it should disconnect.

**Error during init**: a version mismatch returns JSON-RPC error code
`-32602` with `supported` and `requested` fields.

## Context object (FastMCP)

Add `ctx: Context` as a typed parameter to any tool or resource function to
access server internals within a request:

```python
@mcp.tool()
async def my_tool(query: str, ctx: Context) -> str:
    await ctx.info(f"Processing: {query}")
    await ctx.report_progress(0.5, 1.0, message="halfway")
    resource = await ctx.read_resource("data://source")
    return resource
```

Context is injected by the framework. Do not instantiate it yourself.
Available on `ctx`: `request_id`, `client_id`, `fastmcp` (server instance),
`session` (raw `ServerSession`), `request_context` (lifespan state).

## Lifespan (FastMCP)

For startup/teardown (database connections, caches):

```python
from contextlib import asynccontextmanager

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

## Logging and notifications

Log through `ctx` to send messages to the client (not stdout):

```python
await ctx.debug("detail")
await ctx.info("status")
await ctx.warning("heads up")
await ctx.error("problem")
```

Notify clients of list changes: `await ctx.session.send_resource_list_changed()`.

**Never use `print()` in stdio servers** — it corrupts the JSON-RPC stream.
Use `print(..., file=sys.stderr)` or a logger configured for stderr.

## Elicitation (FastMCP)

Tools can request structured input from the user mid-execution:

```python
from pydantic import BaseModel

class Prefs(BaseModel):
    confirm: bool
    date: str = "2024-12-26"

@mcp.tool()
async def book(date: str, ctx: Context) -> str:
    if date == "2024-12-25":
        result = await ctx.elicit("Pick another date?", schema=Prefs)
        if result.action == "accept" and result.data:
            return f"Booked for {result.data.date}"
        return "Cancelled"
    return f"Booked for {date}"
```

`ElicitationResult` fields: `action` ("accept", "decline", "cancel"),
`data` (validated model, only on accept), `validation_error`.

For OAuth flows or external URLs, use `ctx.elicit_url()` or raise
`UrlElicitationRequiredError`.

## Sampling (FastMCP)

Tools can request LLM completions through the client:

```python
from mcp.types import SamplingMessage, TextContent

@mcp.tool()
async def summarize(text: str, ctx: Context) -> str:
    result = await ctx.session.create_message(
        messages=[SamplingMessage(
            role="user",
            content=TextContent(type="text", text=f"Summarize: {text}"),
        )],
        max_tokens=200,
    )
    return result.content.text if result.content.type == "text" else str(result.content)
```

Sampling puts the client in control of LLM access, user approval, and model
selection. The server never calls an LLM directly.

## Argument completion

Servers can provide autocompletion suggestions for prompt arguments and resource
template parameters via `completions/complete`:

```python
from mcp import ClientSession
from mcp.types import PromptReference, ResourceTemplateReference

# Client-side — server provides suggestions
result = await session.complete(
    ref=ResourceTemplateReference(type="ref/resource", uri="weather://{city}"),
    argument={"name": "city", "value": "lon"},
    context_arguments={"country": "UK"},  # previously resolved args
)
# result.completion.values — list of suggestion strings
```

FastMCP can handle completions if you register a completion handler. The spec
defines this in `mcpio__specification__2025-11-25__server__utilities__completion.md`.

## Pagination

List operations (`tools/list`, `resources/list`, etc.) support cursor-based
pagination. Servers yield results in chunks; clients pass the cursor forward.

```python
# Client side — paginating through tools
result = await session.list_tools()
while result.next_cursor:  # v2 snake_case
    result = await session.list_tools(
        params=PaginatedRequestParams(cursor=result.next_cursor)
    )
    # process result.tools
```

Cursors are opaque — don't parse or construct them. An absent `nextCursor` means
no more pages.

## Logging

Servers send structured log messages to clients. 8 RFC-5424 severity levels
(`debug`, `info`, `notice`, `warning`, `error`, `critical`, `alert`, `emergency`).

```python
# Via context (FastMCP) — preferred
await ctx.info("Server started")
await ctx.warning("Rate limit approaching")

# Low-level
await ctx.session.send_log_message(level="info", data="Server started")
```

Clients may set minimum log level via `logging/setLevel`. Servers must declare
`logging` capability if they emit log messages.

**stdio note**: log to stderr or via MCP log messages. Never log to stdout.

## Icons

Tools, resources, prompts, and the server itself can expose icons for UI display:

```python
from mcp.server.fastmcp import FastMCP, Icon

icon = Icon(src="icon.png", mimeType="image/png", sizes="64x64")
mcp = FastMCP("My Server", icons=[icon])

@mcp.tool(icons=[icon])
def my_tool(): ...
```

Icons must use HTTPS or `data:` URIs. Clients should treat icon bytes as
untrusted input. Source: `docs/mcpio__specification__2025-11-25__basic__index.md`.
