# Transports

Sources: `docs/mcpio__specification__2025-11-25__basic__transports.md`,
`docs/README.md`, `docs/mcpio__docs__develop__build-server.md`,
`docs/migration.md`

## Overview

MCP encodes all messages as JSON-RPC 2.0, UTF-8 encoded. Two standard transports:

1. **stdio** — client spawns server as subprocess; messages over stdin/stdout.
2. **Streamable HTTP** — server runs independently; messages over HTTP POST/GET
   with optional SSE streaming. Replaces the older HTTP+SSE transport from
   spec version 2024-11-05.

Clients SHOULD support stdio whenever possible. Both transports use the same
JSON-RPC message format — the protocol layer is transport-agnostic.

## stdio

**Use when:** Local subprocess model. Client launches the server; both share
the same machine. Default for Claude Desktop integration and most CLI tooling.

### Mechanics

- Client writes newline-delimited JSON-RPC to server's stdin.
- Server writes responses to stdout.
- Server MAY write logs/debug to stderr; client MAY capture or ignore it.
- Server MUST NOT write anything non-JSON-RPC to stdout.
- Client MUST NOT write anything non-JSON-RPC to server's stdin.

**Critical pitfall:** Any `print()` or other stdout write in the server
corrupts the JSON-RPC stream. This is silent — communication just breaks.

```python
import sys

# WRONG in stdio server — corrupts stream
print("Starting up")

# CORRECT — log to stderr
print("Starting up", file=sys.stderr)

# CORRECT — use SDK logging via Context
await ctx.info("Starting up")  # sends MCP log notification to client
```

HTTP-transport servers do not have this restriction.

### Shutdown

Client closes server's stdin → waits for server to exit → sends SIGTERM if
still running → sends SIGKILL as last resort.

### Server-side (FastMCP)

```python
from mcp.server.fastmcp import FastMCP

mcp = FastMCP("My Server")

@mcp.tool()
def my_tool(x: int) -> int:
    return x * 2

if __name__ == "__main__":
    mcp.run()  # defaults to stdio
```

### Client-side (connecting to stdio server)

```python
import asyncio
from mcp import ClientSession, StdioServerParameters
from mcp.client.stdio import stdio_client

async def run():
    params = StdioServerParameters(
        command="python",
        args=["server.py"],
        env={"API_KEY": "my-key"},  # optional extra env vars
    )
    async with stdio_client(params) as (read, write):
        async with ClientSession(read, write) as session:
            await session.initialize()
            tools = await session.list_tools()
            print("Tools:", [t.name for t in tools.tools])

asyncio.run(run())
```

### Running with uv (recommended for isolation)

```python
# Claude Desktop config
{
  "mcpServers": {
    "my-server": {
      "command": "uv",
      "args": ["run", "--with", "mcp", "/absolute/path/to/server.py"],
      "env": {"MY_API_KEY": "..."}
    }
  }
}
```

## Streamable HTTP

**Use when:** Remote servers, multi-client scenarios, browser-based clients,
or any case where the server is not a subprocess.

### Mechanics

- Server runs at a single HTTP endpoint supporting both POST and GET.
- Client POSTs each JSON-RPC message. Server responds with either:
  - `Content-Type: application/json` (single response), or
  - `Content-Type: text/event-stream` (SSE stream for streaming + notifications).
- Client GETs the endpoint to open a server-to-client SSE stream without
  first sending a request.
- Session management via `Mcp-Session-Id` header (server assigns on init,
  client includes on all subsequent requests).
- Client MUST include `MCP-Protocol-Version: <version>` header after init.

**Session management:**
- Server assigns session ID in `InitializeResult` response header.
- Client includes `Mcp-Session-Id` on all subsequent requests.
- Server returns 404 for expired sessions — client must start a new session.
- Client sends HTTP DELETE to terminate a session explicitly.

**Resumability:** Servers may attach `id` fields to SSE events. On reconnect,
client sends `Last-Event-ID`; server replays missed messages.

### Server-side — minimal

```python
from mcp.server.fastmcp import FastMCP

# Stateless (recommended for scalability)
mcp = FastMCP("My Server", stateless_http=True, json_response=True)

@mcp.tool()
def greet(name: str) -> str:
    return f"Hello, {name}!"

if __name__ == "__main__":
    mcp.run(transport="streamable-http")
    # Serves at http://127.0.0.1:8000/mcp by default
```

### Server-side — custom host/port

```python
if __name__ == "__main__":
    mcp.run(
        transport="streamable-http",
        host="0.0.0.0",
        port=9000,
    )
```

### Server-side — mounting to Starlette (multiple servers)

```python
import contextlib
from starlette.applications import Starlette
from starlette.routing import Mount
from mcp.server.fastmcp import FastMCP

echo_mcp = FastMCP("EchoServer", stateless_http=True, json_response=True)
math_mcp = FastMCP("MathServer", stateless_http=True, json_response=True)

@echo_mcp.tool()
def echo(message: str) -> str:
    return f"Echo: {message}"

@math_mcp.tool()
def add(a: int, b: int) -> int:
    return a + b

# Set mount path so endpoints are at /echo and /math (not /echo/mcp and /math/mcp)
echo_mcp.settings.streamable_http_path = "/"
math_mcp.settings.streamable_http_path = "/"

@contextlib.asynccontextmanager
async def lifespan(app: Starlette):
    async with contextlib.AsyncExitStack() as stack:
        await stack.enter_async_context(echo_mcp.session_manager.run())
        await stack.enter_async_context(math_mcp.session_manager.run())
        yield

app = Starlette(
    routes=[
        Mount("/echo", echo_mcp.streamable_http_app()),
        Mount("/math", math_mcp.streamable_http_app()),
    ],
    lifespan=lifespan,
)
# Run: uvicorn server:app --reload
# Clients connect to http://localhost:8000/echo and http://localhost:8000/math
```

### Server-side — host-based routing

```python
from starlette.routing import Host

app = Starlette(
    routes=[
        Host("mcp.acme.corp", app=mcp.streamable_http_app()),
    ],
    lifespan=lifespan,
)
```

### Server-side — path configuration at init time

```python
# Configure streamable_http_path in constructor to set endpoint location
mcp_at_root = FastMCP(
    "My Server",
    json_response=True,
    streamable_http_path="/",  # endpoint at root of wherever it's mounted
)

# Mounted at /process → endpoint at /process (not /process/mcp)
app = Starlette(routes=[Mount("/process", app=mcp_at_root.streamable_http_app())])
```

### Client-side (v1) — basic HTTP connection

```python
import asyncio
from mcp import ClientSession
from mcp.client.streamable_http import streamable_http_client

async def run():
    async with streamable_http_client("http://localhost:8000/mcp") as (read, write):
        async with ClientSession(read, write) as session:
            await session.initialize()
            tools = await session.list_tools()
            print("Tools:", [t.name for t in tools.tools])

asyncio.run(run())
```

### Client-side — with auth headers and timeouts

```python
import httpx
from mcp import ClientSession
from mcp.client.streamable_http import streamable_http_client

async def run():
    http_client = httpx.AsyncClient(
        headers={"Authorization": "Bearer my-token"},
        timeout=httpx.Timeout(30, read=300),  # 300s read timeout for streaming
        follow_redirects=True,
    )
    async with http_client:
        async with streamable_http_client(
            "http://localhost:8000/mcp",
            http_client=http_client,
        ) as (read, write):
            async with ClientSession(read, write) as session:
                await session.initialize()
                result = await session.call_tool("my_tool", {"x": 42})
                print(result.content[0].text)
```

### Capturing session ID (v2 — via httpx event hooks)

```python
import httpx

captured_session_ids: list[str] = []

async def capture_session_id(response: httpx.Response) -> None:
    session_id = response.headers.get("mcp-session-id")
    if session_id:
        captured_session_ids.append(session_id)

http_client = httpx.AsyncClient(
    event_hooks={"response": [capture_session_id]},
    follow_redirects=True,
)

async with http_client:
    async with streamable_http_client(url, http_client=http_client) as (read, write):
        async with ClientSession(read, write) as session:
            await session.initialize()
            session_id = captured_session_ids[0] if captured_session_ids else None
```

Note: In v1, `streamablehttp_client` returned a 3-tuple
`(read, write, get_session_id)`. In v2, it returns a 2-tuple and the callback
was removed. Use httpx event hooks to capture the session ID in v2.

## CORS for browser-based clients

If your server is accessed from a browser, configure CORS properly. The
`Mcp-Session-Id` header must be exposed or browsers cannot read the session ID
from initialization responses:

```python
from starlette.middleware.cors import CORSMiddleware

# Wrap your Starlette app with CORS middleware
app = CORSMiddleware(
    app,  # your Starlette/FastAPI app
    allow_origins=["https://your-frontend.com"],  # restrict in production
    allow_methods=["GET", "POST", "DELETE"],  # MCP streamable HTTP methods
    expose_headers=["Mcp-Session-Id"],  # required for browser clients
)
```

## SSE (deprecated)

HTTP+SSE was the HTTP transport in protocol version 2024-11-05. It is replaced
by Streamable HTTP in 2025-11-25. Still supported for backwards compatibility.

```python
# Still works but not recommended for new code
mcp.run(transport="sse")
```

### Backwards compatibility probing (client)

When connecting to an unknown server:
1. POST `InitializeRequest` to the server URL.
2. If 200 → Streamable HTTP.
3. If 400/404/405 → GET the URL; expect SSE stream with `endpoint` event →
   old HTTP+SSE transport.

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
|----------|-----------|
| Claude Desktop integration | stdio |
| Local CLI tools | stdio |
| Remote server or SaaS | Streamable HTTP |
| Multi-client / concurrent sessions | Streamable HTTP |
| Browser-based client | Streamable HTTP (+ CORS) |
| Existing ASGI app (FastAPI, Starlette) | Mount Streamable HTTP app |
| Testing (in-process) | `Client(server)` — no transport at all |

## Testing without a transport

The recommended testing approach uses no transport:

```python
from mcp import Client

async with Client(mcp, raise_exceptions=True) as client:
    await client.initialize()  # not needed — Client handles init
    result = await client.call_tool("my_tool", {"x": 1})
```

See `references/testing.md` for the full test pattern.

## Custom transports

The protocol is transport-agnostic. Custom transports must:
- Preserve JSON-RPC message format and UTF-8 encoding.
- Support the full lifecycle (initialize, operation, shutdown).
- Document connection establishment and message exchange patterns.
