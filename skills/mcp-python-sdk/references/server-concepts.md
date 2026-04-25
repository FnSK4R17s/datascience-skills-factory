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

The model decides when to call tools. Resources are loaded by the client
application. Prompts are invoked by the user (slash commands, menus).

## Tools

Functions the LLM can call to take actions or retrieve data.

Protocol operations: `tools/list`, `tools/call`.

### Basic tool patterns

```python
from mcp.server.fastmcp import FastMCP

mcp = FastMCP("Tools Demo")

# Simple synchronous tool
@mcp.tool()
def calculate_bmi(weight_kg: float, height_m: float) -> float:
    """Calculate Body Mass Index."""
    return weight_kg / (height_m ** 2)

# Tool with enum-like parameter
@mcp.tool()
def convert_temperature(value: float, from_unit: str, to_unit: str) -> float:
    """Convert temperature between Celsius, Fahrenheit, and Kelvin.
    from_unit and to_unit: 'C', 'F', or 'K'
    """
    # Convert to Celsius first
    if from_unit == "F":
        celsius = (value - 32) * 5 / 9
    elif from_unit == "K":
        celsius = value - 273.15
    else:
        celsius = value

    # Convert from Celsius to target
    if to_unit == "F":
        return celsius * 9 / 5 + 32
    elif to_unit == "K":
        return celsius + 273.15
    return celsius

# Async tool
@mcp.tool()
async def check_service_health(url: str, timeout: float = 5.0) -> dict[str, str]:
    """Check if a service is healthy by making an HTTP GET request."""
    import httpx
    try:
        async with httpx.AsyncClient(timeout=timeout) as client:
            resp = await client.get(url)
        return {"status": "healthy", "code": str(resp.status_code)}
    except Exception as e:
        return {"status": "unhealthy", "error": str(e)}
```

### Tool with progress reporting

```python
from mcp.server.fastmcp import Context

@mcp.tool()
async def process_batch(items: list[str], ctx: Context) -> str:
    """Process a batch of items with progress updates."""
    total = len(items)
    results = []

    await ctx.info(f"Starting batch processing of {total} items")

    for i, item in enumerate(items):
        await ctx.report_progress(
            progress=i / total,
            total=1.0,
            message=f"Processing item {i+1}/{total}: {item}",
        )
        # Do actual processing here
        results.append(f"processed:{item}")

    await ctx.report_progress(progress=1.0, total=1.0, message="Complete")
    await ctx.info(f"Completed processing {total} items")
    return f"Processed {total} items: {', '.join(results)}"
```

### Tool that reads resources

```python
@mcp.tool()
async def analyze_config(ctx: Context) -> str:
    """Read the server config resource and analyze it."""
    config_text = await ctx.read_resource("config://settings")
    import json
    config = json.loads(config_text)
    return f"Debug mode: {config.get('debug', False)}, Theme: {config.get('theme', 'default')}"
```

### Structured output with validation

```python
from pydantic import BaseModel, Field
from typing import TypedDict


class AnalysisResult(BaseModel):
    sentiment: str = Field(description="positive, negative, or neutral")
    confidence: float = Field(description="Confidence score 0.0 to 1.0", ge=0.0, le=1.0)
    key_phrases: list[str]


@mcp.tool()
def analyze_text(text: str) -> AnalysisResult:
    """Analyze text sentiment — returns validated structured data."""
    # FastMCP generates outputSchema automatically from AnalysisResult
    return AnalysisResult(
        sentiment="positive",
        confidence=0.87,
        key_phrases=["excellent", "highly recommended"],
    )


class FileStats(TypedDict):
    line_count: int
    word_count: int
    char_count: int


@mcp.tool()
def count_file_stats(text: str) -> FileStats:
    """Count lines, words, and characters in text."""
    lines = text.splitlines()
    words = text.split()
    return FileStats(
        line_count=len(lines),
        word_count=len(words),
        char_count=len(text),
    )
```

### Tool error handling

```python
from mcp.types import CallToolResult, TextContent

@mcp.tool()
async def safe_divide(numerator: float, denominator: float, ctx: Context) -> float:
    """Divide two numbers safely."""
    if denominator == 0:
        # Raising an exception from a tool causes FastMCP to wrap it
        # as is_error=True in the CallToolResult
        raise ValueError("Cannot divide by zero")
    return numerator / denominator
```

When a tool raises an exception, FastMCP returns `CallToolResult(is_error=True,
content=[TextContent(text=str(exception))])`. The model sees the error message.

## Resources

Read-only data sources. Clients (not the model) decide which resources to load.

Protocol operations: `resources/list`, `resources/templates/list`,
`resources/read`, `resources/subscribe`.

### Static resources

```python
import json
from mcp.server.fastmcp import FastMCP

mcp = FastMCP("Resource Demo")

@mcp.resource("config://settings")
def get_settings() -> str:
    """Get application configuration."""
    return json.dumps({
        "theme": "dark",
        "language": "en",
        "debug": False,
        "max_results": 100,
    }, indent=2)

@mcp.resource("data://schema", mime_type="application/json")
def get_schema() -> str:
    """Get the database schema."""
    return json.dumps({
        "tables": ["users", "orders", "products"],
        "version": "2.3",
    })
```

### Dynamic resource templates

```python
@mcp.resource("file://documents/{name}")
def read_document(name: str) -> str:
    """Read a document by name."""
    # Would normally read from disk
    return f"Content of document: {name}"

@mcp.resource("users://{user_id}/profile")
async def get_user_profile(user_id: str) -> str:
    """Get user profile. Supports async."""
    # Would normally query a database
    return json.dumps({"id": user_id, "name": f"User {user_id}", "role": "member"})

@mcp.resource("api://github/{owner}/{repo}/readme")
async def get_github_readme(owner: str, repo: str) -> str:
    """Fetch a GitHub repository's README."""
    import httpx
    url = f"https://api.github.com/repos/{owner}/{repo}/readme"
    async with httpx.AsyncClient() as client:
        resp = await client.get(url, headers={"Accept": "application/vnd.github.raw"})
        if resp.status_code == 200:
            return resp.text
        return f"README not found for {owner}/{repo}"
```

### Resource with context (for logging)

```python
@mcp.resource("db://query/{table}")
async def query_table(table: str, ctx: Context) -> str:
    """Query a database table and return results as JSON."""
    await ctx.info(f"Querying table: {table}")
    # Access lifespan context
    db = ctx.request_context.lifespan_context.db
    results = db.query(f"SELECT * FROM {table} LIMIT 100")
    return json.dumps(results)
```

### Notifying clients of resource changes

```python
@mcp.tool()
async def update_config(key: str, value: str, ctx: Context) -> str:
    """Update a config key and notify clients."""
    # Update the config
    # ...

    # Notify clients the resource list or a specific resource changed
    await ctx.session.send_resource_updated("config://settings")
    await ctx.session.send_resource_list_changed()
    return f"Updated {key} = {value}"
```

## Prompts

Parameterized instruction templates invoked by users.

Protocol operations: `prompts/list`, `prompts/get`.

### Simple string prompts

```python
from mcp.server.fastmcp import FastMCP
from mcp.server.fastmcp.prompts import base

mcp = FastMCP("Prompt Demo")

@mcp.prompt(title="Code Review")
def review_code(code: str, language: str = "python") -> str:
    """Generate a code review prompt."""
    return f"Please review this {language} code for bugs, style, and performance:\n\n```{language}\n{code}\n```"

@mcp.prompt(title="Email Draft")
def draft_email(subject: str, recipient: str, tone: str = "professional") -> str:
    """Draft an email."""
    return f"Write a {tone} email to {recipient} with subject: '{subject}'"
```

### Multi-turn prompts (list of messages)

```python
@mcp.prompt(title="Debug Assistant")
def debug_error(error: str, code: str = "") -> list[base.Message]:
    """Generate a debugging conversation starter."""
    messages = [
        base.UserMessage("I'm seeing this error:"),
        base.UserMessage(f"```\n{error}\n```"),
    ]
    if code:
        messages.append(base.UserMessage(f"In this code:\n```\n{code}\n```"))
    messages.append(
        base.AssistantMessage("I'll help debug that. Let me analyze the error.")
    )
    return messages

@mcp.prompt(title="Pair Programming")
def pair_program(task: str, language: str) -> list[base.Message]:
    """Start a pair programming session."""
    return [
        base.UserMessage(f"I want to implement: {task}"),
        base.UserMessage(f"Using language: {language}"),
        base.AssistantMessage(
            f"Great! Let's break this down step by step. "
            f"First, let me understand the requirements..."
        ),
        base.UserMessage("Yes, let's start with the core logic."),
    ]
```

## Capabilities

FastMCP infers capabilities automatically from registered decorators.

| Capability | Condition for declaration |
|-----------|--------------------------|
| `tools` | At least one `@mcp.tool()` registered |
| `resources` | At least one `@mcp.resource()` registered |
| `prompts` | At least one `@mcp.prompt()` registered |
| `logging` | Always declared by FastMCP |
| `completions` | When completion handlers are registered |

Sub-capabilities: `listChanged` (push notifications when list changes),
`subscribe` (resources only — notify on specific resource changes).

A server that does not declare `tools` capability will not receive tool calls,
even if handlers exist. Capabilities are fixed for the session lifetime.

## Lifecycle

Three mandatory phases:

1. **Initialization** — client sends `initialize` with protocol version and
   capabilities; server responds with its own; client sends `initialized`
   notification.
2. **Operation** — normal request/response and notification exchange.
3. **Shutdown** — client closes transport. No protocol-level shutdown message.

**Version negotiation**: client proposes its latest version; server accepts
or counters. On mismatch, the server returns JSON-RPC error `-32602` with
`supported` and `requested` fields.

## Argument completion

Servers can provide autocompletion for prompt arguments and resource template
parameters. Clients send `completions/complete` requests.

```python
# Client-side — requesting completions (for reference)
from mcp import ClientSession
from mcp.types import PromptReference, ResourceTemplateReference

result = await session.complete(
    ref=ResourceTemplateReference(type="ref/resource", uri="weather://{city}"),
    argument={"name": "city", "value": "lon"},
    context_arguments={"country": "UK"},  # previously resolved args
)
# result.completion.values — list of suggestion strings like ["London", "Long Beach"]
```

## Pagination

List operations support cursor-based pagination. Clients pass the cursor
forward through all pages.

```python
# Server-side pagination (low-level server)
from mcp.types import ListResourcesResult, Resource

ITEMS = [f"item-{i}" for i in range(1, 201)]  # 200 items

@server.list_resources()
async def list_resources_paginated(request):
    page_size = 20
    cursor = request.params.cursor if request.params else None
    start = 0 if cursor is None else int(cursor)
    end = start + page_size

    resources = [
        Resource(uri=f"resource://{item}", name=item)
        for item in ITEMS[start:end]
    ]
    next_cursor = str(end) if end < len(ITEMS) else None

    return ListResourcesResult(resources=resources, nextCursor=next_cursor)
```

```python
# Client-side — paginating through all resources
from mcp.types import PaginatedRequestParams

all_resources = []
cursor = None

while True:
    result = await session.list_resources(
        params=PaginatedRequestParams(cursor=cursor) if cursor else None
    )
    all_resources.extend(result.resources)

    if result.nextCursor:  # v2: next_cursor
        cursor = result.nextCursor
    else:
        break

print(f"Total resources: {len(all_resources)}")
```

Cursors are opaque — do not parse or construct them.

## Logging

8 RFC-5424 severity levels: `debug`, `info`, `notice`, `warning`, `error`,
`critical`, `alert`, `emergency`.

```python
# Via context (FastMCP) — preferred
@mcp.tool()
async def my_tool(ctx: Context) -> str:
    await ctx.debug("Detailed diagnostic")
    await ctx.info("Normal operation")
    await ctx.warning("Unexpected but recoverable")
    await ctx.error("Something failed")
    await ctx.log(level="notice", message="Custom level")
    return "done"

# Low-level via session
await ctx.session.send_log_message(level="info", data="Server started", logger="app.core")
```

Clients may set minimum log level via `logging/setLevel`. Servers must declare
`logging` capability if they emit messages.

**stdio rule**: Never log to stdout in a stdio server. Any non-JSON-RPC write
to stdout corrupts the stream. Log to stderr or use MCP log messages.

```python
import sys

# Safe in stdio servers
print("Debug info", file=sys.stderr)
```

## Icons

Tools, resources, prompts, and the server can expose icons for UI display:

```python
from mcp.server.fastmcp import FastMCP, Icon

icon = Icon(src="https://example.com/icon.png", mimeType="image/png", sizes="64x64")
mcp = FastMCP("My Server", icons=[icon])

@mcp.tool(icons=[icon])
def my_tool(): ...

@mcp.resource("demo://resource", icons=[icon])
def my_resource(): ...
```

Icons must use HTTPS or `data:` URIs. Clients should treat icon bytes as
untrusted input.
