# Tools

Source: `docs/tools.md`, `docs/agents.md`

Tools extend what agents can do — letting them fetch real-time data, execute code, query
databases, and take actions. Under the hood, tools are callable functions with well-defined
inputs and outputs that get passed to a chat model. The model decides when to invoke a tool
and what arguments to provide.

## Create tools

### Basic tool definition

```python
from langchain.tools import tool

@tool
def search_database(query: str, limit: int = 10) -> str:
    """Search the customer database for records matching the query.

    Args:
        query: Search terms to look for
        limit: Maximum number of results to return
    """
    return f"Found {limit} results for '{query}'"
```

Type hints are **required** — they define the tool's input schema passed to the model.
The docstring becomes the tool's description. Keep it informative and concise.

**Naming:** use `snake_case`. Some providers reject names with spaces or special characters.

### Custom tool name and description

```python
# Override the name (defaults to function name)
@tool("web_search")
def search(query: str) -> str:
    """Search the web for information."""
    return f"Results for: {query}"

# Override both name and description
@tool("calculator", description="Performs arithmetic calculations. Use for any math problems.")
def calc(expression: str) -> str:
    """Evaluate mathematical expressions."""
    return str(eval(expression))  # noqa: S307

print(search.name)  # "web_search"
```

### Advanced schema definition with Pydantic

```python
from pydantic import BaseModel, Field
from typing import Literal

class WeatherInput(BaseModel):
    """Input for weather queries."""
    location: str = Field(description="City name or 'City, Country' for disambiguation")
    units: Literal["celsius", "fahrenheit"] = Field(
        default="celsius",
        description="Temperature unit preference"
    )
    include_forecast: bool = Field(
        default=False,
        description="Whether to include a 5-day forecast"
    )

@tool(args_schema=WeatherInput)
def get_weather(location: str, units: str = "celsius", include_forecast: bool = False) -> str:
    """Get current weather and optional forecast for a location."""
    temp = 22 if units == "celsius" else 72
    result = f"Current weather in {location}: {temp} degrees {units[0].upper()}"
    if include_forecast:
        result += "\nNext 5 days: Sunny, Cloudy, Rain, Sunny, Sunny"
    return result
```

### Advanced schema with JSON Schema dict

```python
weather_schema = {
    "type": "object",
    "properties": {
        "location": {"type": "string", "description": "City name"},
        "units": {
            "type": "string",
            "enum": ["celsius", "fahrenheit"],
            "description": "Temperature unit"
        },
    },
    "required": ["location"],
}

@tool(args_schema=weather_schema)
def get_weather_json(location: str, units: str = "celsius") -> str:
    """Get weather for a location."""
    return f"Sunny in {location}, 22{units[0].upper()}"
```

## Reserved argument names

| Parameter name | Purpose |
| --- | --- |
| `config` | Reserved for passing `RunnableConfig` to tools internally |
| `runtime` | Reserved for `ToolRuntime` parameter |

Using these as tool parameters causes runtime errors. Use `ToolRuntime` to access runtime
information instead.

## Access context with ToolRuntime

`ToolRuntime` is injected automatically and **hidden from the LLM's tool schema**. The
model only sees the other parameters.

```python
from langchain.tools import tool, ToolRuntime

@tool
def my_tool(query: str, runtime: ToolRuntime) -> str:
    """A context-aware tool. The model sees only `query`."""
    # runtime.state      — current conversation state (short-term)
    # runtime.context    — immutable per-run config (user_id, permissions)
    # runtime.store      — persistent cross-conversation memory (long-term)
    # runtime.stream_writer  — emit real-time progress updates
    # runtime.execution_info — thread_id, run_id, node_attempt
    # runtime.server_info    — assistant_id, graph_id, user (on LangGraph Server)
    # runtime.tool_call_id   — unique ID for this tool invocation
    ...
```

### Short-term memory: State

State is the conversation data for the current thread. Access it via `runtime.state`.

```python
from langchain.tools import tool, ToolRuntime
from langchain.messages import HumanMessage

@tool
def get_last_user_message(runtime: ToolRuntime) -> str:
    """Get the most recent message from the user."""
    messages = runtime.state["messages"]
    for message in reversed(messages):
        if isinstance(message, HumanMessage):
            return message.content
    return "No user messages found"

@tool
def get_user_preference(pref_name: str, runtime: ToolRuntime) -> str:
    """Get a user preference value from conversation state."""
    preferences = runtime.state.get("user_preferences", {})
    return preferences.get(pref_name, "Not set")
```

#### Update state from a tool

Return a `Command` to update state fields. Always include a `ToolMessage` so the model
sees confirmation of the tool call:

```python
from langchain.agents import AgentState
from langchain.messages import ToolMessage
from langchain.tools import ToolRuntime, tool
from langgraph.types import Command
from typing_extensions import NotRequired

class CustomState(AgentState):
    user_name: NotRequired[str]
    preferred_language: NotRequired[str]

@tool
def set_user_name(new_name: str, runtime: ToolRuntime[None, CustomState]) -> Command:
    """Set the user's name in the conversation state."""
    return Command(
        update={
            "user_name": new_name,
            "messages": [
                ToolMessage(
                    content=f"User name set to {new_name}.",
                    tool_call_id=runtime.tool_call_id,
                )
            ],
        }
    )

@tool
def set_language(language: str, runtime: ToolRuntime[None, CustomState]) -> Command:
    """Set the preferred response language."""
    return Command(
        update={
            "preferred_language": language,
            "messages": [
                ToolMessage(
                    content=f"Language set to {language}.",
                    tool_call_id=runtime.tool_call_id,
                )
            ],
        }
    )
```

When multiple tools update the same state field in parallel, define a reducer on that field
to resolve conflicts.

### Immutable context: Context

Context is immutable per-invocation data. Pass at invocation time via `context=`.

```python
from dataclasses import dataclass
from langchain.agents import create_agent
from langchain.tools import tool, ToolRuntime

USER_DATABASE = {
    "user123": {"name": "Alice Johnson", "account_type": "Premium", "balance": 5000},
    "user456": {"name": "Bob Smith", "account_type": "Standard", "balance": 1200},
}

@dataclass
class UserContext:
    user_id: str
    api_key: str

@tool
def get_account_info(runtime: ToolRuntime[UserContext]) -> str:
    """Get the current user's account information."""
    user_id = runtime.context.user_id
    if user_id in USER_DATABASE:
        user = USER_DATABASE[user_id]
        return f"Name: {user['name']}, Type: {user['account_type']}, Balance: ${user['balance']}"
    return "User not found"

@tool
def get_permissions(runtime: ToolRuntime[UserContext]) -> str:
    """Get the API permissions for the current user."""
    return f"API key ends in: ...{runtime.context.api_key[-4:]}"

agent = create_agent(
    model="openai:gpt-5.4",
    tools=[get_account_info, get_permissions],
    context_schema=UserContext,
    system_prompt="You are a financial assistant.",
)

result = agent.invoke(
    {"messages": [{"role": "user", "content": "What's my current balance?"}]},
    context=UserContext(user_id="user123", api_key="sk-abc123xyz789"),
)
```

### Long-term memory: Store

The store persists data across conversations. Use `runtime.store` with a
namespace/key pattern.

```python
from typing import Any
from langgraph.store.memory import InMemoryStore  # use PostgresStore in production
from langchain.agents import create_agent
from langchain.tools import tool, ToolRuntime

@tool
def get_user_info(user_id: str, runtime: ToolRuntime) -> str:
    """Look up stored user info."""
    item = runtime.store.get(("users",), user_id)
    return str(item.value) if item else "Unknown user"

@tool
def save_user_info(user_id: str, user_info: dict[str, Any], runtime: ToolRuntime) -> str:
    """Save user info to persistent storage."""
    runtime.store.put(("users",), user_id, user_info)
    return "Successfully saved user info."

@tool
def save_preference(key: str, value: str, runtime: ToolRuntime) -> str:
    """Save a user preference (scoped by context.user_id)."""
    # Namespace by user ID for proper isolation
    user_id = runtime.context.user_id if runtime.context else "global"
    runtime.store.put(("prefs", user_id), key, {"value": value})
    return f"Saved {key}={value}"

@tool
def get_preference(key: str, runtime: ToolRuntime) -> str:
    """Get a saved preference."""
    user_id = runtime.context.user_id if runtime.context else "global"
    item = runtime.store.get(("prefs", user_id), key)
    return item.value["value"] if item else "not set"

store = InMemoryStore()
agent = create_agent(
    model="openai:gpt-5.4",
    tools=[get_user_info, save_user_info, save_preference, get_preference],
    store=store,
)

# First session: save user info
agent.invoke({
    "messages": [{"role": "user", "content": "Save: userid abc123, name Foo, age 25"}]
})

# Second session (different invocation, same store): retrieve
result = agent.invoke({
    "messages": [{"role": "user", "content": "What do you know about user abc123?"}]
})
```

For production, use `PostgresStore`:
```python
from langgraph.store.postgres import PostgresStore

with PostgresStore.from_conn_string("postgresql://user:pass@host/db") as store:
    store.setup()
    agent = create_agent(model, tools, store=store)
```

### Stream writer

Emit real-time progress updates from within a tool. The tool must run within a LangGraph
execution context (i.e., via `agent.stream()` or `agent.invoke()`).

```python
from langchain.tools import tool, ToolRuntime

@tool
def process_large_dataset(dataset_name: str, runtime: ToolRuntime) -> str:
    """Process a large dataset and return summary statistics."""
    writer = runtime.stream_writer

    writer(f"Starting processing of {dataset_name}...")
    # ... do work, emit progress ...
    writer(f"Loaded {dataset_name}: 10,000 records")
    # ... more work ...
    writer("Computing statistics...")
    # ... finish ...
    writer("Done.")
    return f"Processed {dataset_name}: mean=42.3, std=5.1"
```

Consume with `stream_mode="custom"`:
```python
for chunk in agent.stream(
    {"messages": [{"role": "user", "content": "Process sales_data"}]},
    stream_mode="custom",
    version="v2",
):
    if chunk["type"] == "custom":
        print(chunk["data"])  # "Starting processing...", "Loaded...", etc.
```

Alternatively, use `get_stream_writer` from `langgraph.config` (functional approach):
```python
from langgraph.config import get_stream_writer

def process_data(item: str) -> str:
    """Process data with streaming updates."""
    writer = get_stream_writer()
    writer(f"Processing: {item}")
    # ... work ...
    writer(f"Done: {item}")
    return "result"
```

### Execution info

Access thread ID, run ID, and retry state:

```python
from langchain.tools import tool, ToolRuntime

@tool
def log_execution_context(runtime: ToolRuntime) -> str:
    """Log execution identity information."""
    info = runtime.execution_info
    print(f"Thread: {info.thread_id}")
    print(f"Run: {info.run_id}")
    print(f"Attempt: {info.node_attempt}")  # retry count
    return f"Thread={info.thread_id}, attempt={info.node_attempt}"
```

Requires `deepagents>=0.5.0` (or `langgraph>=1.1.5`).

### Server info

When running on LangGraph Server:

```python
@tool
def get_assistant_scoped_data(runtime: ToolRuntime) -> str:
    """Fetch data scoped to the current assistant."""
    server = runtime.server_info
    if server is not None:
        print(f"Assistant: {server.assistant_id}, Graph: {server.graph_id}")
        if server.user is not None:
            print(f"User: {server.user.identity}")
        return f"Running on graph: {server.graph_id}"
    return "Not running on LangGraph Server (local dev)"
```

`server_info` is `None` during local development or testing.

## Tool return types

| Return type | Effect |
|-------------|--------|
| `str` | Wrapped in `ToolMessage`, sent to model as text |
| `dict` / object | Serialized, sent to model for reasoning |
| `Command` | Updates graph state fields; always include a `ToolMessage` so model sees confirmation |

### Return a string (most common)

```python
@tool
def get_weather(city: str) -> str:
    """Get weather for a city."""
    return f"It is currently sunny in {city}."
```

### Return an object (structured data)

```python
@tool
def get_weather_data(city: str) -> dict:
    """Get structured weather data for a city."""
    return {
        "city": city,
        "temperature_c": 22,
        "conditions": "sunny",
        "humidity_pct": 45,
    }
```

### Return a Command (state update)

```python
from langchain.messages import ToolMessage
from langchain.tools import ToolRuntime, tool
from langgraph.types import Command

@tool
def set_language(language: str, runtime: ToolRuntime) -> Command:
    """Set the preferred response language."""
    return Command(
        update={
            "preferred_language": language,
            "messages": [
                ToolMessage(
                    content=f"Language set to {language}.",
                    tool_call_id=runtime.tool_call_id,
                )
            ],
        }
    )
```

### content_and_artifact return format

Return both a model-visible string and machine-readable data (stored in `ToolMessage.artifact`):

```python
@tool(response_format="content_and_artifact")
def retrieve_documents(query: str):
    """Retrieve relevant documents for a query."""
    docs = vector_store.similarity_search(query, k=3)
    serialized = "\n\n".join(
        f"Source: {doc.metadata}\nContent: {doc.page_content}"
        for doc in docs
    )
    # First element → ToolMessage.content (sent to model)
    # Second element → ToolMessage.artifact (accessible programmatically)
    return serialized, docs
```

## ToolNode (for custom LangGraph graphs)

When building a custom graph instead of using `create_agent`, use `ToolNode`:

```python
from langchain.tools import tool
from langgraph.prebuilt import ToolNode, tools_condition
from langgraph.graph import StateGraph, MessagesState, START, END
from langchain_openai import ChatOpenAI

@tool
def search(query: str) -> str:
    """Search for information."""
    return f"Results for: {query}"

@tool
def calculator(expression: str) -> str:
    """Evaluate a math expression."""
    return str(eval(expression))  # noqa: S307

model = ChatOpenAI(model="gpt-5.4")

def call_llm(state: MessagesState):
    response = model.bind_tools([search, calculator]).invoke(state["messages"])
    return {"messages": [response]}

# ToolNode handles parallel execution, error handling, state injection
tool_node = ToolNode([search, calculator])

builder = StateGraph(MessagesState)
builder.add_node("llm", call_llm)
builder.add_node("tools", tool_node)
builder.add_edge(START, "llm")
builder.add_conditional_edges("llm", tools_condition)  # routes to "tools" or END
builder.add_edge("tools", "llm")
graph = builder.compile()
```

### ToolNode error handling

```python
# Default: catch invocation errors, re-raise execution errors
tool_node = ToolNode(tools)

# Catch all errors and return error message to LLM
tool_node = ToolNode(tools, handle_tool_errors=True)

# Custom error message
tool_node = ToolNode(tools, handle_tool_errors="Something went wrong, please try again.")

# Custom error handler function
def handle_error(e: ValueError) -> str:
    return f"Invalid input: {e}"

tool_node = ToolNode(tools, handle_tool_errors=handle_error)

# Only catch specific exception types
tool_node = ToolNode(tools, handle_tool_errors=(ValueError, TypeError))
```

## Complete tool example: financial assistant tools

```python
from dataclasses import dataclass
from typing import Any, Literal
from langchain.agents import AgentState, create_agent
from langchain.messages import ToolMessage
from langchain.tools import tool, ToolRuntime
from langgraph.store.memory import InMemoryStore
from langgraph.types import Command
from typing_extensions import NotRequired

# State
class FinancialState(AgentState):
    active_portfolio: NotRequired[str]
    last_query_type: NotRequired[str]

# Context
@dataclass
class FinancialContext:
    user_id: str
    access_level: Literal["read", "trade", "admin"]

# Tools
@tool
def get_portfolio(runtime: ToolRuntime[FinancialContext, FinancialState]) -> str:
    """Get the current user's portfolio summary."""
    user_id = runtime.context.user_id
    portfolio = runtime.store.get(("portfolios",), user_id)
    if portfolio:
        return f"Portfolio: {portfolio.value}"
    return "No portfolio found. Create one to get started."

@tool
def set_active_portfolio(name: str, runtime: ToolRuntime[FinancialContext, FinancialState]) -> Command:
    """Set the active portfolio to work with."""
    if runtime.context.access_level not in ("trade", "admin"):
        return Command(
            update={"messages": [ToolMessage(
                content="Insufficient permissions to change portfolio.",
                tool_call_id=runtime.tool_call_id,
            )]}
        )
    return Command(
        update={
            "active_portfolio": name,
            "messages": [ToolMessage(
                content=f"Active portfolio set to '{name}'.",
                tool_call_id=runtime.tool_call_id,
            )],
        }
    )

@tool
def search_stocks(query: str, runtime: ToolRuntime) -> str:
    """Search for stocks by name or ticker symbol."""
    writer = runtime.stream_writer
    writer(f"Searching for '{query}'...")
    # ... real search logic ...
    writer("Search complete.")
    return f"Found: AAPL (Apple Inc.), MSFT (Microsoft), GOOGL (Alphabet)"

store = InMemoryStore()
agent = create_agent(
    model="openai:gpt-5.4",
    tools=[get_portfolio, set_active_portfolio, search_stocks],
    state_schema=FinancialState,
    context_schema=FinancialContext,
    store=store,
    system_prompt="You are a financial assistant. Help users manage their investment portfolios.",
)
```
