# MCP Integration

Source: `docs/mcp.md`

## Overview

LangChain agents use tools defined on any MCP (Model Context Protocol) server via
`langchain-mcp-adapters`. `MultiServerMCPClient` connects to one or more servers and
returns their tools as standard LangChain tools — identical to `@tool`-decorated
functions from the agent's perspective.

```bash
pip install langchain-mcp-adapters
pip install fastmcp  # to author custom MCP servers
```

`MultiServerMCPClient` is **stateless by default** — each tool invocation creates a
fresh `ClientSession`, executes the tool, and then cleans up. See [Stateful sessions](#stateful-sessions)
for persistent connections.

## Quickstart

```python
import asyncio
from langchain_mcp_adapters.client import MultiServerMCPClient
from langchain.agents import create_agent

async def main():
    client = MultiServerMCPClient({
        "math": {
            "transport": "stdio",       # local subprocess via stdin/stdout
            "command": "python",
            "args": ["/absolute/path/to/math_server.py"],
        },
        "weather": {
            "transport": "http",        # remote server over HTTP
            "url": "http://localhost:8000/mcp",
        },
    })

    tools = await client.get_tools()
    agent = create_agent("claude-sonnet-4-6", tools)

    result = await agent.ainvoke(
        {"messages": [{"role": "user", "content": "What is (3 + 5) x 12?"}]}
    )
    print(result["messages"][-1].text)

asyncio.run(main())
```

## Custom MCP servers (FastMCP)

```python
# math_server.py — stdio transport (launched as subprocess)
from fastmcp import FastMCP

mcp = FastMCP("Math")

@mcp.tool()
def add(a: int, b: int) -> int:
    """Add two numbers."""
    return a + b

@mcp.tool()
def multiply(a: int, b: int) -> int:
    """Multiply two numbers."""
    return a * b

if __name__ == "__main__":
    mcp.run(transport="stdio")
```

```python
# weather_server.py — HTTP transport (run as a server process)
from fastmcp import FastMCP

mcp = FastMCP("Weather")

@mcp.tool()
async def get_weather(location: str) -> str:
    """Get weather for a location."""
    return f"Sunny and 72°F in {location}"

if __name__ == "__main__":
    mcp.run(transport="streamable-http")  # listens on port 8000 by default
```

## Transports

| Transport | Use case | Config keys |
|-----------|----------|-------------|
| `stdio` | Local subprocess — launched and managed by the client | `command`, `args`, `env` |
| `http` | Remote HTTP server (also called `streamable-http`) | `url`, `headers`, `auth` |
| `sse` | Server-sent events (deprecated by MCP spec, still functional) | `url`, `headers` |

### HTTP with authentication

```python
# Static headers (e.g., API key)
client = MultiServerMCPClient({
    "my_api": {
        "transport": "http",
        "url": "https://api.example.com/mcp",
        "headers": {
            "Authorization": "Bearer sk-...",
            "X-Tenant-ID": "acme",
        },
    }
})

# Custom auth via httpx.Auth interface
client = MultiServerMCPClient({
    "my_api": {
        "transport": "http",
        "url": "https://api.example.com/mcp",
        "auth": my_httpx_auth_object,  # implements httpx.Auth
    }
})
```

### stdio with environment variables

```python
client = MultiServerMCPClient({
    "db_tool": {
        "transport": "stdio",
        "command": "python",
        "args": ["/path/to/db_server.py"],
        "env": {
            "DATABASE_URL": "postgresql://...",
            "DB_POOL_SIZE": "10",
        },
    }
})
```

## Stateful sessions

Use `client.session()` when the MCP server maintains state across calls (e.g.,
a database connection, a scraping session, or a shell session).

```python
from langchain_mcp_adapters.client import MultiServerMCPClient
from langchain_mcp_adapters.tools import load_mcp_tools
from langchain.agents import create_agent

client = MultiServerMCPClient({"browser": {"transport": "http", "url": "..."}})

async with client.session("browser") as session:
    tools = await load_mcp_tools(session)
    agent = create_agent("claude-sonnet-4-6", tools)
    # All tool calls within this block share the same server session
    result = await agent.ainvoke(
        {"messages": [{"role": "user", "content": "Navigate to docs and extract the API reference"}]}
    )
```

## Core features

### Loading tools

```python
# From all servers
tools = await client.get_tools()

# From a specific server session
async with client.session("math") as session:
    from langchain_mcp_adapters.tools import load_mcp_tools
    tools = await load_mcp_tools(session)
```

### Structured content

When an MCP tool returns `structuredContent` alongside text, the adapter wraps it
in an `MCPToolArtifact` accessible via `ToolMessage.artifact`:

```python
from langchain.messages import ToolMessage

result = await agent.ainvoke({"messages": [{"role": "user", "content": "Get order status"}]})

for msg in result["messages"]:
    if isinstance(msg, ToolMessage) and msg.artifact:
        structured = msg.artifact["structured_content"]
        print(structured)  # machine-readable data, e.g. {"order_id": "ABC", "status": "shipped"}
```

### Multimodal tool content

MCP tools that return images or mixed content are normalized to LangChain's
standard content blocks:

```python
result = await agent.ainvoke(
    {"messages": [{"role": "user", "content": "Take a screenshot of the dashboard"}]}
)

for msg in result["messages"]:
    if msg.type == "tool":
        for block in msg.content_blocks:
            if block["type"] == "text":
                print(f"Text: {block['text']}")
            elif block["type"] == "image":
                print(f"Image URL: {block.get('url')}")
                print(f"Image (base64): {block.get('base64', '')[:50]}...")
```

### Resources

MCP resources expose data (files, database records, API responses). They are
converted to `Blob` objects:

```python
# Load all resources from a server
blobs = await client.get_resources("server_name")

# Load specific resources by URI
blobs = await client.get_resources(
    "server_name",
    uris=["file:///path/to/report.pdf", "file:///path/to/config.json"]
)

for blob in blobs:
    print(f"URI: {blob.metadata['uri']}, MIME: {blob.mimetype}")
    print(blob.as_string())  # for text content
```

Or directly via session:

```python
from langchain_mcp_adapters.resources import load_mcp_resources

async with client.session("docs") as session:
    blobs = await load_mcp_resources(session)
```

### Prompts

MCP prompts are reusable templates. They load as LangChain messages:

```python
# Load a prompt by name
messages = await client.get_prompt("server_name", "summarize")

# Load with arguments
messages = await client.get_prompt(
    "server_name",
    "code_review",
    arguments={"language": "python", "focus": "security"},
)

for msg in messages:
    print(f"{msg.type}: {msg.content}")

# Use as the starting message history for an agent run
result = await agent.ainvoke({"messages": messages})
```

## Tool interceptors

MCP servers run as separate processes and cannot access LangGraph runtime context
(store, agent state, user context). **Interceptors bridge this gap** — they wrap
every MCP tool call with access to the full `ToolRuntime`.

Interceptors also enable retry logic, request modification, header injection, and
short-circuit execution.

### Accessing runtime context

```python
from dataclasses import dataclass
from langchain_mcp_adapters.client import MultiServerMCPClient
from langchain_mcp_adapters.interceptors import MCPToolCallRequest
from langchain.agents import create_agent

@dataclass
class UserContext:
    user_id: str
    api_key: str

async def inject_user_context(request: MCPToolCallRequest, handler):
    """Inject user credentials into every MCP tool call."""
    runtime = request.runtime
    user_id = runtime.context.user_id
    api_key = runtime.context.api_key

    modified = request.override(
        args={**request.args, "user_id": user_id}
    )
    return await handler(modified)


client = MultiServerMCPClient(
    {"my_api": {"transport": "http", "url": "http://localhost:8000/mcp"}},
    tool_interceptors=[inject_user_context],
)
tools = await client.get_tools()
agent = create_agent("openai:gpt-5.4", tools, context_schema=UserContext)

result = await agent.ainvoke(
    {"messages": [{"role": "user", "content": "Show my orders"}]},
    context=UserContext(user_id="u123", api_key="sk-..."),
)
```

### Accessing the store (long-term memory)

```python
from langchain.agents import create_agent
from langgraph.store.memory import InMemoryStore

async def personalize_with_store(request: MCPToolCallRequest, handler):
    """Apply stored user preferences to search tool calls."""
    runtime = request.runtime
    user_id = runtime.context.user_id
    store = runtime.store

    prefs = store.get(("preferences",), user_id)
    if prefs and request.name == "search":
        request = request.override(args={
            **request.args,
            "language": prefs.value.get("language", "en"),
            "limit": prefs.value.get("result_limit", 10),
        })

    return await handler(request)


client = MultiServerMCPClient(
    {...},
    tool_interceptors=[personalize_with_store],
)
tools = await client.get_tools()
agent = create_agent("openai:gpt-5.4", tools, context_schema=UserContext, store=InMemoryStore())
```

### Accessing agent state (block unauthenticated calls)

```python
from langchain.messages import ToolMessage

async def require_authentication(request: MCPToolCallRequest, handler):
    """Block sensitive MCP tools if user is not authenticated."""
    state = request.runtime.state
    is_authenticated = state.get("authenticated", False)
    sensitive_tools = {"delete_file", "update_settings", "export_data"}

    if request.name in sensitive_tools and not is_authenticated:
        return ToolMessage(
            content="Authentication required. Please log in first.",
            tool_call_id=request.runtime.tool_call_id,
        )

    return await handler(request)
```

### State updates and Commands from interceptors

Interceptors can return `Command` objects to update agent state or control flow:

```python
from langgraph.types import Command
from langchain.messages import ToolMessage

async def handle_task_completion(request: MCPToolCallRequest, handler):
    """Mark task complete and switch to summary agent on submit_order."""
    result = await handler(request)

    if request.name == "submit_order":
        return Command(
            update={
                "messages": [result] if isinstance(result, ToolMessage) else [],
                "task_status": "completed",
            },
            goto="summary_agent",  # hand off to another node
        )

    return result


async def end_on_success(request: MCPToolCallRequest, handler):
    """End agent run when mark_complete is called."""
    result = await handler(request)

    if request.name == "mark_complete":
        return Command(
            update={"messages": [result], "status": "done"},
            goto="__end__",
        )

    return result
```

### Custom interceptor patterns

```python
# Logging interceptor
async def logging_interceptor(request: MCPToolCallRequest, handler):
    print(f"[MCP] Calling {request.name} with args: {request.args}")
    result = await handler(request)
    print(f"[MCP] {request.name} returned: {result}")
    return result


# Dynamic auth header injection
async def auth_header_interceptor(request: MCPToolCallRequest, handler):
    token = get_token_for_service(request.name)
    modified = request.override(headers={"Authorization": f"Bearer {token}"})
    return await handler(modified)


# Retry with exponential backoff
import asyncio

async def retry_interceptor(request: MCPToolCallRequest, handler, max_retries=3):
    last_error = None
    for attempt in range(max_retries):
        try:
            return await handler(request)
        except Exception as e:
            last_error = e
            if attempt < max_retries - 1:
                wait = 1.0 * (2 ** attempt)
                print(f"[MCP] {request.name} failed (attempt {attempt + 1}), retrying in {wait}s")
                await asyncio.sleep(wait)
    raise last_error


# Append structured content to tool message (make it visible to model)
import json
from mcp.types import TextContent

async def append_structured_content(request: MCPToolCallRequest, handler):
    result = await handler(request)
    if result.structuredContent:
        result.content += [
            TextContent(type="text", text=json.dumps(result.structuredContent))
        ]
    return result


# Compose interceptors — first in list is outermost layer
client = MultiServerMCPClient(
    {"api": {"transport": "http", "url": "..."}},
    tool_interceptors=[
        logging_interceptor,       # outer: fires first before, last after
        auth_header_interceptor,   # middle
        retry_interceptor,         # inner: fires last before, first after
    ],
)
```

## Progress notifications

Subscribe to progress updates for long-running tool calls:

```python
from langchain_mcp_adapters.callbacks import Callbacks, CallbackContext

async def on_progress(progress: float, total: float | None, message: str | None, context: CallbackContext):
    pct = (progress / total * 100) if total else progress
    print(f"[{context.server_name}/{context.tool_name}] {pct:.0f}% — {message}")


client = MultiServerMCPClient(
    {...},
    callbacks=Callbacks(on_progress=on_progress),
)
```

`CallbackContext` provides `server_name` and `tool_name` (available during tool calls).

## Server log messages

```python
from mcp.types import LoggingMessageNotificationParams

async def on_log(params: LoggingMessageNotificationParams, context: CallbackContext):
    print(f"[{context.server_name}] {params.level.upper()}: {params.data}")


client = MultiServerMCPClient(
    {...},
    callbacks=Callbacks(on_logging_message=on_log),
)
```

## Elicitation (interactive server-to-client input)

MCP servers can request additional input from users mid-execution via elicitation.

**Server side:**

```python
from pydantic import BaseModel
from mcp.server.fastmcp import Context, FastMCP

server = FastMCP("ProfileCreator")

class UserDetails(BaseModel):
    email: str
    age: int

@server.tool()
async def create_profile(name: str, ctx: Context) -> str:
    """Create a user profile, prompting for extra details."""
    result = await ctx.elicit(
        message=f"Please provide additional details for {name}'s profile:",
        schema=UserDetails,
    )
    if result.action == "accept" and result.data:
        return f"Created profile for {name}: email={result.data.email}, age={result.data.age}"
    if result.action == "decline":
        return f"Minimal profile created for {name}."
    return "Profile creation cancelled."
```

**Client side:**

```python
from langchain_mcp_adapters.callbacks import Callbacks, CallbackContext
from mcp.shared.context import RequestContext
from mcp.types import ElicitRequestParams, ElicitResult

async def on_elicitation(
    mcp_context: RequestContext,
    params: ElicitRequestParams,
    context: CallbackContext,
) -> ElicitResult:
    """Prompt user for input and return their response."""
    # In a real app: render params.message and params.requestedSchema to the user
    user_input = await prompt_user(params.message, params.requestedSchema)

    if user_input is None:
        return ElicitResult(action="decline")

    return ElicitResult(action="accept", content=user_input)


client = MultiServerMCPClient(
    {"profile": {"transport": "http", "url": "http://localhost:8000/mcp"}},
    callbacks=Callbacks(on_elicitation=on_elicitation),
)
```

Elicitation response actions:

| Action | Description |
|--------|-------------|
| `accept` | User provided input; include data in `content` |
| `decline` | User chose not to provide the information |
| `cancel` | User cancelled the operation entirely |

## Complete example: multi-server agent with interceptors

```python
import asyncio
from dataclasses import dataclass
from langchain_mcp_adapters.client import MultiServerMCPClient
from langchain_mcp_adapters.interceptors import MCPToolCallRequest
from langchain_mcp_adapters.callbacks import Callbacks, CallbackContext
from langchain.agents import create_agent
from langgraph.store.memory import InMemoryStore
from langchain.messages import ToolMessage

@dataclass
class AppContext:
    user_id: str
    tenant_id: str

async def inject_tenant(request: MCPToolCallRequest, handler):
    """Add tenant isolation to every MCP tool call."""
    ctx = request.runtime.context
    return await handler(request.override(args={
        **request.args,
        "tenant_id": ctx.tenant_id,
    }))

async def log_calls(request: MCPToolCallRequest, handler):
    print(f"[{request.name}] args={request.args}")
    result = await handler(request)
    print(f"[{request.name}] done")
    return result

async def on_progress(progress, total, message, context: CallbackContext):
    print(f"[{context.server_name}] {progress}/{total} — {message}")


async def main():
    store = InMemoryStore()

    client = MultiServerMCPClient(
        {
            "search": {"transport": "http", "url": "http://search-service:8000/mcp"},
            "crm": {
                "transport": "stdio",
                "command": "python",
                "args": ["/services/crm_mcp_server.py"],
                "env": {"CRM_API_KEY": "sk-crm-..."},
            },
        },
        tool_interceptors=[log_calls, inject_tenant],
        callbacks=Callbacks(on_progress=on_progress),
    )

    tools = await client.get_tools()

    agent = create_agent(
        model="anthropic:claude-sonnet-4-6",
        tools=tools,
        context_schema=AppContext,
        store=store,
        system_prompt=(
            "You are a customer service agent. "
            "Use the search tool to find product information. "
            "Use the crm tool to look up and update customer records."
        ),
    )

    result = await agent.ainvoke(
        {"messages": [{"role": "user", "content": "Find orders for customer 42 and check status"}]},
        context=AppContext(user_id="agent-001", tenant_id="acme"),
    )
    print(result["messages"][-1].text)


asyncio.run(main())
```
