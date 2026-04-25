# FastMCP — High-Level Server API (v1)

Sources: `docs/README.md`, `docs/mcpio__docs__develop__build-server.md`,
`docs/migration.md`

FastMCP (`mcp.server.fastmcp.FastMCP`) is the recommended starting point for
all new MCP servers. It handles capability declaration, JSON Schema generation
from type annotations, error wrapping, and transport configuration. Both sync
and async functions are supported everywhere.

## Minimal server

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
    return f"Please write a {style} greeting for someone named {name}."

if __name__ == "__main__":
    mcp.run(transport="streamable-http")
```

## Tool registration

FastMCP infers JSON Schema from Python type annotations. The function docstring
becomes the tool description. Both sync and async are supported.

### Simple tools

```python
from mcp.server.fastmcp import FastMCP

mcp = FastMCP("Tool Example")

@mcp.tool()
def sum_numbers(a: int, b: int) -> int:
    """Add two numbers together."""
    return a + b

@mcp.tool()
def get_weather(city: str, unit: str = "celsius") -> str:
    """Get weather for a city. unit: 'celsius' or 'fahrenheit'."""
    # Call external API here
    return f"Weather in {city}: 22 degrees {unit[0].upper()}"

@mcp.tool()
async def fetch_url(url: str) -> str:
    """Fetch content from a URL."""
    import httpx
    async with httpx.AsyncClient() as client:
        resp = await client.get(url)
        return resp.text
```

### Annotated parameters with Field descriptions

```python
from typing import Annotated
from pydantic import Field

@mcp.tool()
def search_documents(
    query: Annotated[str, Field(description="Search query string")],
    limit: Annotated[int, Field(description="Max results to return", ge=1, le=100)] = 10,
    include_archived: bool = False,
) -> list[str]:
    """Search the document database."""
    # ... search logic
    return [f"Result {i} for '{query}'" for i in range(limit)]
```

### Structured output — Pydantic models

When the return type annotation is a Pydantic `BaseModel`, `TypedDict`,
dataclass with type hints, or `dict[str, T]`, FastMCP auto-generates
`outputSchema` and validates the return value.

```python
from pydantic import BaseModel, Field
from typing import TypedDict

class WeatherData(BaseModel):
    temperature: float = Field(description="Temperature in Celsius")
    humidity: float = Field(description="Humidity percentage")
    condition: str
    wind_speed: float

@mcp.tool()
def get_weather_structured(city: str) -> WeatherData:
    """Get weather for a city — returns structured data."""
    return WeatherData(
        temperature=22.5,
        humidity=45.0,
        condition="sunny",
        wind_speed=5.2,
    )

class LocationInfo(TypedDict):
    latitude: float
    longitude: float
    name: str

@mcp.tool()
def get_location(address: str) -> LocationInfo:
    """Get location coordinates for an address."""
    return LocationInfo(latitude=51.5074, longitude=-0.1278, name="London, UK")

@mcp.tool()
def get_statistics(data_type: str) -> dict[str, float]:
    """Get statistics — dict[str, T] also generates outputSchema."""
    return {"mean": 42.5, "median": 40.0, "std_dev": 5.2}
```

Primitive return types (`str`, `int`, `float`, `bool`) and generic containers
(`list`, `tuple`, `Union`) are wrapped in `{"result": value}`.

To suppress structured output on a typed return:

```python
@mcp.tool(structured_output=False)
def get_user_raw(user_id: str) -> dict:
    """Returns unstructured output despite dict return type."""
    return {"name": "Alice", "age": 30}
```

### Direct CallToolResult — full protocol control

Use `CallToolResult` when you need the `_meta` field (data passed to the client
application without being exposed to the model):

```python
from mcp.types import CallToolResult, TextContent

@mcp.tool()
def advanced_tool(message: str) -> CallToolResult:
    """Return CallToolResult directly for full control."""
    return CallToolResult(
        content=[TextContent(type="text", text=f"Response visible to model: {message}")],
        _meta={"hidden": "data for client applications only, not shown to model"},
    )

@mcp.tool()
def empty_result_tool() -> CallToolResult:
    """Tool that returns nothing."""
    return CallToolResult(content=[])
```

Rules:
- `CallToolResult` must be the direct return type — no `Optional[CallToolResult]`
- For empty results: `CallToolResult(content=[])`
- For optional simple types: use `str | None` (not `Optional[CallToolResult]`)

## Resource registration

Resources are read-only data sources loaded into context by the application
(not by the model). Two patterns:

### Static URI (no parameters)

```python
@mcp.resource("config://settings")
def get_settings() -> str:
    """Get application settings as JSON."""
    return '{"theme": "dark", "language": "en", "debug": false}'

@mcp.resource("config://settings", mime_type="application/json")
def get_settings_typed() -> str:
    return '{"theme": "dark"}'
```

### Dynamic URI template (parameters from URI)

```python
@mcp.resource("file://documents/{name}")
def read_document(name: str) -> str:
    """Read a document by name."""
    # This would normally read from disk
    return f"Content of document: {name}"

@mcp.resource("users://{user_id}/profile")
async def get_user_profile(user_id: str) -> str:
    """Get a user profile by ID."""
    # async resources are supported
    return f"Profile for user {user_id}"

@mcp.resource("weather://alerts/{state}")
async def get_alerts(state: str) -> str:
    """Get active weather alerts for a state."""
    return f"No active alerts for {state}"
```

FastMCP maps URI template parameters to function arguments automatically.

## Prompt registration

Prompts are parameterized instruction templates invoked by users (not the model).

```python
from mcp.server.fastmcp.prompts import base

@mcp.prompt(title="Code Review")
def review_code(code: str) -> str:
    """Generate a code review prompt."""
    return f"Please review this code:\n\n{code}"

@mcp.prompt(title="Debug Assistant")
def debug_error(error: str, context: str = "") -> list[base.Message]:
    """Generate a debugging prompt with multi-turn messages."""
    messages = [
        base.UserMessage("I'm seeing this error:"),
        base.UserMessage(error),
    ]
    if context:
        messages.append(base.UserMessage(f"Context: {context}"))
    messages.append(base.AssistantMessage("I'll help debug that. What have you tried so far?"))
    return messages

@mcp.prompt()
def summarize_document(content: str, style: str = "brief") -> str:
    """Request a document summary in a given style."""
    return f"Please provide a {style} summary of:\n\n{content}"
```

## Context object

Add `ctx: Context` (any name, typed `Context`) to any tool or resource handler.
The framework injects it automatically — do not instantiate it yourself.

```python
from mcp.server.fastmcp import Context, FastMCP

mcp = FastMCP("Context Example")

@mcp.tool()
async def long_running_task(
    task_name: str,
    ctx: Context,
    steps: int = 5,
) -> str:
    """Run a task with progress reporting and logging."""
    await ctx.info(f"Starting task: {task_name}")

    for i in range(steps):
        progress = (i + 1) / steps
        await ctx.report_progress(
            progress=progress,
            total=1.0,
            message=f"Step {i + 1}/{steps}",
        )
        await ctx.debug(f"Completed step {i + 1}")

    await ctx.info(f"Task '{task_name}' complete")
    return f"Task '{task_name}' completed successfully"

@mcp.tool()
async def read_and_process(resource_uri: str, ctx: Context) -> str:
    """Read a resource from within a tool handler."""
    content = await ctx.read_resource(resource_uri)
    return f"Processed: {content}"
```

### Context properties

- `ctx.request_id` — unique ID for the current request
- `ctx.client_id` — client ID if available
- `ctx.fastmcp` — the `FastMCP` server instance
  - `ctx.fastmcp.name` — server name
  - `ctx.fastmcp.settings` — server configuration (`debug`, `log_level`, `host`, `port`, etc.)
- `ctx.session` — raw `ServerSession` for advanced use
- `ctx.request_context` — request-specific data and lifespan state
  - `ctx.request_context.lifespan_context` — typed startup resources
  - `ctx.request_context.meta` — request metadata (progressToken, etc.)

### Context logging methods

```python
await ctx.debug("Detailed diagnostic info")
await ctx.info("Normal operational info")
await ctx.warning("Something unexpected but recoverable")
await ctx.error("Something failed")
await ctx.log(level="notice", message="All 8 RFC-5424 levels supported")
```

### Session methods (via ctx.session)

```python
# Notify clients that lists have changed
await ctx.session.send_resource_list_changed()
await ctx.session.send_tool_list_changed()
await ctx.session.send_prompt_list_changed()

# Notify that a specific resource changed
await ctx.session.send_resource_updated(resource_uri)

# Direct log message with full control
await ctx.session.send_log_message(level="info", data="Server started", logger="my.logger")
```

## Lifespan (startup/teardown)

Use lifespan for database connections, caches, and shared resources that need
to be initialized once and cleaned up on shutdown.

```python
from collections.abc import AsyncIterator
from contextlib import asynccontextmanager
from dataclasses import dataclass

from mcp.server.fastmcp import Context, FastMCP
from mcp.server.session import ServerSession


class Database:
    @classmethod
    async def connect(cls) -> "Database":
        print("Database connected", file=sys.stderr)
        return cls()

    async def disconnect(self) -> None:
        print("Database disconnected", file=sys.stderr)

    def query(self, sql: str) -> list[dict]:
        return [{"id": 1, "result": sql}]


@dataclass
class AppContext:
    db: Database
    config: dict


@asynccontextmanager
async def app_lifespan(server: FastMCP) -> AsyncIterator[AppContext]:
    """Manage application lifecycle with type-safe context."""
    db = await Database.connect()
    config = {"max_results": 100, "timeout": 30}
    try:
        yield AppContext(db=db, config=config)
    finally:
        await db.disconnect()


mcp = FastMCP("My App", lifespan=app_lifespan)


@mcp.tool()
def query_db(sql: str, ctx: Context[ServerSession, AppContext]) -> str:
    """Execute a database query using the shared connection."""
    app_ctx: AppContext = ctx.request_context.lifespan_context
    results = app_ctx.db.query(sql)
    max_r = app_ctx.config["max_results"]
    return str(results[:max_r])
```

The lifespan function receives the `FastMCP` server and must yield the context
object. Cleanup runs in the `finally` block.

## Elicitation — requesting user input mid-tool

Tools can pause execution and request structured input from the user:

```python
from pydantic import BaseModel, Field
from mcp.server.fastmcp import Context, FastMCP
from mcp.shared.exceptions import UrlElicitationRequiredError
from mcp.types import ElicitRequestURLParams
import uuid

mcp = FastMCP("Elicitation Example")


class BookingPreferences(BaseModel):
    check_alternative: bool = Field(description="Would you like to check another date?")
    alternative_date: str = Field(
        default="2024-12-26",
        description="Alternative date (YYYY-MM-DD)",
    )


@mcp.tool()
async def book_table(date: str, party_size: int, ctx: Context) -> str:
    """Book a table, with elicitation if date is unavailable."""
    if date == "2024-12-25":
        result = await ctx.elicit(
            message=f"No tables available for {party_size} on {date}. Try another date?",
            schema=BookingPreferences,
        )

        if result.action == "accept" and result.data:
            if result.data.check_alternative:
                return f"Booked for {result.data.alternative_date}"
            return "No booking made"
        return "Booking cancelled"

    return f"Booked for {date}"


@mcp.tool()
async def secure_payment(amount: float, ctx: Context) -> str:
    """Process payment requiring URL confirmation (URL-mode elicitation)."""
    elicitation_id = str(uuid.uuid4())

    result = await ctx.elicit_url(
        message=f"Please confirm payment of ${amount:.2f}",
        url=f"https://payments.example.com/confirm?amount={amount}&id={elicitation_id}",
        elicitation_id=elicitation_id,
    )

    if result.action == "accept":
        return f"Payment of ${amount:.2f} initiated"
    elif result.action == "decline":
        return "Payment declined by user"
    return "Payment cancelled"


@mcp.tool()
async def connect_oauth_service(service_name: str, ctx: Context) -> str:
    """Connect to a service requiring OAuth — raises error pattern."""
    elicitation_id = str(uuid.uuid4())
    # Raising UrlElicitationRequiredError converts to -32042 error response
    # telling the client to complete the URL flow before retrying.
    raise UrlElicitationRequiredError([
        ElicitRequestURLParams(
            mode="url",
            message=f"Authorization required to connect to {service_name}",
            url=f"https://{service_name}.example.com/oauth/authorize?id={elicitation_id}",
            elicitationId=elicitation_id,
        )
    ])
```

`ElicitationResult` fields: `action` ("accept", "decline", "cancel"),
`data` (validated Pydantic model, only on accept), `validation_error`.

Privacy rule: elicitation must never request passwords or API keys.

## Sampling — requesting LLM completions through the client

Servers can request LLM completions through the host's model. The client
controls user approval, model selection, and access.

```python
from mcp.types import SamplingMessage, TextContent


@mcp.tool()
async def generate_poem(topic: str, ctx: Context) -> str:
    """Generate a poem by requesting an LLM completion via the client."""
    result = await ctx.session.create_message(
        messages=[
            SamplingMessage(
                role="user",
                content=TextContent(type="text", text=f"Write a short poem about {topic}"),
            )
        ],
        max_tokens=200,
    )

    if result.content.type == "text":
        return result.content.text
    return str(result.content)


@mcp.tool()
async def analyze_sentiment(text: str, ctx: Context) -> str:
    """Analyze sentiment using LLM sampling."""
    result = await ctx.session.create_message(
        messages=[
            SamplingMessage(
                role="user",
                content=TextContent(
                    type="text",
                    text=f"Classify the sentiment of this text as positive/negative/neutral. "
                         f"Reply with only one word.\n\nText: {text}",
                ),
            )
        ],
        max_tokens=10,
    )
    if result.content.type == "text":
        return result.content.text.strip().lower()
    return "unknown"
```

The client must have declared `sampling` capability during initialization. If
it has not, `create_message` will raise a protocol error.

## Composition and mounting

Mount sub-servers to split a large server into logical modules. Tools get
prefixed with the mount name.

```python
main = FastMCP("Main Server")

# Sub-server for math operations
math = FastMCP("Math")

@math.tool()
def multiply(a: int, b: int) -> int:
    """Multiply two numbers."""
    return a * b

@math.tool()
def divide(a: float, b: float) -> float:
    """Divide a by b."""
    if b == 0:
        raise ValueError("Cannot divide by zero")
    return a / b

# Sub-server for text operations
text = FastMCP("Text")

@text.tool()
def uppercase(s: str) -> str:
    """Convert string to uppercase."""
    return s.upper()

# Mount both — tools become "math/multiply", "math/divide", "text/uppercase"
main.mount("math", math)
main.mount("text", text)

if __name__ == "__main__":
    main.run(transport="streamable-http")
```

Mounted servers share the parent's transport.

## Images and binary content

```python
from mcp.server.fastmcp import FastMCP, Image

mcp = FastMCP("Image Example")


@mcp.tool()
def create_thumbnail(image_path: str) -> Image:
    """Create a thumbnail from an image file."""
    from PIL import Image as PILImage
    img = PILImage.open(image_path)
    img.thumbnail((100, 100))
    # Image class handles base64 encoding automatically
    return Image(data=img.tobytes(), format="png")


@mcp.tool()
def get_chart(data: list[float]) -> Image:
    """Generate a bar chart from numeric data."""
    import io
    import matplotlib.pyplot as plt

    fig, ax = plt.subplots()
    ax.bar(range(len(data)), data)
    buf = io.BytesIO()
    fig.savefig(buf, format="png")
    buf.seek(0)
    return Image(data=buf.read(), format="png")
```

## Icons

```python
from mcp.server.fastmcp import FastMCP, Icon

icon = Icon(src="https://example.com/icon.png", mimeType="image/png", sizes="64x64")

mcp = FastMCP(
    "My Server",
    website_url="https://example.com",
    icons=[icon],
)

@mcp.tool(icons=[icon])
def my_tool() -> str:
    """Tool with an icon for UI display."""
    return "result"

@mcp.resource("demo://resource", icons=[icon])
def my_resource() -> str:
    """Resource with an icon."""
    return "content"
```

Icons must use HTTPS or `data:` URIs.

## Running the server

### stdio (default — for Claude Desktop and local tools)

```python
if __name__ == "__main__":
    mcp.run()  # defaults to stdio
```

### Streamable HTTP (recommended for production)

```python
# Stateless — recommended for scalability
mcp = FastMCP("StatelessServer", stateless_http=True, json_response=True)

if __name__ == "__main__":
    mcp.run(transport="streamable-http")
    # Serves at http://127.0.0.1:8000/mcp by default
```

### Custom host/port and path

```python
if __name__ == "__main__":
    mcp.run(
        transport="streamable-http",
        host="0.0.0.0",
        port=9000,
        # streamable_http_path="/api/mcp",  # custom path
    )
```

### Mounting to an existing ASGI app (Starlette/FastAPI)

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

# Configure servers to mount at the root of each path
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
# Clients connect to http://localhost:8000/echo and http://localhost:8000/math
```

### CORS for browser clients

```python
from starlette.middleware.cors import CORSMiddleware

starlette_app = CORSMiddleware(
    starlette_app,
    allow_origins=["*"],  # restrict in production
    allow_methods=["GET", "POST", "DELETE"],
    expose_headers=["Mcp-Session-Id"],  # required for browser clients to read session ID
)
```

### Host-based routing

```python
from starlette.routing import Host

app = Starlette(
    routes=[
        Host("mcp.acme.corp", app=mcp.streamable_http_app()),
    ],
    lifespan=lifespan,
)
```

### SSE transport (deprecated — prefer Streamable HTTP)

```python
mcp.run(transport="sse")  # still works, not recommended for new code
```

## Development tools

```bash
# Run with MCP Inspector UI (fastest for iteration)
uv run mcp dev server.py

# Add dependencies during dev
uv run mcp dev server.py --with pandas --with numpy

# Install in Claude Desktop
uv run mcp install server.py
uv run mcp install server.py --name "My Analytics Server"
uv run mcp install server.py -v API_KEY=abc123 -f .env
```

## Claude Desktop integration

After running in dev mode or to install permanently, add to
`claude_desktop_config.json`:

```json
{
  "mcpServers": {
    "weather": {
      "command": "uv",
      "args": ["run", "--with", "mcp", "/absolute/path/to/server.py"],
      "env": {"WEATHER_API_KEY": "your-key-here"}
    }
  }
}
```

- macOS: `~/Library/Application Support/Claude/claude_desktop_config.json`
- Windows: `%APPDATA%\Claude\claude_desktop_config.json`
- Always use absolute paths — Claude Desktop's working directory is undefined.
- Always restart Claude Desktop fully after config changes (Quit, not close).

## Claude Code integration (HTTP)

```bash
claude mcp add --transport http my-server http://localhost:8000/mcp
```

## When to leave FastMCP for the low-level API

- Need custom request/response interception at the protocol level.
- Need handlers not supported by FastMCP decorators: `subscribe_resource`,
  `set_logging_level` (workaround: `mcp._lowlevel_server._add_request_handler`).
- Need middleware wrapping every incoming message.
- Prefer explicit control over capability negotiation.

See `references/low-level-server.md`.
