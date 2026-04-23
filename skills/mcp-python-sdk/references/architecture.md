# Architecture

Sources: `docs/mcpio__docs__learn__architecture.md`,
`docs/mcpio__specification__2025-11-25__architecture__index.md`

## Participants

MCP uses a **client-host-server** model:

- **MCP Host**: The AI application (e.g. Claude Desktop, an IDE, a custom app).
  Manages one or more MCP clients. Enforces security, consent, and coordinates
  with the LLM.
- **MCP Client**: A protocol-level component instantiated by the host. Each client
  maintains a dedicated 1:1 connection with one MCP server.
- **MCP Server**: A program that exposes tools, resources, and prompts. Can run
  locally (same machine via stdio) or remotely (HTTP).

A single host can connect to many servers simultaneously via multiple clients.

```
Host
 ├─ Client 1  ──── Server A (local, stdio)
 ├─ Client 2  ──── Server B (local, stdio)
 └─ Client 3  ──── Server C (remote, Streamable HTTP)
```

Local servers run as subprocess; remote servers are network services.

## Two layers

**Data layer** — JSON-RPC 2.0 message semantics:
- Lifecycle management (initialize, capability negotiation, shutdown)
- Server features: tools, resources, prompts
- Client features: sampling, elicitation, logging
- Utility features: progress, cancellation, notifications

**Transport layer** — communication channel:
- stdio for local processes
- Streamable HTTP for remote servers (replaces old HTTP+SSE)

The data layer is transport-agnostic. Same JSON-RPC messages regardless of
which transport is in use.

## Stateful sessions

MCP is a stateful protocol. Each connection goes through:

1. **Initialization**: `initialize` request → `initialize` response →
   `notifications/initialized` notification. Capabilities are exchanged here
   and cannot be added retroactively.
2. **Operation**: Normal tool calls, resource reads, prompts, sampling, etc.
3. **Shutdown**: Client closes connection.

A subset of MCP can be made stateless using the Streamable HTTP transport's
`stateless_http` option — each request starts a fresh session.

## Primitives: what servers expose

| Primitive | Control | Analogy |
|-----------|---------|---------|
| Tools | Model (autonomous) | POST endpoint; performs actions, may have side effects |
| Resources | Application | GET endpoint; read-only data |
| Prompts | User (explicit) | Reusable templates |

Discovery pattern: `*/list` → `*/get` (or `tools/call`). Listings are dynamic —
servers may send `notifications/*/list_changed` when the set changes.

## Primitives: what clients expose to servers

| Feature | Purpose |
|---------|---------|
| Sampling | Server requests LLM completion through the host's model |
| Elicitation | Server requests structured input from the user |
| Roots | Server learns which filesystem directories to operate in |
| Logging | Server sends log messages to the client |

## Capability negotiation

Both sides declare supported features in `initialize`. A server that doesn't
declare `tools` capability cannot receive tool calls even if handlers are
registered. Capabilities are fixed for the session lifetime.

## Design principles

1. Servers are easy to build — complex orchestration stays in the host.
2. Servers are composable — each focuses on a narrow responsibility.
3. Servers cannot read the full conversation or "see into" other servers.
4. Features are progressive — core protocol is minimal; extras are negotiated.

## JSON-RPC 2.0 message types

All messages are UTF-8 encoded JSON-RPC 2.0:

- **Request**: `{"jsonrpc": "2.0", "id": N, "method": "...", "params": {...}}`
- **Result response**: `{"jsonrpc": "2.0", "id": N, "result": {...}}`
- **Error response**: `{"jsonrpc": "2.0", "id": N, "error": {"code": N, "message": "..."}}`
- **Notification** (one-way, no `id`): `{"jsonrpc": "2.0", "method": "...", "params": {...}}`
