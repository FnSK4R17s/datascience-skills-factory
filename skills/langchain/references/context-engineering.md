# Context Engineering

Source: `docs/context-engineering.md`, `docs/middleware__overview.md`, `docs/middleware__custom.md`,
`docs/middleware__built-in.md`, `docs/runtime.md`

## Why context engineering matters

Agent failures are almost always caused by the wrong context being passed to the LLM —
not by the model being incapable. Context engineering is the practice of providing the right
information and tools in the right format at each step of the agent loop.

## Three context types

| Context Type | Scope | Controlled via |
|---|---|---|
| Model context | Transient — what the LLM sees in a single call | System prompt, message history, tool list, response format |
| Tool context | Persistent — what tools can read/write | State, Store, Runtime context |
| Life-cycle context | Persistent — what happens between model and tool calls | Middleware hooks |

## Model context

### System prompt

```python
from langchain.agents import create_agent
from langchain.agents.middleware import dynamic_prompt, ModelRequest

# Static
agent = create_agent(model, tools=tools, system_prompt="You are a helpful assistant.")

# Dynamic — varies per request
@dynamic_prompt
def role_based_prompt(request: ModelRequest) -> str:
    role = request.runtime.context.get("user_role", "user")
    return f"You are a helpful assistant. User role: {role}."

agent = create_agent(model, tools=tools, middleware=[role_based_prompt])
```

### Message history (trim/summarize)

```python
from langchain.agents.middleware import SummarizationMiddleware, ContextEditingMiddleware, ClearToolUsesEdit

# Summarize old messages when token budget fills
agent = create_agent(
    model, tools=tools,
    middleware=[
        SummarizationMiddleware(
            model="openai:gpt-5.4-mini",
            trigger=("tokens", 4000),
            keep=("messages", 20),
        )
    ]
)

# Clear old tool outputs (keep N most recent results)
agent = create_agent(
    model, tools=tools,
    middleware=[
        ContextEditingMiddleware(
            edits=[ClearToolUsesEdit(trigger=100000, keep=3)]
        )
    ]
)
```

### Dynamic tool selection

Use `@wrap_model_call` to filter tools before each model call (see `docs/middleware__custom.md`):

```python
from langchain.agents.middleware import wrap_model_call, ModelRequest, ModelResponse

@wrap_model_call
def filter_tools_by_role(request: ModelRequest, handler) -> ModelResponse:
    role = request.runtime.context.get("user_role", "viewer")
    if role != "admin":
        filtered = [t for t in request.tools if not t.name.startswith("admin_")]
        request = request.override(tools=filtered)
    return handler(request)
```

## Tool context (ToolRuntime)

Tools access runtime information through the `ToolRuntime` parameter (hidden from LLM).

```python
from langchain.tools import tool, ToolRuntime

@tool
def get_user_data(key: str, runtime: ToolRuntime) -> str:
    """Retrieve user-specific data."""
    # State: current conversation (short-term)
    messages = runtime.state["messages"]

    # Context: immutable per-run config (user_id, permissions)
    user_id = runtime.context.user_id

    # Store: cross-conversation memory (long-term)
    stored = runtime.store.get(("users",), user_id)

    # stream_writer: emit progress to streaming consumers
    runtime.stream_writer(f"Fetching data for {user_id}...")

    # execution_info: thread_id, run_id, attempt count
    attempt = runtime.execution_info.node_attempt

    return str(stored.value) if stored else "No data"
```

Pass context at invocation time:

```python
from dataclasses import dataclass

@dataclass
class UserContext:
    user_id: str
    user_role: str

agent = create_agent(model, tools=[get_user_data], context_schema=UserContext)
result = agent.invoke(
    {"messages": [{"role": "user", "content": "Get my data"}]},
    context=UserContext(user_id="u123", user_role="admin")
)
```

## Life-cycle context (middleware hooks)

```python
from langchain.agents.middleware import AgentMiddleware, AgentState, hook_config
from langgraph.runtime import Runtime
from typing import Any

class AuditMiddleware(AgentMiddleware):
    """Log each model call and inject audit data before agent starts."""

    def before_agent(self, state: AgentState, runtime: Runtime) -> dict[str, Any] | None:
        print(f"Run started: {runtime.execution_info.run_id}")
        return None  # return None to continue, or dict to update state

    def before_model(self, state: AgentState, runtime: Runtime) -> dict[str, Any] | None:
        print(f"Model call #{len(state['messages'])} messages")
        return None

    def after_model(self, state: AgentState, runtime: Runtime) -> dict[str, Any] | None:
        last = state["messages"][-1]
        print(f"Model responded: {last.text[:100]}")
        return None

    def after_agent(self, state: AgentState, runtime: Runtime) -> dict[str, Any] | None:
        print("Run complete")
        return None

agent = create_agent(model, tools=tools, middleware=[AuditMiddleware()])
```

Hook return value of `None` means "continue unchanged." Returning a dict updates state.
Use `can_jump_to` to allow jumping over nodes:

```python
from langchain.agents.middleware import before_model, hook_config
from langchain.messages import AIMessage

@before_model(can_jump_to=["end"])
def rate_limit_guard(state, runtime):
    if len(state["messages"]) >= 50:
        return {"messages": [AIMessage("Limit reached.")], "jump_to": "end"}
    return None
```

## Data source summary

| Source | Mutable | Scope | Access |
|---|---|---|---|
| Runtime Context | No | Per-invocation | `runtime.context` / `request.runtime.context` |
| State | Yes | Per-thread | `runtime.state` / `request.state` |
| Store | Yes | Cross-thread | `runtime.store` / `request.runtime.store` |
