# Build a Server — End-to-End Tutorial

Sources: `docs/mcpio__docs__develop__build-server.md`, `docs/README.md`

This file covers concrete end-to-end patterns for building a real MCP server
from scratch, wiring it to Claude Desktop or Claude Code, and debugging it.

## Project setup (uv — recommended)

```bash
uv init weather-server
cd weather-server
uv add "mcp[cli]" httpx

# Or for pip-based projects:
pip install "mcp[cli]" httpx
```

## Complete weather server example

This server fetches real weather data and exposes tools and resources:

```python
"""Weather MCP server — exposes weather tools and resources."""

import sys
from mcp.server.fastmcp import FastMCP, Context

mcp = FastMCP("WeatherServer")

# Real-world note: use an actual weather API (OpenWeatherMap, WeatherAPI, etc.)
# and store the API key in an environment variable
WEATHER_DATA = {
    "london": {"temp": 15, "condition": "cloudy", "humidity": 75},
    "paris": {"temp": 18, "condition": "sunny", "humidity": 60},
    "new york": {"temp": 22, "condition": "partly cloudy", "humidity": 55},
}


@mcp.tool()
async def get_forecast(city: str, ctx: Context) -> dict[str, str]:
    """Get weather forecast for a city.

    Returns temperature (Celsius), weather condition, and humidity.
    """
    city_lower = city.lower()
    await ctx.info(f"Looking up weather for: {city}")

    data = WEATHER_DATA.get(city_lower)
    if not data:
        raise ValueError(f"No weather data for '{city}'. Try: London, Paris, New York")

    return {
        "city": city,
        "temperature_c": str(data["temp"]),
        "condition": data["condition"],
        "humidity_pct": str(data["humidity"]),
    }


@mcp.tool()
async def compare_weather(city1: str, city2: str, ctx: Context) -> str:
    """Compare weather between two cities."""
    await ctx.info(f"Comparing weather: {city1} vs {city2}")

    data1 = WEATHER_DATA.get(city1.lower())
    data2 = WEATHER_DATA.get(city2.lower())

    if not data1:
        raise ValueError(f"No weather data for '{city1}'")
    if not data2:
        raise ValueError(f"No weather data for '{city2}'")

    warmer = city1 if data1["temp"] > data2["temp"] else city2
    diff = abs(data1["temp"] - data2["temp"])

    return (
        f"{city1}: {data1['temp']}°C, {data1['condition']}\n"
        f"{city2}: {data2['temp']}°C, {data2['condition']}\n"
        f"{warmer} is warmer by {diff}°C"
    )


@mcp.resource("weather://alerts/{city}")
async def get_alerts(city: str) -> str:
    """Get active weather alerts for a city."""
    # In production: call a weather API
    return f"No active weather alerts for {city}"


@mcp.resource("weather://forecast/cities")
def list_available_cities() -> str:
    """List all cities with available weather data."""
    cities = list(WEATHER_DATA.keys())
    return ", ".join(c.title() for c in cities)


@mcp.prompt(title="Weather Report")
def weather_report_prompt(city: str) -> str:
    """Generate a prompt requesting a weather report."""
    return f"Please provide a detailed weather report for {city}, including any relevant travel advice."


if __name__ == "__main__":
    # Use stdio for Claude Desktop / Claude Code integration
    # Use streamable-http for remote/multi-client deployment
    import sys
    if "--http" in sys.argv:
        mcp.run(transport="streamable-http")
    else:
        mcp.run()  # stdio default
```

## Logging rules for stdio servers

**Never write to stdout** in a stdio server. Any `print()` or other stdout
write corrupts the JSON-RPC stream and silently breaks communication.

```python
# WRONG — corrupts the stream
print("Starting weather server")
logging.basicConfig()  # also writes to stdout by default

# CORRECT — write to stderr
import sys
print("Starting weather server", file=sys.stderr)

# CORRECT — use structured SDK logging via Context
@mcp.tool()
async def my_tool(ctx: Context) -> str:
    await ctx.info("Tool called")     # sends MCP log notification
    await ctx.debug("Verbose debug")  # only if client has requested debug level
    return "done"

# CORRECT — configure Python logging to go to stderr
import logging
logging.basicConfig(stream=sys.stderr, level=logging.INFO)
logger = logging.getLogger(__name__)
logger.info("This is safe")
```

For HTTP-transport servers, stdout is fine since it doesn't interfere with
HTTP responses.

## Development workflow

```bash
# Fastest iteration: open in MCP Inspector UI
uv run mcp dev server.py

# Add extra dependencies for dev
uv run mcp dev server.py --with pandas --with numpy

# Mount local editable code
uv run mcp dev server.py --with-editable .

# The Inspector opens at http://localhost:5173
# You can invoke tools, read resources, test prompts without any client code
```

## Claude Desktop integration

### Install permanently

```bash
uv run mcp install server.py
uv run mcp install server.py --name "Weather Server"
uv run mcp install server.py -v WEATHER_API_KEY=abc123
uv run mcp install server.py -f .env  # load env vars from .env file
```

### Manual configuration

Edit `claude_desktop_config.json`:
- macOS: `~/Library/Application Support/Claude/claude_desktop_config.json`
- Windows: `%APPDATA%\Claude\claude_desktop_config.json`

```json
{
  "mcpServers": {
    "weather": {
      "command": "uv",
      "args": [
        "run",
        "--with", "mcp",
        "--with", "httpx",
        "/absolute/path/to/server.py"
      ],
      "env": {
        "WEATHER_API_KEY": "your-key-here"
      }
    }
  }
}
```

Rules for the config:
- **Always use absolute paths** — Claude Desktop's working directory is
  undefined. Relative paths will fail silently.
- **Always restart fully** after config changes — Quit from the application
  menu, not just close the window.
- Put env vars in the `env` key — stdio servers inherit a limited env.

### Using a virtual environment directly

```json
{
  "mcpServers": {
    "weather": {
      "command": "/absolute/path/to/project/.venv/bin/python",
      "args": ["/absolute/path/to/server.py"],
      "env": {"WEATHER_API_KEY": "..."}
    }
  }
}
```

### Running without uv (pip-installed)

```json
{
  "mcpServers": {
    "weather": {
      "command": "python",
      "args": ["/absolute/path/to/server.py"]
    }
  }
}
```

## Claude Code integration (HTTP transport)

First, run the server:
```bash
uv run server.py --http
# Or: python server.py --http
```

Then register with Claude Code:
```bash
claude mcp add --transport http weather-server http://localhost:8000/mcp

# With custom path
claude mcp add --transport http weather-server http://localhost:9000/api/mcp
```

## Running as HTTP server

```python
if __name__ == "__main__":
    # Recommended for production: stateless + JSON responses
    mcp = FastMCP("WeatherServer", stateless_http=True, json_response=True)
    mcp.run(transport="streamable-http")
    # Serves at http://127.0.0.1:8000/mcp
```

For Docker/container deployments:
```python
mcp.run(transport="streamable-http", host="0.0.0.0", port=8080)
```

## Server with database lifespan

A more realistic server pattern with a shared database connection:

```python
import sys
import json
import sqlite3
from collections.abc import AsyncIterator
from contextlib import asynccontextmanager
from dataclasses import dataclass

from mcp.server.fastmcp import FastMCP, Context
from mcp.server.session import ServerSession


@dataclass
class AppContext:
    db: sqlite3.Connection


@asynccontextmanager
async def lifespan(server: FastMCP) -> AsyncIterator[AppContext]:
    """Initialize database connection on startup."""
    db = sqlite3.connect(":memory:")
    db.execute(
        "CREATE TABLE notes (id INTEGER PRIMARY KEY, title TEXT, content TEXT)"
    )
    db.execute("INSERT INTO notes (title, content) VALUES ('First Note', 'Hello!')")
    db.commit()
    print("Database initialized", file=sys.stderr)
    try:
        yield AppContext(db=db)
    finally:
        db.close()
        print("Database closed", file=sys.stderr)


mcp = FastMCP("Notes Server", lifespan=lifespan)


@mcp.tool()
def list_notes(ctx: Context[ServerSession, AppContext]) -> list[dict]:
    """List all notes."""
    app: AppContext = ctx.request_context.lifespan_context
    cursor = app.db.execute("SELECT id, title FROM notes")
    return [{"id": row[0], "title": row[1]} for row in cursor.fetchall()]


@mcp.tool()
def get_note(note_id: int, ctx: Context[ServerSession, AppContext]) -> dict:
    """Get a note by ID."""
    app: AppContext = ctx.request_context.lifespan_context
    cursor = app.db.execute(
        "SELECT id, title, content FROM notes WHERE id = ?",
        (note_id,),
    )
    row = cursor.fetchone()
    if not row:
        raise ValueError(f"Note {note_id} not found")
    return {"id": row[0], "title": row[1], "content": row[2]}


@mcp.tool()
async def create_note(
    title: str,
    content: str,
    ctx: Context[ServerSession, AppContext],
) -> dict:
    """Create a new note."""
    app: AppContext = ctx.request_context.lifespan_context
    cursor = app.db.execute(
        "INSERT INTO notes (title, content) VALUES (?, ?)",
        (title, content),
    )
    app.db.commit()
    await ctx.session.send_resource_list_changed()  # notify clients
    return {"id": cursor.lastrowid, "title": title}


@mcp.resource("notes://{note_id}")
def read_note_resource(note_id: str, ctx: Context[ServerSession, AppContext]) -> str:
    """Read a note as a resource."""
    app: AppContext = ctx.request_context.lifespan_context
    cursor = app.db.execute(
        "SELECT title, content FROM notes WHERE id = ?",
        (int(note_id),),
    )
    row = cursor.fetchone()
    if not row:
        raise ValueError(f"Note {note_id} not found")
    return json.dumps({"title": row[0], "content": row[1]}, indent=2)


if __name__ == "__main__":
    mcp.run()
```

## Debugging checklist

1. **Use MCP Inspector first:**
   ```bash
   npx @modelcontextprotocol/inspector uv run server.py
   ```
   This lets you invoke tools and read resources without any client code.

2. **Check Claude Desktop logs** (macOS):
   ```bash
   tail -f ~/Library/Logs/Claude/mcp*.log
   ```
   On Windows: `%APPDATA%\Claude\Logs\mcp*.log`

3. **Look for `-32602` in logs** — usually a capability negotiation mismatch,
   e.g., server sent `sampling/createMessage` to a client that didn't declare
   `sampling` capability.

4. **Verify stdout is clean** — add a startup log to stderr and verify it
   appears in logs without corrupting the protocol.

5. **Test env vars** — stdio servers inherit limited env. Add a tool that
   returns `os.environ.get("MY_KEY", "NOT SET")` to debug missing vars.

6. **Always restart fully** — closing the Claude Desktop window is not enough.
   Use Quit from the application menu.
