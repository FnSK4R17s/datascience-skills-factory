# MCP Integration

Source: `docs/mcp.md`

## Overview

LangChain agents can use tools defined on any MCP (Model Context Protocol) server via the
`langchain-mcp-adapters` library. `MultiServerMCPClient` connects to one or more servers
and returns their tools as standard LangChain tools.

## Installation

```bash
pip install langchain-mcp-adapters
pip install fastmcp  # to author custom MCP servers
```

## Quickstart

```python
import asyncio
from langchain_mcp_adapters.client import MultiServerMCPClient
from langchain.agents import create_agent

async def main():
    client = MultiServerMCPClient({
        "math": {
            "transport": "stdio",       # local subprocess
            "command": "python",
            "args": ["/path/to/math_server.py"],
        },
        "weather": {
            "transport": "http",        # remote HTTP server
            "url": "http://localhost:8000/mcp",
        },
    })

    tools = await client.get_tools()
    agent = create_agent("claude-sonnet-4-6", tools)

    result = await agent.ainvoke(
        {"messages": [{"role": "user", "content": "What is (3 + 5) x 12?"}]}
    )
    print(result["messages"][-1].text)

asyncio.run(main())
```

`MultiServerMCPClient` is stateless by default — each tool invocation creates a fresh
`ClientSession`. Use the stateful session context manager for calls that need continuity.

## Stateful sessions

```python
async with client.session("math") as session:
    tools = await session.get_tools()
    # All calls within this block share the same session
```

## Custom MCP servers (FastMCP)

```python
from fastmcp import FastMCP

mcp = FastMCP("MyServer")

@mcp.tool()
def add(a: int, b: int) -> int:
    """Add two numbers."""
    return a + b

if __name__ == "__main__":
    mcp.run(transport="stdio")
```

Run as `python math_server.py` and reference it with `transport: "stdio"` in the client.

## Transport options

| Transport | Use case | Config keys |
|-----------|----------|-------------|
| `stdio` | Local subprocess | `command`, `args`, `env` |
| `http` | Remote HTTP server | `url` |
| `sse` | Server-sent events stream | `url` |

## Tool naming

MCP tool names follow the server's naming. Use `always_include` in
`LLMToolSelectorMiddleware` to ensure critical MCP tools are always available
even when the LLM tool selector filters the list.

## Notes

- MCP tools appear identically to regular `@tool`-decorated functions from the agent's perspective.
- For runtime-discovered MCP tools (e.g., loaded per-request), use `DynamicToolMiddleware`
  pattern with `wrap_model_call` + `wrap_tool_call` hooks (see `references/middleware.md`).
