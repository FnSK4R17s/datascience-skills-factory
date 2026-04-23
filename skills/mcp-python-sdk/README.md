<p align="center">
  <img src="logo.png" alt="mcp-python-sdk" height="88">
</p>

<h1 align="center">mcp-python-sdk</h1>

<p align="center">
  <strong>Build MCP servers and clients in Python.</strong><br>
  <sub>Part of <a href="../../">Data Science Skills Factory</a></sub>
</p>

---

The `mcp` package is the official Python implementation of the Model Context
Protocol. It lets Python code act as a **server** (hosting tools, resources,
and prompts for an LLM client) or as a **client** (connecting to any MCP
server).

Two decorator APIs ship in the same package: `FastMCP` is the v1 stable
API; `MCPServer` is the v2 pre-alpha rename — functionally identical, but
transport params move from the constructor to `run()`. This skill documents
both, the low-level `Server` escape hatch, every transport (stdio, Streamable
HTTP, SSE), OAuth 2.1 authorization, experimental tasks, and the in-process
testing pattern.

## Install

```bash
npx skills add FnSK4R17s/datascience-skills-factory --skill mcp-python-sdk
```

## File structure

```
mcp-python-sdk/
├── SKILL.md                       # Entry point, triggers, decision tree
├── README.md                      # This file
├── logo.png                       # Brand mark
└── references/
    ├── architecture.md            # host / client / server roles, protocol
    ├── server-concepts.md         # tools / resources / prompts / capabilities
    ├── client-concepts.md         # sessions, discovery, sampling
    ├── transports.md              # stdio, Streamable HTTP, SSE
    ├── fastmcp.md                 # v1 decorator API, Context object
    ├── mcpserver.md               # v2 pre-alpha rename, run()-based transport
    ├── migration-v1-to-v2.md      # breaking-change table, rename map
    ├── low-level-server.md        # raw Server, when to drop FastMCP
    ├── build-server.md            # end-to-end server build recipe
    ├── build-client.md            # end-to-end client build recipe
    ├── authorization.md           # OAuth 2.1, PKCE, PRM, scope handling
    ├── experimental-tasks.md      # long-running job primitives
    ├── testing.md                 # in-process Client(server), pytest fixture
    └── specification-pointers.md  # pointers to the spec for deep dives
```

## When the skill fires

- Code imports `mcp`, `mcp.server`, or `mcp.client`.
- User asks to build or debug an MCP server or client in Python.
- FastMCP / MCPServer decorators appear in the codebase.

## When it should NOT fire

- TypeScript / JavaScript MCP SDK — different package, different idioms.
- Consuming an MCP server as a Claude Code user (not a builder).
- Raw JSON-RPC over stdio without the SDK.
