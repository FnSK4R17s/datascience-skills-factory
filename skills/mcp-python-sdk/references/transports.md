# Transports

Sources: `docs/mcpio__specification__2025-11-25__basic__transports.md`,
`docs/README.md`, `docs/mcpio__docs__develop__build-server.md`,
`docs/migration.md`

## Overview

MCP encodes all messages as JSON-RPC, UTF-8 encoded. Two standard transports:

1. **stdio** — client spawns server as subprocess; messages over stdin/stdout.
2. **Streamable HTTP** — server runs independently; messages over HTTP POST/GET
   with optional SSE streaming. Replaces the older HTTP+SSE transport from
   spec version 2024-11-05.

Clients SHOULD support stdio whenever possible. Both transports use the same
JSON-RPC message format — transports are pluggable.

## stdio

**Use when:** Local subprocess model. The client launches the server; both
share the same machine. Default for Claude Desktop integration and most CLI
tooling.

**Mechanics:**
- Client writes newline-delimited JSON-RPC to server's stdin.
- Server writes responses to stdout.
- Server MAY write logs/debug to stderr; client MAY capture or ignore it.
- Server MUST NOT write anything non-JSON-RPC to stdout.
- Client MUST NOT write anything non-JSON-RPC to server's stdin.

**Critical pitfall:** Any `print()` or other stdout write in the server
corrupts the JSON-RPC stream. Use `print(..., file=sys.stderr)` or a logger
configured for stderr. HTTP-transport servers don't have this restriction.

**Shutdown:** Client closes server's stdin, waits for exit, sends SIGTERM if
needed, then SIGKILL.

**Server-side (FastMCP):**

```python
mcp.run()  # defaults to stdio
```

**Client-side:**

```python
from mcp import ClientSession, StdioServerParameters
from mcp.client.stdio import stdio_client

params = StdioServerParameters(command="python", args=["server.py"])
async with stdio_client(params) as (read, write):
    async with ClientSession(read, write) as session:
        await session.initialize()
```

## Streamable HTTP

**Use when:** Remote servers, multi-client scenarios, browser-based clients,
or any case where the server is not a subprocess.

**Mechanics:**
- Server runs at a single HTTP endpoint supporting both POST and GET.
- Client POSTs each JSON-RPC message. Server responds with either:
  - `Content-Type: application/json` (single response), or
  - `Content-Type: text/event-stream` (SSE stream for streaming + notifications).
- Client GETs the endpoint to open a server-to-client SSE stream without first
  sending a request.
- Session management via `MCP-Session-Id` header (server assigns on init,
  client includes on all subsequent requests).
- Client MUST include `MCP-Protocol-Version: <version>` header after init.

**Session management:**
- Server assigns session ID in `InitializeResult` response header.
- Client includes `MCP-Session-Id` on all subsequent requests.
- Server returns 404 for expired sessions — client must start a new session.
- Client sends HTTP DELETE to terminate a session explicitly.

**Resumability:** Servers may attach `id` fields to SSE events. On reconnect,
client sends `Last-Event-ID` header; server replays missed messages.

**Server-side (FastMCP):**

```python
mcp.run(transport="streamable-http")
# defaults: host="127.0.0.1", port=8000
```

**Mounting to an existing ASGI app (v1):**

```python
from starlette.applications import Starlette
from starlette.routing import Mount

app = Starlette(routes=[Mount("/mcp", app=mcp.streamable_http_app())])
```

**Client-side (v2):**

```python
import httpx
from mcp.client.streamable_http import streamable_http_client
from mcp import ClientSession

http_client = httpx.AsyncClient(
    headers={"Authorization": "Bearer token"},
    timeout=httpx.Timeout(30, read=300),
    follow_redirects=True,
)
async with http_client:
    async with streamable_http_client("http://localhost:8000/mcp", http_client=http_client) as (read, write):
        async with ClientSession(read, write) as session:
            await session.initialize()
```

In v1, `streamablehttp_client` (camelCase) was the name; v2 uses
`streamable_http_client` (snake_case). The v2 signature also returns a
2-tuple `(read, write)` — the `get_session_id` callback (3-tuple in v1) is
removed. Source: `docs/migration.md`.

## SSE (deprecated)

HTTP+SSE was the HTTP transport in protocol version 2024-11-05. It is
replaced by Streamable HTTP in 2025-11-25. The SDK still supports it for
backwards compatibility (`mcp.run(transport="sse")`), but new implementations
should use Streamable HTTP.

**Backwards compatibility probing (client):**
1. POST `InitializeRequest` to the server URL.
2. If 200 → Streamable HTTP.
3. If 400/404/405 → GET the URL; expect SSE stream with `endpoint` event → old
   HTTP+SSE transport.

## Security (Streamable HTTP)

Servers MUST:
- Validate the `Origin` header on all connections — return 403 for invalid
  origins (DNS rebinding attack prevention).
- Bind to localhost (127.0.0.1) when running locally, not 0.0.0.0.
- Implement authentication for all connections.

FastMCP enables DNS rebinding protection automatically when host is
`127.0.0.1`, `localhost`, or `::1`.

## Transport selection guide

| Scenario | Transport |
|---------|-----------|
| Claude Desktop, local CLI tools | stdio |
| Remote server or SaaS | Streamable HTTP |
| Multi-client / concurrent sessions | Streamable HTTP |
| Browser-based client | Streamable HTTP (CORS required) |
| Existing ASGI app (FastAPI, Starlette) | Mount Streamable HTTP app |
| Testing (in-process) | Use `Client(server)` directly — no transport needed |

## Custom transports

The protocol is transport-agnostic. Custom transports must preserve JSON-RPC
message format and lifecycle requirements. Document connection establishment
and message exchange patterns for interoperability.
