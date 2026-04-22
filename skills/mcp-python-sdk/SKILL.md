---
name: mcp-python-sdk
description: >
  Build MCP servers and clients in Python using the official
  modelcontextprotocol/python-sdk. Covers FastMCP high-level decorators,
  low-level Server/Client APIs, stdio and HTTP transports, capabilities
  negotiation, and authorization. Invoke when code imports `mcp`,
  `mcp.server`, or `mcp.client`; when the user asks to build an MCP server
  or client in Python; or when FastMCP patterns appear in the codebase.
triggers:
  - mcp server python
  - fastmcp
  - mcp client python
  - model context protocol python
  - mcp.server
  - mcp.client
---

# MCP Python SDK Skill

The Model Context Protocol Python SDK (`mcp`) lets Python code participate in
the MCP ecosystem — either by hosting server-side primitives (tools, resources,
prompts) that an LLM client can call, or by acting as a client that connects to
existing servers. The hard parts are: picking the right abstraction layer
(FastMCP vs low-level), picking the right transport (stdio vs HTTP), and keeping
the capability negotiation and lifecycle correct.

This skill is a problem-statement plus reference data. It points you at the
traps and the authoritative information. Implementation decisions belong to the
agent reading this file — the SDK surface changes; the problems don't.

## When to invoke

- Writing a new MCP server in Python.
- Writing a client that connects to an MCP server from Python.
- Debugging transport or lifecycle errors (`InitializationError`,
  `CapabilityError`, session teardown issues).
- Choosing between FastMCP and the low-level server API.
- Adding OAuth / authorization to an HTTP-transport server.
- Writing tests that exercise MCP server logic without spinning up a real
  transport.

## When NOT to invoke

- TypeScript / JavaScript MCP SDK — different SDK, different patterns.
- Consuming an existing MCP server as a Claude Code tool (the user is a
  consumer, not a builder; refer to Claude Code docs instead).
- Generic Python async questions not specifically about the MCP SDK.

## Map of references

| File | Contents |
|------|----------|
| [references/server-concepts.md](references/server-concepts.md) | Tools, resources, prompts; capabilities; lifecycle phases |
| [references/client-concepts.md](references/client-concepts.md) | Session management, primitive discovery, call/read/invoke, sampling |
| [references/transports.md](references/transports.md) | stdio, Streamable HTTP, SSE; selection criteria; auth considerations |
| [references/fastmcp.md](references/fastmcp.md) | High-level decorators, context, composition, mounting |
| [references/low-level-server.md](references/low-level-server.md) | Raw protocol, request handlers, when to leave FastMCP |
| [references/authorization.md](references/authorization.md) | OAuth 2.1 story, token validation, scope enforcement |
| [references/testing.md](references/testing.md) | In-process client/server pairs, transport mocking, test patterns |

Read the file that matches the user's problem. Read `server-concepts.md`
first if the user is starting from scratch — it orients the rest.

## The core traps (know before you read the references)

**FastMCP is not always FastMCP.** The package ships two server layers:
`FastMCP` (high-level, decorator-driven) and `Server` (low-level, manual
handler registration). They share transports and wire format but have different
ergonomics. Mixing patterns from both in the same search causes confusion.

**Capabilities must be declared at init time.** A server that doesn't declare
`tools` in its capability list cannot serve tool calls, even if it registers
handlers for them. The client will not send calls it believes the server
doesn't support.

**stdio is for local subprocess use; HTTP is for remote and multi-client.**
Starting a stdio server from a long-lived process that already owns stdin/stdout
is a common mistake. stdio inherits the process's stdin/stdout — any debug print
will corrupt the JSON-RPC stream.

**The session is stateful.** `initialize` → `initialized` → operation → `close`
is the required sequence. Sending operation requests before `initialized` is
acknowledged causes a protocol error.

**`async with` is not optional for clients.** The Python SDK client manages
transport lifecycle via async context managers. A client that isn't wrapped in
`async with` leaves connections open and may deadlock on test teardown.

## Anti-recommendations

- Do not hardcode transport URLs or version strings in shipped code — pass
  them via config or environment variables.
- Do not write your own JSON-RPC framing — the SDK handles it; bypass only
  if the SDK transport layer itself is broken.
- Do not name-drop libraries for sampling/elicitation unless you have verified
  they work end-to-end in the SDK version you are targeting.
