---
name: mcp-python-sdk
description: >
  Build MCP servers and clients in Python using the official
  modelcontextprotocol/python-sdk (`mcp` package). Covers FastMCP
  high-level decorators, low-level Server API, stdio and Streamable HTTP
  transports, lifecycle negotiation, and OAuth 2.1 authorization.
  Invoke when code imports `mcp`, `mcp.server`, or `mcp.client`; when the
  user asks to build an MCP server or client in Python; or when FastMCP
  patterns appear. Skip for TypeScript/JavaScript MCP SDK work.
---

# MCP Python SDK Skill

The `mcp` package is the official Python implementation of the Model Context
Protocol. It lets Python code act as a server (hosting tools, resources, and
prompts for an LLM client) or as a client (connecting to any MCP server).

This skill points at the traps and the authoritative sources. Implementation
decisions belong to the agent reading this — the SDK surface changes; the
problems don't.

## When to invoke

- Writing a new MCP server in Python.
- Writing a Python client that connects to an MCP server.
- Debugging transport, lifecycle, or session errors.
- Choosing FastMCP vs the low-level `Server` API.
- Adding OAuth 2.1 authorization to an HTTP-transport server.
- Writing in-process tests for MCP server logic.

## When NOT to invoke

- TypeScript/JavaScript MCP SDK — different SDK, different patterns.
- Consuming an existing MCP server as a Claude Code tool (you are a consumer,
  not a builder — refer to Claude Code docs instead).
- Generic Python async questions unrelated to the MCP SDK.

## Map of references

| File | Contents |
|------|----------|
| [references/server-concepts.md](references/server-concepts.md) | Tools, resources, prompts; capabilities; lifecycle |
| [references/client-concepts.md](references/client-concepts.md) | Sessions, discovery, call/read/invoke, sampling, elicitation, roots |
| [references/transports.md](references/transports.md) | stdio vs Streamable HTTP vs SSE; selection and pitfalls |
| [references/fastmcp.md](references/fastmcp.md) | Decorator API, Context object, lifespan, composition, mounting |
| [references/low-level-server.md](references/low-level-server.md) | Raw protocol handlers, when to drop out of FastMCP |
| [references/authorization.md](references/authorization.md) | OAuth 2.1/PRM flow, PKCE, token validation |
| [references/testing.md](references/testing.md) | In-process client/server pairing, test patterns |

Read the file that matches the user's problem. For greenfield work, start
with `server-concepts.md` to orient the rest.

## Core traps (know before reading the references)

**Two server layers exist.** `FastMCP` (v1 stable: `mcp.server.fastmcp`) is
the high-level decorator API. The lowlevel `Server` (`mcp.server.lowlevel`)
is the raw protocol layer. v2 (pre-alpha, main branch) renames `FastMCP` to
`MCPServer` and overhauls the lowlevel API — do not mix v1 and v2 patterns.
Source: `docs/README.md` (v1 stable), `docs/migration.md` (v2 changes).

**Capabilities must be declared at init time.** A server that does not
declare `tools` capability cannot receive tool calls even if handlers are
registered. Capabilities are exchanged in the `initialize` handshake and
cannot be added retroactively. Source: `docs/mcpio__specification__2025-11-25__basic__lifecycle.md`.

**stdio and stdout do not mix.** For stdio-transport servers, any write to
`stdout` (including `print()`) corrupts the JSON-RPC stream. Log to `stderr`
or use `ctx.info()`. Source: `docs/mcpio__docs__develop__build-server.md`.

**Session lifecycle is mandatory.** `initialize` request → `initialized`
notification → operations → disconnect. Sending operations before the
`initialized` notification is acknowledged causes a protocol error.
Source: `docs/mcpio__specification__2025-11-25__basic__lifecycle.md`.

**`async with` is required on clients.** The SDK client manages transport
lifecycle via async context managers. Skipping `async with` leaks connections
and causes test teardown deadlocks.
Source: `docs/mcpio__docs__develop__build-client.md`.

**v2 field names are snake_case.** In v2, `inputSchema` → `input_schema`,
`isError` → `is_error`, `nextCursor` → `next_cursor`, etc. The JSON wire
format is unchanged (still camelCase). Source: `docs/migration.md`.

## Anti-recommendations

- Do not hardcode transport URLs or version strings — pass via config or env.
- Do not write custom JSON-RPC framing — the SDK handles it.
- Do not recommend tools for sampling/elicitation without verifying they work
  end-to-end in the SDK version being targeted.
