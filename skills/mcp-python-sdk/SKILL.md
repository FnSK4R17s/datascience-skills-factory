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

## The v1 / v2 split — pick one and commit

**v1 (stable):** `FastMCP` at `mcp.server.fastmcp.FastMCP`. Current stable
release on PyPI. All production code should use this.

**v2 (pre-alpha):** `MCPServer` at `mcp.server.mcpserver.MCPServer`. Lives on
`main` branch. A rename of `FastMCP` with breaking API changes (transport
params moved out of constructor, `get_context()` removed, field names
snake_case, lowlevel handlers constructor-only). Do not mix v1 and v2 patterns.

**Rule: use v1 (`FastMCP`) for production. Use v2 only when explicitly
targeting the `main` branch or pre-alpha features.**

## Installation

```bash
pip install mcp          # base package
pip install "mcp[cli]"  # includes typer + python-dotenv for CLI tools

# Recommended: use uv for projects
uv init my-mcp-server
cd my-mcp-server
uv add "mcp[cli]"
```

## Minimal working server (30 seconds to running)

```python
from mcp.server.fastmcp import FastMCP

mcp = FastMCP("Demo", json_response=True)

@mcp.tool()
def add(a: int, b: int) -> int:
    """Add two numbers."""
    return a + b

@mcp.resource("greeting://{name}")
def get_greeting(name: str) -> str:
    """Get a personalized greeting."""
    return f"Hello, {name}!"

@mcp.prompt()
def greet_user(name: str, style: str = "friendly") -> str:
    """Generate a greeting prompt."""
    styles = {
        "friendly": "Please write a warm, friendly greeting",
        "formal": "Please write a formal, professional greeting",
    }
    return f"{styles.get(style, styles['friendly'])} for someone named {name}."

if __name__ == "__main__":
    mcp.run(transport="streamable-http")
```

Run it:
```bash
uv run --with mcp server.py
# Test with Inspector: npx @modelcontextprotocol/inspector
# Add to Claude Code: claude mcp add --transport http my-server http://localhost:8000/mcp
```

## Core traps (read before touching any code)

**stdout corrupts stdio.** Any `print()` in a stdio-transport server corrupts
the JSON-RPC stream. Use `print(..., file=sys.stderr)` or `await ctx.info()`.
HTTP-transport servers do not have this restriction.

**Capabilities at init only.** Capabilities (tools, resources, prompts,
sampling, logging) are declared in the `initialize` handshake and cannot be
added retroactively. FastMCP infers them from registered decorators
automatically.

**Session lifecycle is mandatory.** `initialize` request → `initialized`
notification → operations → disconnect. Sending operations before the
`initialized` notification is acknowledged causes a protocol error.

**`async with` is required on clients.** The SDK manages transport lifecycle via
async context managers. Skipping `async with` leaks connections and causes test
teardown deadlocks.

**v2 attribute names are snake_case.** `result.isError` → `result.is_error`,
`tool.inputSchema` → `tool.input_schema`, `tools.nextCursor` →
`tools.next_cursor`. Wire format is still camelCase; only Python attribute access
changed. `populate_by_name=True` means constructor kwargs still accept camelCase.

**Token passthrough is forbidden.** MCP servers MUST NOT forward tokens received
from clients to upstream APIs. Obtain separate tokens for upstream calls.

**`CallToolResult` must always be returned directly.** No `Optional[CallToolResult]`
or `Union`. For empty results: `CallToolResult(content=[])`.

## Map of references

| File | Contents |
|------|----------|
| [references/fastmcp.md](references/fastmcp.md) | v1 decorator API, Context, lifespan, composition, mounting, images, icons — the primary file for server builders |
| [references/server-concepts.md](references/server-concepts.md) | Tools, resources, prompts; capabilities; lifecycle; elicitation; sampling; pagination; logging |
| [references/client-concepts.md](references/client-concepts.md) | Sessions, discovery, call/read/invoke, sampling, elicitation, roots, OAuth client |
| [references/transports.md](references/transports.md) | stdio vs Streamable HTTP vs SSE; selection, CORS, ASGI mounting |
| [references/testing.md](references/testing.md) | In-process client/server pairing, pytest patterns, MCP Inspector, debugging |
| [references/low-level-server.md](references/low-level-server.md) | Raw protocol handlers, v1 vs v2 patterns, when to drop out of FastMCP |
| [references/mcpserver.md](references/mcpserver.md) | v2 MCPServer rename, transport param changes, import paths |
| [references/authorization.md](references/authorization.md) | OAuth 2.1 flow, PKCE, resource param, token passthrough prohibition, TokenVerifier |
| [references/experimental-tasks.md](references/experimental-tasks.md) | Async task execution, polling, elicitation/sampling within tasks |
| [references/migration-v1-to-v2.md](references/migration-v1-to-v2.md) | Complete breaking changes catalog with before/after examples |
| [references/architecture.md](references/architecture.md) | Host-client-server model, data vs transport layers, JSON-RPC 2.0 |
| [references/build-server.md](references/build-server.md) | End-to-end server tutorial: weather server, Claude Desktop wiring, debugging |
| [references/build-client.md](references/build-client.md) | End-to-end client tutorial: stdio client, Anthropic SDK integration, full chatbot |
| [references/specification-pointers.md](references/specification-pointers.md) | Spec document map, key constraints, JSON Schema dialect |

**For greenfield server work:** start with `fastmcp.md`, then `server-concepts.md`.
**For client work:** start with `client-concepts.md`, then `build-client.md`.
**For debugging:** start with `testing.md`.

## Anti-recommendations

- Do not hardcode transport URLs or version strings — pass via config or env.
- Do not write custom JSON-RPC framing — the SDK handles it.
- Do not mix v1 and v2 import patterns in the same codebase.
- Do not use `print()` in stdio servers — it breaks the JSON-RPC stream.
- Do not call `get_context()` in v2 — it was removed; use `ctx: Context` param.
- Do not return `Optional[CallToolResult]` from tools — always return `CallToolResult` directly.
- Do not forward received bearer tokens to upstream APIs — token passthrough is prohibited.
- Do not use `create_connected_server_and_client_session` in v2 — use `Client(server)`.
