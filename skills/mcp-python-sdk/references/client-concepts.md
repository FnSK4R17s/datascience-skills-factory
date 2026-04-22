# MCP Client Concepts

An MCP client opens a session with a server, discovers its primitives, and
calls them on behalf of a host application (typically an LLM orchestration
layer). The Python SDK `ClientSession` handles the protocol state machine;
the transport delivers bytes.

## Session lifecycle

All client operations require an active, initialized session:

```python
from mcp import ClientSession
from mcp.client.stdio import stdio_client

async with stdio_client(server_params) as (read, write):
    async with ClientSession(read, write) as session:
        await session.initialize()
        # session is now in operation phase
        result = await session.call_tool("my_tool", {"arg": "value"})
```

`ClientSession` is an async context manager. Exiting the context sends a
`close` notification and tears down the session cleanly. The outer context
manager (`stdio_client` or the HTTP equivalent) manages the transport.

**Do not** share a `ClientSession` across concurrent tasks without external
serialization — the session's internal state is not thread/task-safe.

## Discovering primitives

After `initialize()`, call the list methods to discover what the server exposes:

```python
# List available tools
tools_result = await session.list_tools()
for tool in tools_result.tools:
    print(tool.name, tool.description, tool.inputSchema)

# List resources
resources_result = await session.list_resources()

# List resource templates
templates_result = await session.list_resource_templates()

# List prompts
prompts_result = await session.list_prompts()
```

Only call list methods for capability types the server declared during
`initialize`. Calling `list_tools()` on a server that didn't declare the
`tools` capability raises a `CapabilityError`.

## Calling tools

```python
result = await session.call_tool("tool_name", arguments={"key": "value"})
for content in result.content:
    if content.type == "text":
        print(content.text)
    elif content.type == "image":
        # content.data is base64-encoded
        pass
    elif content.type == "resource":
        # content.resource is an embedded resource
        pass

if result.isError:
    # Tool returned an error result (not a protocol error)
    handle_tool_error(result)
```

Tool results use `isError` rather than raising an exception when the tool
itself signals failure. Protocol-level errors (invalid params, method not
found) raise `McpError`.

## Reading resources

```python
resource_result = await session.read_resource("resource://my-server/data")
for content in resource_result.contents:
    if content.type == "text":
        print(content.text)
    elif content.type == "blob":
        # content.blob is base64-encoded binary
        pass
```

Resource URIs are server-defined. Discover the available URIs via
`list_resources()` and `list_resource_templates()` first.

## Getting prompts

```python
prompt_result = await session.get_prompt(
    "prompt_name",
    arguments={"topic": "async Python"}
)
for message in prompt_result.messages:
    print(message.role, message.content)
```

Inject the returned `messages` list directly into an LLM API call.

## Resource subscriptions

```python
await session.subscribe_resource("resource://my-server/live-data")
# The session will now receive resources/updated notifications for this URI
# Unsubscribe when done:
await session.unsubscribe_resource("resource://my-server/live-data")
```

The SDK delivers update notifications via a callback registered with the
session. See the notification handler pattern in the SDK docs.

## Sampling (client-side LLM calls)

The MCP protocol defines a `sampling/createMessage` request that a server can
send to the client, asking the client to run an LLM call and return the result.
This enables server-side agentic patterns where the server orchestrates LLM
calls through the client.

To support sampling, register a handler before `initialize()`:

```python
async def handle_sampling(request):
    # request.params has messages, modelPreferences, maxTokens, etc.
    # Call your LLM here and return a CreateMessageResult
    ...

session = ClientSession(read, write, sampling_callback=handle_sampling)
```

The client must declare the `sampling` capability for the server to send
sampling requests. The SDK includes this in the default capability set if
a sampling callback is provided.

## Pagination

`list_tools()`, `list_resources()`, and `list_prompts()` support cursor-based
pagination for servers with large catalogs. Check `result.nextCursor` and
pass it back as `cursor=` to fetch subsequent pages.

## Elicitation

The MCP 2025-11-25 spec adds an `elicitation/create` request — a server asking
the client to prompt the human for input during a tool call. Register an
elicitation callback on the session similar to the sampling callback pattern.
This is marked experimental in some SDK versions; check the SDK changelog before
relying on it.

## Common errors

| Error | Cause | Fix |
|-------|-------|-----|
| `CapabilityError` | Called a list/call method the server didn't declare | Check `session.server_capabilities` before calling |
| `McpError(MethodNotFound)` | Tool/resource/prompt name doesn't exist | Call the list method first to verify |
| `McpError(InvalidParams)` | Arguments don't match the tool's input schema | Inspect `tool.inputSchema` |
| Session deadlock on test teardown | `ClientSession` not exited via `async with` | Always use `async with ClientSession(...)` |
