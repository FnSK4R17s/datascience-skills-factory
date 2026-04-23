---
name: mcp-python-sdk
description: >
  Build MCP servers and clients in Python using the official
  modelcontextprotocol/python-sdk (`mcp` package). Covers FastMCP (v1 stable)
  and MCPServer (v2 pre-alpha) decorator APIs, low-level Server, stdio and
  Streamable HTTP transports, lifecycle negotiation, OAuth 2.1 authorization,
  experimental tasks, and in-process testing. Invoke when code imports `mcp`,
  `mcp.server`, or `mcp.client`; when the user asks to build an MCP server or
  client in Python; or when FastMCP/MCPServer patterns appear.
triggers:
  - mcp server python
  - fastmcp
  - mcpserver python
  - mcp client python
  - mcp sdk
  - modelcontextprotocol python
skip:
  - TypeScript MCP SDK
  - JavaScript MCP SDK
  - non-Python MCP tooling
  - consuming MCP servers as a Claude Code tool (user perspective, not builder)
---

# MCP Python SDK Skill

The `mcp` package is the official Python implementation of the Model Context
Protocol. It lets Python code act as a server (hosting tools, resources, and
prompts for an LLM client) or as a client (connecting to any MCP server).

This skill points at the traps and the authoritative sources. Implementation
decisions belong to the agent reading this — the SDK surface changes; the
problems don't.

## The v1 / v2 split — pick one and commit

**v1 (stable):** `FastMCP` at `mcp.server.fastmcp.FastMCP`. Current stable
release on PyPI. All decorators, lifespan, and transport run here.

**v2 (pre-alpha):** `MCPServer` at `mcp.server.mcpserver.MCPServer`. Lives on
`main` branch. A mechanical rename of `FastMCP` plus breaking API changes (see
`references/migration-v1-to-v2.md`). The lowlevel `Server` also has breaking
changes in v2.

Do not mix v1 and v2 patterns. Picking the wrong layer causes silent failures
(camelCase field names, missing constructor params, wrong import paths).

**When in doubt: use v1 (`FastMCP`) for production; use v2 only when targeting
the `main` branch or building for a v2 release.**

## Installation

```bash
pip install mcp          # base
pip install "mcp[cli]"  # includes typer + python-dotenv for CLI tools
```

## When to invoke this skill

- Writing a new MCP server in Python.
- Writing a Python client that connects to an MCP server.
- Debugging transport, lifecycle, or session errors.
- Choosing FastMCP vs lowlevel `Server` API.
- Adding OAuth 2.1 authorization to an HTTP-transport server.
- Writing in-process tests for MCP server logic.
- Migrating from v1 to v2.
- Understanding experimental tasks for async/deferred tool execution.

## When NOT to invoke this skill

- TypeScript/JavaScript MCP SDK — different SDK, different patterns.
- Consuming an existing MCP server as a Claude Code tool (you are a consumer,
  not a builder — refer to Claude Code docs instead).
- Generic Python async questions unrelated to the MCP SDK.
- Questions about non-Python MCP SDKs (C#, Java, Go, Rust, Ruby).

## Map of references

| File | Contents |
|------|----------|
| [references/server-concepts.md](references/server-concepts.md) | Tools, resources, prompts; capabilities; lifecycle; logging; pagination; icons |
| [references/client-concepts.md](references/client-concepts.md) | Sessions, discovery, call/read/invoke, sampling, elicitation, roots |
| [references/transports.md](references/transports.md) | stdio vs Streamable HTTP vs SSE; selection and pitfalls |
| [references/fastmcp.md](references/fastmcp.md) | v1 decorator API, Context, lifespan, composition, mounting |
| [references/mcpserver.md](references/mcpserver.md) | v2 MCPServer rename, transport param changes, import paths |
| [references/low-level-server.md](references/low-level-server.md) | Raw protocol handlers, when to drop out of FastMCP |
| [references/authorization.md](references/authorization.md) | OAuth 2.1/PRM flow, PKCE, resource param, token passthrough prohibition |
| [references/testing.md](references/testing.md) | In-process client/server pairing, test patterns, MCP Inspector, debugging |
| [references/migration-v1-to-v2.md](references/migration-v1-to-v2.md) | Breaking changes catalog: field renames, constructor splits, removed helpers |
| [references/experimental-tasks.md](references/experimental-tasks.md) | Async task execution, polling, elicitation/sampling within tasks |
| [references/architecture.md](references/architecture.md) | Host-client-server model, data vs transport layers, JSON-RPC 2.0 |
| [references/build-server.md](references/build-server.md) | Tutorial patterns: project setup, logging rules, Claude Desktop wiring |
| [references/build-client.md](references/build-client.md) | Tutorial patterns: stdio client, Anthropic SDK integration |
| [references/specification-pointers.md](references/specification-pointers.md) | Spec document map, key constraints, JSON Schema dialect |

Read the file that matches the user's problem. For greenfield work, start with
`server-concepts.md` to orient, then `fastmcp.md` to implement.

## Core traps (know before reading the references)

**Capabilities must be declared at init time.** A server that does not declare
`tools` capability cannot receive tool calls even if handlers are registered.
Capabilities are exchanged in the `initialize` handshake and cannot be added
retroactively. Source: `docs/mcpio__specification__2025-11-25__basic__lifecycle.md`.

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

**Token passthrough is forbidden.** MCP servers MUST NOT forward tokens
received from clients to upstream APIs. Obtain separate tokens for upstream
calls. Source: `docs/mcpio__specification__2025-11-25__basic__authorization.md`.

**Experimental tasks are opt-in and API-unstable.** Call
`server.experimental.enable_tasks()` to activate. The `.experimental`
namespace on both `Server` and `ClientSession` is the entry point.
Source: `docs/experimental__tasks.md`.

## Anti-recommendations

- Do not hardcode transport URLs or version strings — pass via config or env.
- Do not write custom JSON-RPC framing — the SDK handles it.
- Do not mix v1 and v2 import patterns in the same codebase.
- Do not use `FastMCP` (v1) and `MCPServer` (v2) interchangeably — they are
  the same concept but with different import paths and constructor signatures.
- Do not recommend tools for sampling/elicitation without verifying they work
  end-to-end in the SDK version being targeted.
