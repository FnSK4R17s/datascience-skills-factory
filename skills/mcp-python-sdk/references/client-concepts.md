# Client Concepts

Sources: `docs/mcpio__docs__learn__client-concepts.md`,
`docs/mcpio__docs__develop__build-client.md`,
`docs/README.md`,
`docs/mcpio__specification__2025-11-25__client__sampling.md`,
`docs/mcpio__specification__2025-11-25__client__roots.md`,
`docs/mcpio__specification__2025-11-25__client__elicitation.md`,
`docs/migration.md`

## Host vs client

The **host** is the application users interact with (Claude.ai, an IDE, a
custom app). The **client** is the protocol-level component: one client per
server connection. The host manages multiple clients.

## Sessions — the core pattern

A session covers one connected client-server pair. Always use async context
managers — skipping `async with` leaks connections and deadlocks test teardown.

### Connecting to a stdio server

```python
import asyncio
from mcp import ClientSession, StdioServerParameters
from mcp.client.stdio import stdio_client

async def run():
    params = StdioServerParameters(
        command="python",
        args=["server.py"],
        env={"API_KEY": "my-key"},  # optional env vars
    )
    async with stdio_client(params) as (read, write):
        async with ClientSession(read, write) as session:
            await session.initialize()

            # List what the server offers
            tools = await session.list_tools()
            print("Tools:", [t.name for t in tools.tools])

            resources = await session.list_resources()
            print("Resources:", [r.uri for r in resources.resources])

            prompts = await session.list_prompts()
            print("Prompts:", [p.name for p in prompts.prompts])

asyncio.run(run())
```

### Connecting to an HTTP server

```python
import httpx
from mcp import ClientSession
from mcp.client.streamable_http import streamable_http_client

async def run():
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
```

**Note (v1 vs v2):** In v1, the function was `streamablehttp_client` (camelCase)
and returned a 3-tuple `(read, write, get_session_id)`. In v2, it's
`streamable_http_client` (snake_case) and returns a 2-tuple `(read, write)`.
Configure all HTTP settings (headers, timeout, auth) on the `httpx.AsyncClient`.

### Managing long-lived connections with AsyncExitStack

```python
from contextlib import AsyncExitStack
from typing import Optional

class MCPClient:
    def __init__(self):
        self.session: Optional[ClientSession] = None
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
        print("Connected. Tools:", [t.name for t in tools.tools])

    async def cleanup(self):
        await self.exit_stack.aclose()
```

## Discovery

After `initialize()`, discover what the server exposes:

```python
# List operations — all return objects with list fields
tools = await session.list_tools()         # .tools: list[Tool]
resources = await session.list_resources() # .resources: list[Resource]
templates = await session.list_resource_templates() # .resourceTemplates
prompts = await session.list_prompts()     # .prompts: list[Prompt]

# Inspect a tool's schema
for tool in tools.tools:
    print(f"Tool: {tool.name}")
    print(f"  Description: {tool.description}")
    print(f"  Schema: {tool.inputSchema}")   # v1
    # print(f"  Schema: {tool.input_schema}")  # v2 snake_case

# Get server capabilities from initialization
# v1: caps = session.get_server_capabilities()
# v2: caps = session.initialize_result.capabilities
```

## Calling tools

```python
result = await session.call_tool("tool_name", {"param": "value"})

# Check for errors first
if result.isError:  # v1; v2: result.is_error
    print("Tool failed:", result.content[0].text)
else:
    # content is a list of content blocks
    for block in result.content:
        if block.type == "text":
            print("Text:", block.text)
        elif block.type == "image":
            print("Image:", block.mimeType, len(block.data), "bytes")
        elif block.type == "resource":
            print("Resource:", block.resource.uri)

    # Structured content (if tool provides outputSchema)
    if result.structuredContent:  # v1; v2: structured_content
        print("Structured:", result.structuredContent)
```

### Parsing different content types

```python
from mcp import types

result = await session.call_tool("get_data", {"format": "text"})
for content in result.content:
    if isinstance(content, types.TextContent):
        print(f"Text: {content.text}")
    elif isinstance(content, types.ImageContent):
        print(f"Image ({content.mimeType}): {len(content.data)} bytes")
    elif isinstance(content, types.EmbeddedResource):
        resource = content.resource
        if isinstance(resource, types.TextResourceContents):
            print(f"Resource {resource.uri}: {resource.text}")
        elif isinstance(resource, types.BlobResourceContents):
            print(f"Binary resource {resource.uri}")
```

## Reading resources

```python
# Read by URI — returns ResourceContents
resource = await session.read_resource("file:///path/to/file")
# v1: accepts AnyUrl or string
# v2: accepts plain string only

for content in resource.contents:
    if isinstance(content, types.TextResourceContents):
        print(f"Text from {content.uri}: {content.text}")
    elif isinstance(content, types.BlobResourceContents):
        # blob is base64-encoded
        import base64
        data = base64.b64decode(content.blob)
        print(f"Binary from {content.uri}: {len(data)} bytes")
```

## Invoking prompts

```python
prompt = await session.get_prompt("prompt_name", {"arg": "value"})

for message in prompt.messages:
    print(f"{message.role}: {message.content}")
    # message.content is TextContent, ImageContent, or EmbeddedResource
```

## Argument completion

```python
from mcp.types import PromptReference, ResourceTemplateReference

# Get completions for a resource template argument
result = await session.complete(
    ref=ResourceTemplateReference(
        type="ref/resource",
        uri="weather://{city}",
    ),
    argument={"name": "city", "value": "lon"},
    context_arguments={"country": "UK"},  # previously resolved arguments
)
print("Suggestions:", result.completion.values)  # e.g. ["London", "Long Beach"]

# Get completions for a prompt argument
result = await session.complete(
    ref=PromptReference(type="ref/prompt", name="greet_user"),
    argument={"name": "style", "value": ""},
)
print("Style options:", result.completion.values)
```

## Display utilities

The SDK provides utilities for showing human-readable names in UIs:

```python
from mcp.shared.metadata_utils import get_display_name

# Precedence: title > annotations.title > name (for tools)
# Precedence: title > name (for other objects)
for tool in tools_response.tools:
    display_name = get_display_name(tool)
    print(f"Tool: {display_name}")
    if tool.description:
        print(f"   {tool.description}")

for resource in resources_response.resources:
    display_name = get_display_name(resource)
    print(f"Resource: {display_name} ({resource.uri})")
```

## Sampling (client-side feature)

Sampling allows a **server** to request LLM completions through the client.
The client controls user approval and model access. The client must declare
`sampling` capability and provide a callback.

```python
from mcp.shared.context import RequestContext

async def handle_sampling_message(
    context: RequestContext,
    params: types.CreateMessageRequestParams,
) -> types.CreateMessageResult:
    """Called when the server requests an LLM completion."""
    # Show the request to the user for approval in production
    print(f"Server requests LLM completion: {params.messages}")

    # Call your LLM here
    return types.CreateMessageResult(
        role="assistant",
        content=types.TextContent(
            type="text",
            text="Response from LLM",
        ),
        model="claude-sonnet-4-20250514",
        stopReason="endTurn",
    )

# Register the callback when creating the session
async with ClientSession(
    read,
    write,
    sampling_callback=handle_sampling_message,
) as session:
    await session.initialize()
```

## Elicitation (client-side feature)

Servers can request structured user input mid-operation. The client presents
UI and validates the response.

```python
from mcp.types import ElicitResult

async def handle_elicitation(context, params) -> ElicitResult:
    """Called when the server needs structured input from the user."""
    # Present params.message and params.requestedSchema to the user
    print(f"Server asks: {params.message}")
    print(f"Schema: {params.requestedSchema}")

    # In production, show a form to the user. Here we auto-accept:
    return ElicitResult(
        action="accept",
        content={"confirm": True, "date": "2024-12-26"},
    )

# Or to decline
return ElicitResult(action="decline")

# Register as session callback
async with ClientSession(
    read,
    write,
    elicitation_callback=handle_elicitation,
) as session:
    await session.initialize()
```

Privacy rule: elicitation must never request passwords or API keys. Warn users
about suspicious requests.

## Roots

Roots let clients tell servers which filesystem directories are in scope.
They are advisory (not a security boundary). OS-level permissions enforce
actual access.

```python
# Roots are declared as client capabilities during initialization
# The SDK manages this; application code sets the root list
# Servers receive roots/list_changed notifications when the list changes
```

## Pagination

```python
from mcp.types import PaginatedRequestParams

# Paginate through all tools
all_tools = []
cursor = None

while True:
    if cursor:
        result = await session.list_tools(params=PaginatedRequestParams(cursor=cursor))
    else:
        result = await session.list_tools()

    all_tools.extend(result.tools)

    if result.nextCursor:  # v1; v2: next_cursor
        cursor = result.nextCursor
    else:
        break
```

## Error handling

```python
from mcp.shared.exceptions import MCPError  # v2; v1: McpError

try:
    result = await session.call_tool("my_tool", {"arg": "value"})
    if result.isError:
        print("Tool execution error:", result.content[0].text)
except MCPError as e:
    print(f"Protocol error {e.error.code}: {e.error.message}")
except Exception as e:
    print(f"Connection error: {e}")
```

Common errors:
- `FileNotFoundError` — server script path is wrong
- `Connection refused` — server not running
- `Tool execution failed` — missing env vars on server side
- `-32602 Invalid params` — capability mismatch (e.g., server sent sampling
  to a client that didn't declare the capability)

## Building a full LLM-powered client with Anthropic

```python
import asyncio
import sys
from contextlib import AsyncExitStack

from anthropic import Anthropic
from mcp import ClientSession, StdioServerParameters, types
from mcp.client.stdio import stdio_client

class MCPClient:
    def __init__(self):
        self.session: ClientSession | None = None
        self.exit_stack = AsyncExitStack()
        self.anthropic = Anthropic()

    async def connect(self, server_script_path: str):
        command = "python" if server_script_path.endswith(".py") else "node"
        params = StdioServerParameters(command=command, args=[server_script_path])

        transport = await self.exit_stack.enter_async_context(stdio_client(params))
        self.session = await self.exit_stack.enter_async_context(
            ClientSession(*transport)
        )
        await self.session.initialize()

        tools = await self.session.list_tools()
        print("Connected. Tools:", [t.name for t in tools.tools])

    async def process_query(self, query: str) -> str:
        messages = [{"role": "user", "content": query}]

        # Get available tools from server
        response = await self.session.list_tools()
        available_tools = [
            {
                "name": t.name,
                "description": t.description,
                "input_schema": t.inputSchema,
            }
            for t in response.tools
        ]

        # Initial Claude call
        claude_resp = self.anthropic.messages.create(
            model="claude-sonnet-4-20250514",
            max_tokens=1000,
            messages=messages,
            tools=available_tools,
        )

        final_text = []
        assistant_content = []

        for content in claude_resp.content:
            if content.type == "text":
                final_text.append(content.text)
                assistant_content.append(content)
            elif content.type == "tool_use":
                # Execute the tool call through MCP
                mcp_result = await self.session.call_tool(
                    content.name,
                    content.input,
                )
                final_text.append(f"[Called {content.name}]")

                # Build tool result message for Claude
                assistant_content.append(content)
                messages.append({"role": "assistant", "content": assistant_content})
                messages.append({
                    "role": "user",
                    "content": [{
                        "type": "tool_result",
                        "tool_use_id": content.id,
                        "content": mcp_result.content,
                    }],
                })

                # Get Claude's follow-up response
                follow_up = self.anthropic.messages.create(
                    model="claude-sonnet-4-20250514",
                    max_tokens=1000,
                    messages=messages,
                    tools=available_tools,
                )
                if follow_up.content and follow_up.content[0].type == "text":
                    final_text.append(follow_up.content[0].text)

        return "\n".join(final_text)

    async def chat_loop(self):
        print("MCP Client Started. Type 'quit' to exit.")
        while True:
            try:
                query = input("\nQuery: ").strip()
                if query.lower() == "quit":
                    break
                response = await self.process_query(query)
                print("\n" + response)
            except Exception as e:
                print(f"\nError: {e}")

    async def cleanup(self):
        await self.exit_stack.aclose()


async def main():
    if len(sys.argv) < 2:
        print("Usage: python client.py <path_to_server_script>")
        sys.exit(1)

    client = MCPClient()
    try:
        await client.connect(sys.argv[1])
        await client.chat_loop()
    finally:
        await client.cleanup()


if __name__ == "__main__":
    asyncio.run(main())
```

## OAuth client — connecting to protected servers

```python
import asyncio
from urllib.parse import parse_qs, urlparse

import httpx
from pydantic import AnyUrl

from mcp import ClientSession
from mcp.client.auth import OAuthClientProvider, TokenStorage
from mcp.client.streamable_http import streamable_http_client
from mcp.shared.auth import OAuthClientInformationFull, OAuthClientMetadata, OAuthToken


class InMemoryTokenStorage(TokenStorage):
    """Simple in-memory token storage for demos. Use persistent storage in production."""

    def __init__(self):
        self.tokens: OAuthToken | None = None
        self.client_info: OAuthClientInformationFull | None = None

    async def get_tokens(self) -> OAuthToken | None:
        return self.tokens

    async def set_tokens(self, tokens: OAuthToken) -> None:
        self.tokens = tokens

    async def get_client_info(self) -> OAuthClientInformationFull | None:
        return self.client_info

    async def set_client_info(self, client_info: OAuthClientInformationFull) -> None:
        self.client_info = client_info


async def handle_redirect(auth_url: str) -> None:
    print(f"Visit this URL to authorize: {auth_url}")


async def handle_callback() -> tuple[str, str | None]:
    callback_url = input("Paste the callback URL: ")
    params = parse_qs(urlparse(callback_url).query)
    return params["code"][0], params.get("state", [None])[0]


async def main():
    oauth_auth = OAuthClientProvider(
        server_url="http://localhost:8001",
        client_metadata=OAuthClientMetadata(
            client_name="My MCP Client",
            redirect_uris=[AnyUrl("http://localhost:3000/callback")],
            grant_types=["authorization_code", "refresh_token"],
            response_types=["code"],
            scope="read write",
        ),
        storage=InMemoryTokenStorage(),
        redirect_handler=handle_redirect,
        callback_handler=handle_callback,
    )

    async with httpx.AsyncClient(auth=oauth_auth, follow_redirects=True) as http_client:
        async with streamable_http_client(
            "http://localhost:8001/mcp",
            http_client=http_client,
        ) as (read, write):
            async with ClientSession(read, write) as session:
                await session.initialize()
                tools = await session.list_tools()
                print("Tools:", [t.name for t in tools.tools])


asyncio.run(main())
```

## v1 → v2 client API changes

Key renames that cause silent failures at runtime:

| v1 | v2 |
|----|----|
| `result.isError` | `result.is_error` |
| `result.structuredContent` | `result.structured_content` |
| `tools.nextCursor` | `tools.next_cursor` |
| `tool.inputSchema` | `tool.input_schema` |
| `session.list_tools(cursor=...)` | `session.list_tools(params=PaginatedRequestParams(cursor=...))` |
| `session.get_server_capabilities()` | `session.initialize_result.capabilities` |
| `McpError` | `MCPError` (from `mcp.shared.exceptions` or top-level `mcp`) |
| `McpError(ErrorData(...))` | `MCPError(code, message)` |
| `streamablehttp_client` | `streamable_http_client` |
| 3-tuple from `streamablehttp_client` | 2-tuple `(read, write)` from `streamable_http_client` |
| `client.server_capabilities` | `client.initialize_result.capabilities` |

Old camelCase names still work as constructor kwargs (Pydantic `populate_by_name=True`),
but Python attribute access must use snake_case.
