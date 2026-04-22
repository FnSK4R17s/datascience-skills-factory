# MCP Server Concepts

An MCP server exposes three kinds of primitives: **tools**, **resources**, and
**prompts**. Each primitive type maps to a distinct wire-protocol namespace.
A server declares which primitives it supports at initialization; the client
uses that declaration to know what it can request.

## Primitives

### Tools

Tools are callable units — functions the LLM (or host application) can invoke.
They follow a request/response model and return structured content. Each tool
has a name, a description (shown to the LLM), and an input schema (JSON Schema).

Key design constraints:
- Tool names must be unique within a server.
- Input schemas must be valid JSON Schema; the SDK validates inputs against
  the schema before invoking handlers.
- Tool results can be text, images, embedded resources, or error content.
- Tools may be annotated as read-only or destructive; clients use these hints
  for permission UI (not enforcement).

### Resources

Resources represent data the server exposes for the LLM to read — files,
database rows, API responses. Resources are identified by URI. A server can
expose static resources (fixed URIs) or templates (URI patterns with
parameters).

Key design constraints:
- Resources are read-only from the protocol's perspective; mutation goes
  through tools.
- A server can emit `resources/list_changed` notifications to signal that
  the resource list has changed.
- Resource content can be text or binary (base64-encoded).
- Resource templates follow RFC 6570 URI template syntax.

### Prompts

Prompts are named, parameterized message templates the server exposes. The
client requests a prompt by name and arguments; the server returns a list of
messages suitable for injecting into an LLM conversation.

Key design constraints:
- Prompt arguments may be required or optional.
- Prompts are different from resources: they return `messages`, not raw content.
- A server emits `prompts/list_changed` when the prompt catalog changes.

## Capabilities

Capabilities are declared during the `initialize` handshake. A server that
does not declare a capability will not receive requests for it.

Capability keys used by the SDK:

| Key | Enables |
|-----|---------|
| `tools` | `tools/list`, `tools/call` |
| `resources` | `resources/list`, `resources/read`, `resources/templates/list` |
| `resources.subscribe` | `resources/subscribe`, `resources/unsubscribe` |
| `prompts` | `prompts/list`, `prompts/get` |
| `logging` | `logging/setLevel`, log notifications |
| `experimental` | experimental extensions (e.g. tasks) |

FastMCP infers capabilities from registered handlers. The low-level `Server`
class requires explicit declaration.

## Lifecycle

```
client                            server
  |  initialize(clientInfo, caps) -->  |
  |  <-- initialize_result(caps)       |
  |  initialized -->                   |   <-- operation phase begins
  |                                    |
  |  ... operation messages ...        |
  |                                    |
  |  close / transport EOF             |   <-- cleanup
```

The server MUST NOT send any operation responses before it receives
`initialized`. The server SHOULD perform resource cleanup (close DB connections,
flush buffers) when the transport signals EOF or when `close` is called.

## Error handling

MCP defines a JSON-RPC error response shape. SDK conventions:

- Raise `McpError` with an appropriate `ErrorCode` from handler code.
- `ErrorCode.MethodNotFound` — requested primitive doesn't exist.
- `ErrorCode.InvalidParams` — input validation failure.
- `ErrorCode.InternalError` — unexpected exception in handler.

Unhandled exceptions in FastMCP handlers are automatically wrapped in
`InternalError` responses. In the low-level server, you must catch and
re-raise as `McpError` yourself, or the transport layer will return a
generic error.

## Resource subscriptions

A server that declares `resources.subscribe` lets clients subscribe to
individual resource URIs. The server then sends `resources/updated`
notifications when a subscribed resource changes. The update notification
carries only the URI, not the new content — clients must re-read.

## Logging

Servers can emit log messages to the client via the `logging/message`
notification. Clients that declared the `logging` capability in their init
will receive these. Use the `Context` object in FastMCP (`ctx.info()`,
`ctx.warning()`, etc.) rather than writing to stdout — stdout is the
transport channel for stdio servers.

## Completions

Servers can offer argument completion hints for prompt arguments and resource
template parameters via the `completion/complete` request. Useful for building
interactive UIs on top of MCP.
