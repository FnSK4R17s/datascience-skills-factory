# Build a Server — Tutorial Patterns

Sources: `docs/mcpio__docs__develop__build-server.md`

This file distills concrete patterns from the build-a-server tutorial (the
full Python weather server walkthrough) that are not covered in other references.

## Project setup

Use `uv` for dependency management:

```bash
uv init weather
cd weather
uv add "mcp[cli]"
```

Run in development mode (auto-registers with Claude Desktop):

```bash
mcp dev server.py
```

## Logging rules for stdio servers

**Never write to stdout** in a stdio server. Any `print()` or other stdout write
corrupts the JSON-RPC stream and silently breaks communication.

```python
# Bad (stdio): corrupts stream
print("Starting up")

# Good (stdio): safe
import sys
print("Starting up", file=sys.stderr)

# Good (all transports): use structured SDK logging via ctx
await ctx.info("Starting up")
```

For HTTP-transport servers, stdout is fine since it doesn't interfere with
HTTP responses.

## The typical FastMCP server skeleton

```python
from mcp.server.fastmcp import FastMCP

mcp = FastMCP("WeatherServer")

@mcp.tool()
async def get_forecast(city: str) -> str:
    """Get weather forecast for a city."""
    # call external API here
    return f"Sunny in {city}, 22C"

@mcp.resource("weather://alerts/{state}")
async def get_alerts(state: str) -> str:
    """Get active weather alerts for a state."""
    return f"No active alerts for {state}"

if __name__ == "__main__":
    mcp.run()  # defaults to stdio
```

## Connecting to Claude Desktop

After running in dev mode, or to install permanently, add to
`claude_desktop_config.json`:

```json
{
  "mcpServers": {
    "weather": {
      "command": "uv",
      "args": ["run", "--with", "mcp", "weather.py"]
    }
  }
}
```

- macOS: `~/Library/Application Support/Claude/claude_desktop_config.json`
- Windows: `%APPDATA%\Claude\claude_desktop_config.json`

Always use absolute paths for the server path, not relative ones. The working
directory when launched by Claude Desktop may be undefined.

Environment variables for the server go in the `env` key:

```json
{
  "mcpServers": {
    "weather": {
      "command": "uv",
      "args": ["run", "weather.py"],
      "env": {"WEATHER_API_KEY": "..."}
    }
  }
}
```

## Running as HTTP server

```python
if __name__ == "__main__":
    mcp.run(transport="streamable-http")
    # listens at http://localhost:8000/mcp by default
```

Add to Claude Code:
```bash
claude mcp add --transport http my-server http://localhost:8000/mcp
```

## Debugging checklist

1. Use MCP Inspector first: `npx @modelcontextprotocol/inspector uv run server.py`
2. Check logs in Claude Desktop at `~/Library/Logs/Claude/mcp*.log` (macOS)
3. Look for `-32602` errors in logs — often means capability negotiation mismatch
   (e.g. server sent sampling/elicitation to a client that didn't declare it)
4. Always restart Claude Desktop fully after config changes — closing the window
   is not enough
