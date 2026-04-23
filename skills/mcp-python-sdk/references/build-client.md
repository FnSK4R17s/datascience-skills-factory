# Build a Client — Tutorial Patterns

Sources: `docs/mcpio__docs__develop__build-client.md`

This file captures the concrete patterns from the build-a-client tutorial
(LLM-powered chatbot connecting to an MCP server via stdio).

## Project setup

```bash
uv init mcp-client
cd mcp-client
uv add mcp anthropic python-dotenv
```

## Connecting to a stdio server

The canonical Python client pattern uses `ClientSession` with `stdio_client`:

```python
import asyncio
from contextlib import AsyncExitStack
from mcp import ClientSession, StdioServerParameters
from mcp.client.stdio import stdio_client

class MCPClient:
    def __init__(self):
        self.session = None
        self.exit_stack = AsyncExitStack()

    async def connect(self, server_script_path: str):
        command = "python" if server_script_path.endswith(".py") else "node"
        params = StdioServerParameters(command=command, args=[server_script_path])

        transport = await self.exit_stack.enter_async_context(stdio_client(params))
        self.session = await self.exit_stack.enter_async_context(
            ClientSession(*transport)
        )
        await self.session.initialize()

        tools = await self.session.list_tools()
        print("Tools:", [t.name for t in tools.tools])

    async def cleanup(self):
        await self.exit_stack.aclose()
```

## Key pattern: `async with` for lifecycle

Always manage transport and session via `async with` (or `AsyncExitStack` as
above). Skipping this leaks connections and causes teardown deadlocks.

## Calling tools

```python
result = await self.session.call_tool(tool_name, tool_args)
# result.content is list[TextContent | ImageContent | ...]
```

## Wiring tool results back to Claude

```python
from anthropic import Anthropic

anthropic = Anthropic()
messages = [{"role": "user", "content": query}]

# Get tools from MCP
response = await self.session.list_tools()
available_tools = [
    {"name": t.name, "description": t.description, "input_schema": t.inputSchema}
    for t in response.tools
]

# First Claude call
claude_resp = anthropic.messages.create(
    model="claude-sonnet-4-20250514",
    max_tokens=1000,
    messages=messages,
    tools=available_tools,
)

# Handle tool use
for content in claude_resp.content:
    if content.type == "tool_use":
        mcp_result = await self.session.call_tool(content.name, content.input)
        # Append tool result and get Claude's final response
        messages.append({"role": "assistant", "content": claude_resp.content})
        messages.append({
            "role": "user",
            "content": [{"type": "tool_result",
                         "tool_use_id": content.id,
                         "content": mcp_result.content}]
        })
        follow_up = anthropic.messages.create(
            model="claude-sonnet-4-20250514", max_tokens=1000, messages=messages
        )
```

## Running

```bash
uv run client.py path/to/server.py
```

## Best practices

- **Error handling**: wrap tool calls in try/except; gracefully handle connection failures
- **Resource management**: use `AsyncExitStack` or `async with` — not bare `ClientSession` creation
- **Security**: store API keys in `.env`, never in source; validate server responses
- **Tool names**: names may contain alphanumerics, hyphens, underscores — validate against spec if needed

## High-level `Client` (v1 stable)

The SDK also provides a higher-level `Client` that wraps `ClientSession` and
handles in-memory transport pairing with a `Server` or `MCPServer`:

```python
from mcp.client import Client

async with Client(server_instance) as client:
    result = await client.call_tool("my_tool", {"x": 1})
```

This is the recommended approach for testing (see `references/testing.md`).
For production HTTP connections, use `streamable_http_client` + `ClientSession`.
