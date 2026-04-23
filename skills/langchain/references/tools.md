# Tools

Source: `docs/tools.md`, `docs/agents.md`

## Define a tool

```python
from langchain.tools import tool

@tool
def search_database(query: str, limit: int = 10) -> str:
    """Search the database for records matching the query.

    Args:
        query: Search terms
        limit: Max results
    """
    return f"Found {limit} results for '{query}'"
```

Type hints are required — they define the input schema passed to the model.
The docstring becomes the tool description the model sees. Keep it informative
and concise.

Naming: use `snake_case`. Some providers reject names with spaces or special characters.

## Customize tool metadata

```python
@tool("web_search", description="Search the web for current information.")
def search(query: str) -> str:
    ...
```

## Advanced schema

Use a Pydantic model or JSON Schema dict for complex inputs:

```python
from pydantic import BaseModel, Field
from typing import Literal

class WeatherInput(BaseModel):
    location: str = Field(description="City name")
    units: Literal["celsius", "fahrenheit"] = "celsius"

@tool(args_schema=WeatherInput)
def get_weather(location: str, units: str = "celsius") -> str:
    """Get weather for a location."""
    ...
```

## Reserved argument names

`config` and `runtime` cannot be used as tool parameter names — they are injected
by the framework. Use `ToolRuntime` to access runtime context instead.

## Access runtime context with ToolRuntime

`ToolRuntime` is injected automatically and hidden from the model's tool schema.

```python
from langchain.tools import tool, ToolRuntime

@tool
def my_tool(query: str, runtime: ToolRuntime) -> str:
    """A context-aware tool."""
    ...
```

### State (short-term memory)

```python
@tool
def get_history_length(runtime: ToolRuntime) -> str:
    """Return number of messages so far."""
    return str(len(runtime.state["messages"]))
```

To update state, return a `Command`:

```python
from langchain.agents import AgentState
from langchain.messages import ToolMessage
from langchain.tools import ToolRuntime, tool
from langgraph.types import Command

class CustomState(AgentState):
    preferred_language: str

@tool
def set_language(language: str, runtime: ToolRuntime[None, CustomState]) -> Command:
    """Set preferred response language."""
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

When multiple tools update the same state field in parallel, define a reducer on
that field to resolve conflicts.

### Context (immutable runtime config)

Passed at invocation time; does not change during a conversation.

```python
from dataclasses import dataclass
from langchain.agents import create_agent
from langchain.tools import tool, ToolRuntime

@dataclass
class UserContext:
    user_id: str

@tool
def get_account_info(runtime: ToolRuntime[UserContext]) -> str:
    """Get account info for the current user."""
    return f"Account for {runtime.context.user_id}"

agent = create_agent(model, tools=[get_account_info], context_schema=UserContext)
result = agent.invoke(
    {"messages": [{"role": "user", "content": "What's my balance?"}]},
    context=UserContext(user_id="user123"),
)
```

### Store (long-term memory)

Persists across conversations. Use `runtime.store` with a namespace/key pattern.

```python
from langgraph.store.memory import InMemoryStore

@tool
def save_preference(key: str, value: str, runtime: ToolRuntime) -> str:
    """Save a user preference."""
    runtime.store.put(("prefs",), key, {"value": value})
    return f"Saved {key}={value}"

@tool
def get_preference(key: str, runtime: ToolRuntime) -> str:
    """Get a saved preference."""
    item = runtime.store.get(("prefs",), key)
    return item.value["value"] if item else "not set"

agent = create_agent(model, tools=[save_preference, get_preference], store=InMemoryStore())
```

For production, use `PostgresStore` instead of `InMemoryStore`.

### Stream writer

Emit real-time updates from inside a tool. Tool must run within a LangGraph
execution context (i.e., called through an agent's `stream()` or `invoke()`).

```python
@tool
def long_running_task(query: str, runtime: ToolRuntime) -> str:
    """Process a complex query."""
    runtime.stream_writer(f"Starting: {query}")
    # ... work ...
    runtime.stream_writer("Done.")
    return "result"
```

### Execution info

```python
@tool
def log_context(runtime: ToolRuntime) -> str:
    info = runtime.execution_info
    return f"thread={info.thread_id} attempt={info.node_attempt}"
```

Requires `langgraph>=1.1.5`.

## Tool return types

| Return type | Effect |
|-------------|--------|
| `str` | Wrapped in `ToolMessage`, passed to model as text |
| `dict` / object | Serialized, passed to model for reasoning |
| `Command` | Updates graph state fields; include `ToolMessage` so model sees confirmation |

## ToolNode (for custom LangGraph graphs)

When building a custom graph instead of using `create_agent`, use `ToolNode`:

```python
from langchain.tools import tool
from langgraph.prebuilt import ToolNode, tools_condition
from langgraph.graph import StateGraph, MessagesState, START, END

tool_node = ToolNode([search, calculator])

builder = StateGraph(MessagesState)
builder.add_node("llm", call_llm)
builder.add_node("tools", tool_node)
builder.add_edge(START, "llm")
builder.add_conditional_edges("llm", tools_condition)  # routes to "tools" or END
builder.add_edge("tools", "llm")
graph = builder.compile()
```

`ToolNode` handles parallel execution and error handling automatically.
Error handling: `handle_tool_errors=True` (catch all), a string (fixed message),
or a callable, or a tuple of exception types.
