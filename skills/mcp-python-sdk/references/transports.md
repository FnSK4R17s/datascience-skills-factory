# MCP Transports

The transport layer carries JSON-RPC messages between client and server.
The Python SDK ships two production transports: **stdio** and
**Streamable HTTP** (which supersedes the earlier SSE transport).
Choosing the wrong transport causes integration headaches that are hard
to diagnose later.

## stdio

Stdio uses the server process's stdin and stdout as a bidirectional byte
channel. The client spawns the server as a child process.

```python
# Server side — run via `python my_server.py`
from mcp.server.fastmcp import FastMCP
mcp = FastMCP("my-server")

# ... register tools/resources ...

if __name__ == "__main__":
    mcp.run()  # defaults to stdio transport
```

```python
# Client side — spawns the server process
from mcp import ClientSession
from mcp.client.stdio import stdio_client, StdioServerParameters

params = StdioServerParameters(
    command="python",
    args=["my_server.py"],
    env=None,  # inherits caller's environment by default
)

async with stdio_client(params) as (read, write):
    async with ClientSession(read, write) as session:
        await session.initialize()
        ...
```

**When to use stdio:**
- Server runs as a local subprocess under the client's control.
- Single client at a time (Claude Desktop, Claude Code, local agent).
- No network exposure required.
- Simplest possible deployment — no HTTP server, no port binding.

**Traps:**
- Any `print()` call in the server corrupts the transport. Use `ctx.info()`
  (FastMCP) or the logging notification for debug output.
- Setting `env=None` inherits the full parent environment, including secrets.
  Pass an explicit `env={}` (plus needed vars) if the subprocess should have
  a restricted environment.
- The server process exits when the transport closes. Do not start a stdio
  server inside an already-running event loop that owns stdin/stdout.

## Streamable HTTP

Streamable HTTP is the recommended transport for remote and multi-client
scenarios. The server runs as a persistent HTTP endpoint; the client opens
connections as needed.

```python
# Server side — FastMCP with HTTP transport
from mcp.server.fastmcp import FastMCP
mcp = FastMCP("my-server")

if __name__ == "__main__":
    mcp.run(transport="streamable-http", host="0.0.0.0", port=8000)
```

```python
# Client side
from mcp import ClientSession
from mcp.client.streamable_http import streamablehttp_client

async with streamablehttp_client("http://localhost:8000/mcp") as (read, write, _):
    async with ClientSession(read, write) as session:
        await session.initialize()
        ...
```

**When to use Streamable HTTP:**
- Multiple clients connecting to the same server instance.
- Remote server (different machine, container, cloud).
- Stateless or stateful-with-session-ID operation (the protocol supports both).
- Authorization via Bearer tokens.

**Traps:**
- The Streamable HTTP transport uses HTTP POST for client-to-server messages
  and SSE (Server-Sent Events) for server-to-client streaming. Both must be
  reachable through any reverse proxy (some proxies buffer SSE by default).
- Ensure the `/mcp` endpoint path matches between server config and client URL.
- Session management: stateful mode assigns a session ID; stateless mode is
  cheaper but loses server-side context between requests.

## SSE (legacy)

The SDK previously shipped an SSE-only transport (`/sse` endpoint for
incoming events, `/messages` for outgoing). This transport is deprecated in
favor of Streamable HTTP. New code should use Streamable HTTP. The SSE
transport may be removed in a future SDK version.

If you are maintaining existing SSE-transport code:

```python
# Legacy SSE client
from mcp.client.sse import sse_client

async with sse_client("http://localhost:8000/sse") as (read, write):
    async with ClientSession(read, write) as session:
        await session.initialize()
        ...
```

## Selecting a transport

| Scenario | Transport |
|----------|-----------|
| Claude Desktop / Claude Code local tool | stdio |
| Single-user local agent | stdio |
| Remote server, one or many clients | Streamable HTTP |
| Existing SSE deployment (maintenance mode) | SSE (legacy) |
| Need OAuth / authorization | Streamable HTTP |

## Authorization and transport security

Authorization only applies to HTTP-based transports. stdio is secured by OS
process isolation — if the process can reach the server's stdin/stdout, it has
full access.

For Streamable HTTP:
- The server should validate Bearer tokens on every request.
- The SDK does not inject auth headers automatically; pass them via
  `httpx.AsyncClient` headers or a custom transport wrapper.
- The MCP spec defines an OAuth 2.1 flow for server-managed authorization
  — see `references/authorization.md` for the full story.
- Use HTTPS in production. Streamable HTTP over plain HTTP leaks tokens.

## In-process transport (testing only)

The SDK provides an in-process transport that wires client and server directly
without network or subprocess overhead. See `references/testing.md`.
