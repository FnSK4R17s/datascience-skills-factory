# Build a Client — End-to-End Tutorial

Sources: `docs/mcpio__docs__develop__build-client.md`, `docs/README.md`

This file covers building a complete LLM-powered chatbot client that connects
to MCP servers, with full examples for both stdio and HTTP transports.

## Project setup

```bash
uv init mcp-client
cd mcp-client
uv add mcp anthropic python-dotenv

# Or with pip:
pip install mcp anthropic python-dotenv
```

Create a `.env` file:
```bash
echo "ANTHROPIC_API_KEY=your-api-key-here" > .env
echo ".env" >> .gitignore
```

## Simple stdio client

Connect to any stdio MCP server and list its tools:

```python
"""Simple MCP client that lists tools from a stdio server."""

import asyncio
from mcp import ClientSession, StdioServerParameters
from mcp.client.stdio import stdio_client


async def main():
    params = StdioServerParameters(
        command="python",
        args=["server.py"],
        # Optional: env vars to pass to the server
        env={"WEATHER_API_KEY": "..."},
    )

    async with stdio_client(params) as (read, write):
        async with ClientSession(read, write) as session:
            await session.initialize()

            # Discover what the server offers
            tools = await session.list_tools()
            print(f"Tools: {[t.name for t in tools.tools]}")

            resources = await session.list_resources()
            print(f"Resources: {[str(r.uri) for r in resources.resources]}")

            prompts = await session.list_prompts()
            print(f"Prompts: {[p.name for p in prompts.prompts]}")

            # Call a tool
            result = await session.call_tool("get_forecast", {"city": "London"})
            if not result.isError:
                print(f"Forecast: {result.content[0].text}")
            else:
                print(f"Error: {result.content[0].text}")

            # Read a resource
            resource = await session.read_resource("weather://forecast/cities")
            print(f"Available cities: {resource.contents[0].text}")


asyncio.run(main())
```

## Complete LLM-powered chatbot client

Full implementation that connects MCP tools to Claude:

```python
"""MCP chatbot client powered by Claude."""

import asyncio
import sys
from contextlib import AsyncExitStack
from typing import Optional

from anthropic import Anthropic
from dotenv import load_dotenv
from mcp import ClientSession, StdioServerParameters, types
from mcp.client.stdio import stdio_client

load_dotenv()


class MCPClient:
    def __init__(self):
        self.session: Optional[ClientSession] = None
        self.exit_stack = AsyncExitStack()
        self.anthropic = Anthropic()

    async def connect_to_server(self, server_script_path: str):
        """Connect to an MCP server via stdio."""
        is_python = server_script_path.endswith(".py")
        is_js = server_script_path.endswith(".js")
        if not (is_python or is_js):
            raise ValueError("Server script must be a .py or .js file")

        command = "python" if is_python else "node"
        server_params = StdioServerParameters(
            command=command,
            args=[server_script_path],
            env=None,
        )

        stdio_transport = await self.exit_stack.enter_async_context(
            stdio_client(server_params)
        )
        self.stdio, self.write = stdio_transport
        self.session = await self.exit_stack.enter_async_context(
            ClientSession(self.stdio, self.write)
        )

        await self.session.initialize()

        response = await self.session.list_tools()
        tools = response.tools
        print(f"\nConnected to server with tools: {[t.name for t in tools]}")

    async def process_query(self, query: str) -> str:
        """Process a user query using Claude and available MCP tools."""
        messages = [{"role": "user", "content": query}]

        # Get current tool list from server
        response = await self.session.list_tools()
        available_tools = [
            {
                "name": tool.name,
                "description": tool.description,
                "input_schema": tool.inputSchema,
            }
            for tool in response.tools
        ]

        # Initial Claude call
        response = self.anthropic.messages.create(
            model="claude-sonnet-4-20250514",
            max_tokens=1000,
            messages=messages,
            tools=available_tools,
        )

        final_text = []
        assistant_message_content = []

        for content in response.content:
            if content.type == "text":
                final_text.append(content.text)
                assistant_message_content.append(content)

            elif content.type == "tool_use":
                tool_name = content.name
                tool_args = content.input

                # Execute tool via MCP
                result = await self.session.call_tool(tool_name, tool_args)
                final_text.append(f"[Calling tool {tool_name} with args {tool_args}]")

                # Add tool result to conversation
                assistant_message_content.append(content)
                messages.append({
                    "role": "assistant",
                    "content": assistant_message_content,
                })
                messages.append({
                    "role": "user",
                    "content": [
                        {
                            "type": "tool_result",
                            "tool_use_id": content.id,
                            "content": result.content,
                        }
                    ],
                })

                # Get Claude's response to the tool result
                response = self.anthropic.messages.create(
                    model="claude-sonnet-4-20250514",
                    max_tokens=1000,
                    messages=messages,
                    tools=available_tools,
                )

                if response.content and response.content[0].type == "text":
                    final_text.append(response.content[0].text)

        return "\n".join(final_text)

    async def chat_loop(self):
        """Run an interactive chat loop."""
        print("\nMCP Client Started!")
        print("Type your queries or 'quit' to exit.\n")

        while True:
            try:
                query = input("Query: ").strip()
                if query.lower() == "quit":
                    break
                if not query:
                    continue

                response = await self.process_query(query)
                print(f"\n{response}\n")

            except KeyboardInterrupt:
                break
            except Exception as e:
                print(f"\nError: {e}\n")

    async def cleanup(self):
        """Clean up resources."""
        await self.exit_stack.aclose()


async def main():
    if len(sys.argv) < 2:
        print("Usage: python client.py <path_to_server_script>")
        sys.exit(1)

    client = MCPClient()
    try:
        await client.connect_to_server(sys.argv[1])
        await client.chat_loop()
    finally:
        await client.cleanup()


if __name__ == "__main__":
    asyncio.run(main())
```

Run:
```bash
uv run client.py path/to/server.py
# or for a Node.js server:
uv run client.py path/to/build/index.js
```

## Connecting to an HTTP server

```python
"""Client for an HTTP MCP server."""

import asyncio
import httpx
from mcp import ClientSession
from mcp.client.streamable_http import streamable_http_client


async def main():
    # Optionally pass auth headers, timeouts, etc.
    http_client = httpx.AsyncClient(
        headers={"Authorization": "Bearer my-token"},
        timeout=httpx.Timeout(30, read=300),
        follow_redirects=True,
    )

    async with http_client:
        async with streamable_http_client(
            "http://localhost:8000/mcp",
            http_client=http_client,
        ) as (read, write):
            async with ClientSession(read, write) as session:
                await session.initialize()

                tools = await session.list_tools()
                print("Tools:", [t.name for t in tools.tools])

                result = await session.call_tool("greet", {"name": "World"})
                print("Result:", result.content[0].text)


asyncio.run(main())
```

## Client with sampling callback

When the server may make LLM sampling requests, provide a callback:

```python
from mcp.shared.context import RequestContext

async def handle_sampling(
    context: RequestContext,
    params: types.CreateMessageRequestParams,
) -> types.CreateMessageResult:
    """Handle LLM sampling requests from the server."""
    # In production: call your LLM with params.messages and params.maxTokens
    # Always show the request to the user for approval in high-trust settings
    print(f"Server requests LLM sampling: {params.messages[-1].content.text[:100]}...")

    # For demo, return a mock response
    return types.CreateMessageResult(
        role="assistant",
        content=types.TextContent(type="text", text="Mock LLM response"),
        model="claude-sonnet-4-20250514",
        stopReason="endTurn",
    )

async with ClientSession(
    read, write,
    sampling_callback=handle_sampling,
) as session:
    await session.initialize()
    # Now tools that call ctx.session.create_message() will work
```

## Paginating large result sets

```python
from mcp.types import PaginatedRequestParams

async def list_all_resources(session: ClientSession) -> list:
    """Fetch all resources using cursor-based pagination."""
    all_resources = []
    cursor = None

    while True:
        if cursor:
            result = await session.list_resources(
                params=PaginatedRequestParams(cursor=cursor)
            )
        else:
            result = await session.list_resources()

        all_resources.extend(result.resources)
        print(f"Fetched page: {len(result.resources)} resources")

        if result.nextCursor:
            cursor = result.nextCursor
        else:
            break

    print(f"Total resources: {len(all_resources)}")
    return all_resources
```

## Getting completions (autocomplete)

```python
from mcp.types import ResourceTemplateReference, PromptReference

async def get_city_suggestions(session: ClientSession, partial: str) -> list[str]:
    """Get autocomplete suggestions for a city name."""
    result = await session.complete(
        ref=ResourceTemplateReference(
            type="ref/resource",
            uri="weather://{city}",
        ),
        argument={"name": "city", "value": partial},
    )
    return result.completion.values

# Usage:
suggestions = await get_city_suggestions(session, "lon")
print(suggestions)  # ["London", "Long Beach", "Long Island"]
```

## Error handling patterns

```python
from mcp.shared.exceptions import MCPError  # v2; v1: McpError

async def safe_tool_call(session: ClientSession, tool: str, args: dict) -> str:
    """Call a tool with full error handling."""
    try:
        result = await session.call_tool(tool, args)
    except MCPError as e:
        return f"Protocol error: {e.error.code} — {e.error.message}"
    except Exception as e:
        return f"Connection error: {e}"

    if result.isError:
        error_text = " ".join(
            block.text for block in result.content
            if isinstance(block, types.TextContent)
        )
        return f"Tool error: {error_text}"

    output = []
    for block in result.content:
        if isinstance(block, types.TextContent):
            output.append(block.text)
        elif isinstance(block, types.ImageContent):
            output.append(f"[Image: {block.mimeType}]")

    return "\n".join(output)
```

## Discovering server capabilities

```python
async def inspect_server(session: ClientSession) -> None:
    """Print a full report of what the server offers."""
    # v1: caps = session.get_server_capabilities()
    # v2:
    init_result = session.initialize_result
    caps = init_result.capabilities if init_result else None

    print("=== Server Info ===")
    if init_result:
        print(f"  Name: {init_result.serverInfo.name if init_result.serverInfo else 'unknown'}")
        print(f"  Instructions: {init_result.instructions or 'none'}")
    print(f"  Has tools: {caps.tools is not None if caps else False}")
    print(f"  Has resources: {caps.resources is not None if caps else False}")
    print(f"  Has prompts: {caps.prompts is not None if caps else False}")

    print("\n=== Tools ===")
    tools = await session.list_tools()
    for tool in tools.tools:
        print(f"  {tool.name}: {tool.description}")

    print("\n=== Resources ===")
    resources = await session.list_resources()
    for resource in resources.resources:
        print(f"  {resource.uri}: {resource.name}")

    templates = await session.list_resource_templates()
    for template in templates.resourceTemplates:
        print(f"  Template: {template.uriTemplate}: {template.name}")

    print("\n=== Prompts ===")
    prompts = await session.list_prompts()
    for prompt in prompts.prompts:
        print(f"  {prompt.name}: {prompt.description}")
```

## Running the client

```bash
# Against a Python server
uv run client.py path/to/server.py

# Against a Node.js server
uv run client.py path/to/build/index.js

# Against the weather server from the tutorial
python client.py ../weather-server/server.py
```

## Troubleshooting

### `FileNotFoundError`

The server script path is wrong. Use the absolute path:
```bash
python client.py /absolute/path/to/server.py
```

### `Connection refused`

The server is not running (for HTTP clients) or the server script crashed on
startup. Run the server script directly to check for import errors:
```bash
python server.py
```

### `Tool execution failed`

The server is missing environment variables. Check the server's env requirements
and pass them via `StdioServerParameters(env={"KEY": "value"})`.

### First response slow (up to 30 seconds)

Normal for stdio servers: the server initializes, Python imports load, and
Claude processes the query. Subsequent responses are faster.

### Tool name validation

Tool names can contain alphanumerics, hyphens (`-`), and underscores (`_`).
No spaces or special characters.
