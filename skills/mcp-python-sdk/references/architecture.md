# Architecture

Sources: `docs/mcpio__docs__learn__architecture.md`,
`docs/mcpio__specification__2025-11-25__architecture__index.md`,
`docs/mcpio__docs__learn__server-concepts.md`,
`docs/mcpio__docs__learn__client-concepts.md`

## Participants

MCP uses a **client-host-server** model:

- **MCP Host**: The AI application (e.g. Claude Desktop, Claude Code, an IDE,
  a custom app). Manages one or more MCP clients. Enforces security, consent,
  and coordinates with the LLM.
- **MCP Client**: A protocol-level component instantiated by the host. Each
  client maintains a dedicated 1:1 connection with one MCP server. In the
  Python SDK, `ClientSession` is the client.
- **MCP Server**: A program that exposes tools, resources, and prompts. Can
  run locally (same machine via stdio) or remotely (HTTP).

A single host can connect to many servers simultaneously via multiple clients:

```
Host (Claude Desktop, Claude Code, custom app)
 ├─ Client 1  ──── Server A (local, stdio, "weather-server")
 ├─ Client 2  ──── Server B (local, stdio, "filesystem-server")
 └─ Client 3  ──── Server C (remote, Streamable HTTP, "search-api")
```

Local servers run as subprocesses; remote servers are network services.

## Two layers

### Data layer — JSON-RPC 2.0 message semantics

- Lifecycle management (initialize, capability negotiation, shutdown)
- Server features: tools, resources, prompts
- Client features: sampling, elicitation, logging
- Utility features: progress, cancellation, notifications, tasks

### Transport layer — communication channel

- stdio for local processes
- Streamable HTTP for remote servers (replaces old HTTP+SSE)

The data layer is transport-agnostic. Same JSON-RPC messages regardless of
transport. You can test with in-process memory streams and deploy over HTTP
without changing server logic.

## Stateful sessions

MCP is a stateful protocol. Each connection goes through:

1. **Initialization**: `initialize` request → `initialize` response →
   `notifications/initialized` notification. Capabilities are exchanged here
   and cannot be added retroactively.
2. **Operation**: Normal tool calls, resource reads, prompts, sampling, etc.
3. **Shutdown**: Client closes connection.

A subset of MCP can be made stateless using the Streamable HTTP transport's
`stateless_http` option — each request starts a fresh session.

## The three server primitives

| Primitive | Control | Analogy | Side effects |
|-----------|---------|---------|--------------|
| Tools | Model (autonomous) | POST endpoint | Allowed |
| Resources | Application | GET endpoint | None (read-only) |
| Prompts | User (explicit) | Template | None |

Discovery pattern: `*/list` → `*/get` (or `tools/call`).

Listings are dynamic — servers may send `notifications/*/list_changed` when
the available set changes at runtime.

## What clients expose to servers

| Feature | Purpose |
|---------|---------|
| Sampling | Server requests LLM completion through the host's model |
| Elicitation | Server requests structured input from the user |
| Roots | Server learns which filesystem directories to operate in |
| Logging | Server sends log messages to the client |

Sampling and elicitation must be declared as client capabilities during
`initialize`. The server cannot use them if the client doesn't declare support.

## Capability negotiation

Both sides declare supported features in `initialize`. The exchange is fixed
for the session — capabilities cannot be added or removed after `initialize`.

```python
# FastMCP infers capabilities automatically from registered decorators
mcp = FastMCP("Demo")

@mcp.tool()
def add(a: int, b: int) -> int: ...  # declares 'tools' capability

@mcp.resource("data://x")
def data() -> str: ...               # declares 'resources' capability

@mcp.prompt()
def my_prompt() -> str: ...          # declares 'prompts' capability
```

A server that does not declare `tools` capability will not receive tool calls,
even if handlers exist.

## Design principles

1. **Servers are easy to build** — complex orchestration stays in the host.
2. **Servers are composable** — each focuses on a narrow responsibility.
3. **Servers cannot read the full conversation** or see into other servers.
4. **Features are progressive** — core protocol is minimal; extras are
   negotiated per session.

## JSON-RPC 2.0 message types

All messages are UTF-8 encoded JSON-RPC 2.0:

```json
// Request
{"jsonrpc": "2.0", "id": 1, "method": "tools/call", "params": {...}}

// Success response
{"jsonrpc": "2.0", "id": 1, "result": {...}}

// Error response
{"jsonrpc": "2.0", "id": 1, "error": {"code": -32602, "message": "..."}}

// Notification (one-way, no id)
{"jsonrpc": "2.0", "method": "notifications/message", "params": {...}}
```

## Typical message flow for a tool call

```
Client                    Server
  │                          │
  │── initialize ───────────>│
  │<── initialize response ──│
  │── notifications/initialized ─>│
  │                          │
  │── tools/list ───────────>│
  │<── {tools: [...]} ───────│
  │                          │
  │── tools/call ───────────>│   {name: "get_weather", arguments: {city: "London"}}
  │                          │   [handler runs, optionally sends progress/log notifications]
  │<── notifications/progress│   {progress: 0.5, total: 1.0}
  │<── notifications/message │   {level: "info", data: "Looking up London..."}
  │<── {result: {...}} ──────│   CallToolResult
  │                          │
  │── disconnect ───────────>│
```

## Typical flow when server requests sampling

```
Client (host + LLM)       Server
  │                          │
  │── tools/call ───────────>│   (tool that needs LLM)
  │<── sampling/createMessage│   {messages: [...], maxTokens: 200}
  │    [user approval]       │
  │    [LLM call]            │
  │── createMessage result ->│   {role: "assistant", content: {...}}
  │<── tools/call result ────│   (tool completes with LLM output)
```

## Protocol version

Current spec version: `2025-11-25` (YYYY-MM-DD format).

Version is negotiated during `initialize`. Both sides agree on a single version
for the session. Backwards-compatible changes do not bump the version.

On mismatch, the server returns JSON-RPC error `-32602` with `supported` and
`requested` fields.

## JSON Schema

MCP uses JSON Schema 2020-12 by default (no `$schema` field present in the
schema objects). Schemas may declare a different dialect via `$schema`.
Implementations must support at least JSON Schema 2020-12.

FastMCP generates JSON Schema automatically from Python type annotations using
Pydantic.
