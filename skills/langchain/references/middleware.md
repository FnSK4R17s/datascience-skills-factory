# Middleware

Source: `docs/middleware__overview.md`, `docs/middleware__built-in.md`, `docs/middleware__custom.md`, `docs/agents.md`

Middleware intercepts the agent loop at well-defined points to add logging,
retries, dynamic behaviour, guardrails, and more — without modifying core agent
logic. Add middleware to `create_agent(..., middleware=[...])`.

## Hook points

The agent loop: model call → tool execution → model call → ... → finish.

Middleware exposes hooks around each step:

| Decorator / method | When it fires |
|--------------------|---------------|
| `@before_model` | Before each model invocation |
| `@after_model` | After each model invocation |
| `@before_agent` | Before the first model call of a run |
| `@after_agent` | After the agent produces its final output |
| `@wrap_model_call` | Wraps the model call; must call `handler(request)` to proceed |
| `@wrap_tool_call` | Wraps each tool execution; must call `handler(request)` to proceed |
| `@dynamic_prompt` | Generates a system prompt from the current request |

## Simple decorator pattern

Use decorators for standalone hooks:

```python
from langchain.agents import create_agent
from langchain.agents.middleware import before_model, wrap_model_call, ModelRequest, ModelResponse

@before_model
def log_before(state, runtime) -> dict | None:
    """Log state before model call. Return None to proceed, or a dict to update state."""
    print(f"Messages: {len(state['messages'])}")
    return None

@wrap_model_call
def dynamic_model(request: ModelRequest, handler) -> ModelResponse:
    """Swap model based on message count."""
    if len(request.state["messages"]) > 10:
        request = request.override(model=advanced_model)
    return handler(request)

agent = create_agent(model, tools=tools, middleware=[log_before, dynamic_model])
```

## Class-based middleware (AgentMiddleware)

Use when middleware needs its own state, tools, or a custom state schema:

```python
from langchain.agents.middleware import AgentMiddleware, ModelRequest, ToolCallRequest
from langchain.agents import AgentState
from typing import Any

class CustomState(AgentState):
    call_count: int

class MyMiddleware(AgentMiddleware):
    state_schema = CustomState  # extends the agent's state schema
    tools = [my_extra_tool]     # tools scoped to this middleware

    def before_model(self, state: CustomState, runtime) -> dict[str, Any] | None:
        return {"call_count": state.get("call_count", 0) + 1}

    def wrap_tool_call(self, request: ToolCallRequest, handler):
        try:
            return handler(request)
        except Exception as e:
            from langchain.messages import ToolMessage
            return ToolMessage(
                content=f"Error: {e}",
                tool_call_id=request.tool_call["id"]
            )

agent = create_agent(model, tools=tools, middleware=[MyMiddleware()])
```

## Dynamic system prompt

```python
from langchain.agents.middleware import dynamic_prompt, ModelRequest

@dynamic_prompt
def role_prompt(request: ModelRequest) -> str:
    role = request.runtime.context.get("user_role", "user")
    if role == "expert":
        return "You are a helpful assistant. Provide technical detail."
    return "You are a helpful assistant. Keep responses simple."

agent = create_agent(model, tools=tools, middleware=[role_prompt], context_schema=Context)
```

## Dynamic tool filtering

Filter which tools are shown to the model at runtime:

```python
from langchain.agents.middleware import wrap_model_call, ModelRequest, ModelResponse

@wrap_model_call
def filter_tools(request: ModelRequest, handler) -> ModelResponse:
    user_role = request.runtime.context.user_role
    if user_role != "admin":
        request = request.override(
            tools=[t for t in request.tools if not t.name.startswith("admin_")]
        )
    return handler(request)
```

For tools discovered at runtime (e.g., from an MCP server), use both
`wrap_model_call` (to register the tool) and `wrap_tool_call` (to route
execution to it). See `docs/agents.md` for the full `DynamicToolMiddleware`
class example.

## Built-in middleware catalogue

Source: `docs/middleware__built-in.md`

| Class | What it does |
|-------|-------------|
| `SummarizationMiddleware` | Compresses history when approaching token limit (`trigger`, `keep` config) |
| `HumanInTheLoopMiddleware` | Pauses for human approval of specific tool calls (`interrupt_on={tool_name: True}`) |
| `ModelCallLimitMiddleware` | Caps total model invocations per run |
| `ToolCallLimitMiddleware` | Caps total tool invocations per run |
| `ModelFallbackMiddleware` | Falls back to alternate models on failure |
| `PIIDetectionMiddleware` | Detects and handles PII in messages |
| `TodoListMiddleware` | Gives agent task planning / tracking |
| `LLMToolSelectorMiddleware` | Pre-selects relevant tools using a cheap model |
| `ToolRetryMiddleware` | Retries failed tool calls with exponential backoff |
| `ModelRetryMiddleware` | Retries failed model calls |
| `LLMToolEmulatorMiddleware` | Emulates tool execution with an LLM (testing) |
| `ContextEditingMiddleware` | Trims or clears tool messages from context |
| `SubagentMiddleware` | Lets the agent spawn subagents |

Quick `SummarizationMiddleware` example:

```python
from langchain.agents.middleware import SummarizationMiddleware

middleware = SummarizationMiddleware(
    model="openai:gpt-4o-mini",     # cheap model for summarization
    trigger=("tokens", 4000),       # summarize when context exceeds 4000 tokens
    keep=("messages", 20),          # retain last 20 messages after summarization
)
```

`trigger` and `keep` accept `("fraction", 0.8)`, `("tokens", N)`, or `("messages", N)`.
The `fraction` form reads model profile data and requires `langchain>=1.1`.

Quick `HumanInTheLoopMiddleware` example:

```python
from langchain.agents.middleware import HumanInTheLoopMiddleware
from langgraph.checkpoint.memory import InMemorySaver

agent = create_agent(
    model, tools=[get_weather],
    middleware=[HumanInTheLoopMiddleware(interrupt_on={"get_weather": True})],
    checkpointer=InMemorySaver(),
)
```

Interrupts surface in the `"updates"` stream as `source == "__interrupt__"`. Resume
with `agent.stream(Command(resume=decisions), config=config, ...)`.

## Middleware ordering

Middleware in the list is applied outermost-first for `wrap_*` hooks (like
function composition). `before_model` hooks run in list order; `after_model`
hooks run in reverse order.
