# FastMCP — High-Level Server API

`FastMCP` is the recommended starting point for new MCP servers. It provides
decorator-driven registration of tools, resources, and prompts, and handles
capabilities declaration, schema generation, and error wrapping automatically.

## Basic structure

```python
from mcp.server.fastmcp import FastMCP, Context

mcp = FastMCP("server-name")

@mcp.tool()
async def my_tool(param: str) -> str:
    """Tool description shown to the LLM."""
    return f"result: {param}"

@mcp.resource("mydata://items/{item_id}")
async def get_item(item_id: str) -> str:
    """Resource description."""
    return f"data for {item_id}"

@mcp.prompt()
async def my_prompt(topic: str) -> list[dict]:
    """Prompt description."""
    return [{"role": "user", "content": f"Tell me about {topic}"}]

if __name__ == "__main__":
    mcp.run()
```

## Tool registration

FastMCP infers the tool's JSON Schema input from Python type annotations.
Use standard types and `Annotated` for descriptions:

```python
from typing import Annotated
from pydantic import Field

@mcp.tool()
async def search(
    query: Annotated[str, Field(description="Search query")],
    limit: Annotated[int, Field(description="Max results", ge=1, le=100)] = 10,
) -> list[str]:
    """Search for items matching the query."""
    ...
```

- Return type is not part of the input schema but is used for documentation.
- The function docstring becomes the tool description.
- Pydantic models work as parameter types and produce nested schemas.

### Tool annotations

Mark tools as read-only or destructive to help clients build permission UIs:

```python
from mcp.server.fastmcp import FastMCP
from mcp.types import Tool

@mcp.tool(annotations={"readOnlyHint": True})
async def read_file(path: str) -> str:
    ...

@mcp.tool(annotations={"destructiveHint": True})
async def delete_record(record_id: str) -> str:
    ...
```

## Resource registration

Resources use URI patterns. FastMCP maps path parameters to function arguments:

```python
@mcp.resource("file:///{path}")
async def read_file(path: str) -> str:
    with open(path) as f:
        return f.read()
```

For static resources (no parameters), use a plain URI:

```python
@mcp.resource("config://app")
async def get_config() -> str:
    return json.dumps(CONFIG)
```

## Prompt registration

Prompts return a list of message dicts or `mcp.types.PromptMessage` objects:

```python
@mcp.prompt()
async def analyze_code(language: str, code: str) -> list:
    return [
        {"role": "user", "content": f"Analyze this {language} code:\n\n{code}"}
    ]
```

## Context object

FastMCP passes a `Context` object to handlers that request it. The context
provides access to server internals and the active session:

```python
@mcp.tool()
async def tool_with_context(query: str, ctx: Context) -> str:
    # Log to the client (not to stdout)
    await ctx.info(f"Processing query: {query}")
    await ctx.warning("Something worth noting")

    # Report progress (for long-running tools)
    await ctx.report_progress(current=0, total=100)

    # Read a resource from within a tool handler
    resource = await ctx.read_resource("data://source")

    # Request the client to run an LLM call (sampling)
    result = await ctx.sample("Summarize this", max_tokens=200)

    return result.text
```

`Context` is injected by name — declare it as a parameter named `ctx` typed
`Context`. Do not instantiate it yourself.

## Composition and mounting

FastMCP supports composing multiple servers:

```python
main = FastMCP("main")
sub = FastMCP("sub-module")

@sub.tool()
async def sub_tool(x: int) -> int:
    return x * 2

# Mount sub under a prefix — tools become "math/sub_tool"
main.mount("math", sub)
```

Mounted servers inherit the parent's transport. Use mounting to split a large
server into logical modules without separate processes.

## Lifespan hooks

Run setup/teardown around the server's operational lifetime:

```python
from contextlib import asynccontextmanager

@asynccontextmanager
async def lifespan(server: FastMCP):
    # Setup: connect to DB, initialize caches
    db = await connect_db()
    yield {"db": db}   # values go into server.state
    # Teardown: clean up
    await db.close()

mcp = FastMCP("my-server", lifespan=lifespan)

@mcp.tool()
async def query(sql: str, ctx: Context) -> str:
    db = ctx.request_context.lifespan_context["db"]
    return await db.fetchall(sql)
```

## Running the server

```python
# stdio (default)
mcp.run()

# Streamable HTTP
mcp.run(transport="streamable-http", host="127.0.0.1", port=8000)

# From CLI (if you use the mcp CLI tool)
# mcp run my_module.py
```

## When to leave FastMCP for the low-level API

FastMCP is a convenience layer. Leave it when you need:

- Custom request/response interception at the protocol level.
- Dynamic tool registration that changes at runtime based on session-specific
  state (FastMCP registers tools at class construction time).
- Fine-grained control over capability negotiation (e.g. refusing to negotiate
  certain capabilities with specific clients).
- Middleware that wraps every incoming message.

See `references/low-level-server.md` for the low-level API.
