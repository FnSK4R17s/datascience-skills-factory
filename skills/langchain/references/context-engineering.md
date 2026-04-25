# Context Engineering

Source: `docs/context-engineering.md`, `docs/middleware__overview.md`,
`docs/middleware__custom.md`, `docs/middleware__built-in.md`, `docs/runtime.md`

## Why context engineering matters

Agent failures are almost always caused by the wrong context being passed to the LLM —
not by the model being incapable. Context engineering is the practice of providing the
right information and tools in the right format at each step of the agent loop.

At the centre of multi-agent design is context engineering — deciding what each agent
sees. The quality of your system depends on ensuring each agent has access to the right
data for its task.

## Three context types

| Context Type | Scope | Controlled via |
|---|---|---|
| **Model context** | Transient — what the LLM sees in a single call | System prompt, message history, tool list, response format |
| **Tool context** | Persistent — what tools can read/write | State, Store, Runtime context |
| **Life-cycle context** | Persistent — what happens between model and tool calls | Middleware hooks |

## Model context

### Static system prompt

```python
from langchain.agents import create_agent

agent = create_agent(
    model="openai:gpt-5.4",
    tools=tools,
    system_prompt="You are a helpful assistant that specialises in financial analysis."
)
```

### Dynamic system prompt via @dynamic_prompt

Generated fresh from the current request state/context on every model call:

```python
from langchain.agents.middleware import dynamic_prompt, ModelRequest

@dynamic_prompt
def role_based_prompt(request: ModelRequest) -> str:
    role = request.runtime.context.user_role if request.runtime and request.runtime.context else "user"
    locale = request.runtime.context.locale if request.runtime and request.runtime.context else "en-US"
    base = "You are a helpful assistant."
    if role == "expert":
        return f"{base} Provide detailed technical explanations. Respond in {locale}."
    elif role == "beginner":
        return f"{base} Explain concepts simply, avoid jargon. Respond in {locale}."
    return f"{base} Respond in {locale}."

agent = create_agent(model, tools, middleware=[role_based_prompt], context_schema=Context)
```

### Dynamic system prompt via wrap_model_call (inject content blocks)

Use this when you need to add structured content blocks (e.g., Anthropic cache control):

```python
from langchain.agents.middleware import wrap_model_call, ModelRequest, ModelResponse
from langchain.messages import SystemMessage
from typing import Callable

@wrap_model_call
def inject_knowledge_base(
    request: ModelRequest,
    handler: Callable[[ModelRequest], ModelResponse],
) -> ModelResponse:
    """Inject company knowledge base into system prompt."""
    # request.system_message is always SystemMessage (even if agent created with str)
    # Use content_blocks for structured list representation
    kb_content = load_knowledge_base()  # load relevant context
    new_content = list(request.system_message.content_blocks) + [
        {
            "type": "text",
            "text": f"Relevant knowledge:\n{kb_content}",
            "cache_control": {"type": "ephemeral"},  # Anthropic caching
        }
    ]
    new_system = SystemMessage(content=new_content)
    return handler(request.override(system_message=new_system))
```

### Message history management

**Summarization** — compress old messages when approaching token limits:

```python
from langchain.agents.middleware import SummarizationMiddleware

agent = create_agent(
    model="openai:gpt-5.4",
    tools=tools,
    middleware=[
        SummarizationMiddleware(
            model="openai:gpt-5.4-mini",
            trigger=("tokens", 4000),   # compress when context > 4000 tokens
            keep=("messages", 20),       # retain last 20 messages
        )
    ]
)
```

**Context editing** — clear old tool outputs (less aggressive than summarization):

```python
from langchain.agents.middleware import ContextEditingMiddleware, ClearToolUsesEdit

agent = create_agent(
    model="openai:gpt-5.4",
    tools=tools,
    middleware=[
        ContextEditingMiddleware(
            edits=[
                ClearToolUsesEdit(
                    trigger=100000,  # clear when > 100K tokens
                    keep=3,          # always keep last 3 tool results
                    exclude_tools=["retrieve_documents"],  # never clear RAG results
                )
            ]
        )
    ]
)
```

### Dynamic tool selection

Control which tools the model sees on each call:

```python
from langchain.agents.middleware import wrap_model_call, ModelRequest, ModelResponse
from dataclasses import dataclass
from typing import Callable

@dataclass
class Context:
    user_role: str       # "admin", "editor", "viewer"
    feature_flags: list  # ["advanced_search", "export"]

@wrap_model_call
def context_based_tools(
    request: ModelRequest,
    handler: Callable[[ModelRequest], ModelResponse],
) -> ModelResponse:
    """Expose only appropriate tools based on user role and feature flags."""
    if request.runtime is None or request.runtime.context is None:
        role = "viewer"
        flags = []
    else:
        role = request.runtime.context.user_role
        flags = request.runtime.context.feature_flags

    all_tools = request.tools
    filtered = []
    for t in all_tools:
        # Role-based filtering
        if t.name.startswith("admin_") and role != "admin":
            continue
        if t.name.startswith("write_") and role == "viewer":
            continue
        # Feature flag filtering
        if t.name == "advanced_search" and "advanced_search" not in flags:
            continue
        if t.name == "export_data" and "export" not in flags:
            continue
        filtered.append(t)

    return handler(request.override(tools=filtered))

# State-based filtering (unlocks tools as conversation progresses)
@wrap_model_call
def state_based_tools(request: ModelRequest, handler) -> ModelResponse:
    state = request.state
    is_authenticated = state.get("authenticated", False)
    message_count = len(state["messages"])

    # Progressive disclosure — unlock tools as trust increases
    if not is_authenticated:
        tools = [t for t in request.tools if t.name.startswith("public_")]
    elif message_count < 5:
        tools = [t for t in request.tools if not t.name.startswith("sensitive_")]
    else:
        tools = request.tools  # all tools available after trust established

    return handler(request.override(tools=tools))
```

**LLM tool selector** — use a cheap model to pre-select relevant tools:

```python
from langchain.agents.middleware import LLMToolSelectorMiddleware

agent = create_agent(
    model="openai:gpt-5.4",
    tools=[tool1, tool2, tool3, tool4, tool5, tool6, tool7, tool8],  # many tools
    middleware=[
        LLMToolSelectorMiddleware(
            model="openai:gpt-5.4-mini",
            max_tools=3,                  # expose at most 3 per model call
            always_include=["search"],    # critical tool always available
        ),
    ],
)
```

## Tool context (ToolRuntime)

Tools access runtime information through the `ToolRuntime` parameter.

```python
from langchain.tools import tool, ToolRuntime

@tool
def comprehensive_tool(query: str, runtime: ToolRuntime) -> str:
    """Demonstrates all ToolRuntime data sources."""
    # State: current conversation (short-term, mutable)
    messages = runtime.state["messages"]
    custom_field = runtime.state.get("my_custom_field", "default")

    # Context: immutable per-run config (user_id, permissions)
    user_id = runtime.context.user_id if runtime.context else None

    # Store: cross-conversation memory (long-term, mutable)
    if user_id:
        stored = runtime.store.get(("users",), user_id)

    # stream_writer: emit progress to streaming consumers
    runtime.stream_writer(f"Processing query: {query}")

    # execution_info: thread_id, run_id, attempt count
    attempt = runtime.execution_info.node_attempt if runtime.execution_info else 0

    # server_info: assistant_id, graph_id, user (on LangGraph Server)
    server = runtime.server_info  # None if not on LangGraph Server

    # tool_call_id: unique ID for this invocation
    call_id = runtime.tool_call_id

    return f"Processed '{query}' for user {user_id} (attempt {attempt})"
```

### Full ToolRuntime reference

| Property | Type | Description |
|----------|------|-------------|
| `state` | `dict` | Current graph state (short-term memory) |
| `context` | dataclass or dict | Immutable per-invocation config |
| `store` | `BaseStore` | Long-term memory backend |
| `stream_writer` | `callable` | Emit real-time progress to streaming consumers |
| `execution_info` | `ExecutionInfo` | `thread_id`, `run_id`, `node_attempt` |
| `server_info` | `ServerInfo` or `None` | `assistant_id`, `graph_id`, `user` (LangGraph Server only) |
| `config` | `RunnableConfig` | Full LangGraph config with callbacks, tags, metadata |
| `tool_call_id` | `str` | Unique ID for this tool invocation |

### Passing context at invocation time

```python
from dataclasses import dataclass
from langchain.agents import create_agent

@dataclass
class AppContext:
    user_id: str
    user_role: str
    locale: str
    tenant_id: str

agent = create_agent(
    model="openai:gpt-5.4",
    tools=[comprehensive_tool],
    context_schema=AppContext,
)

# Context is immutable during the run — set it here
result = agent.invoke(
    {"messages": [{"role": "user", "content": "Hello"}]},
    context=AppContext(
        user_id="u123",
        user_role="admin",
        locale="en-US",
        tenant_id="tenant-acme",
    ),
)
```

## Life-cycle context (middleware hooks)

Middleware intercepts the agent loop at well-defined points to inject context, validate,
log, or alter behaviour without changing core agent code.

```python
from langchain.agents.middleware import (
    AgentMiddleware, AgentState, ModelRequest, ModelResponse
)
from langgraph.runtime import Runtime
from typing import Any, Callable

class LifecycleContextMiddleware(AgentMiddleware):
    """Full lifecycle hook example showing when each hook fires."""

    def before_agent(self, state: AgentState, runtime: Runtime) -> dict[str, Any] | None:
        """Fires once at the start of each invoke/stream call."""
        print(f"Run started: thread={runtime.execution_info.thread_id if runtime.execution_info else 'N/A'}")
        # Return dict to inject initial state updates
        return {"call_start_time": "2026-04-25T10:00:00Z"}  # hypothetical timestamp field

    def before_model(self, state: AgentState, runtime: Runtime) -> dict[str, Any] | None:
        """Fires before each LLM call."""
        print(f"Model call #{len(state['messages'])} messages in context")
        return None  # None = continue unchanged

    def after_model(self, state: AgentState, runtime: Runtime) -> dict[str, Any] | None:
        """Fires after each LLM response."""
        last = state["messages"][-1]
        print(f"Model responded: {last.text[:100]}")
        return None

    def wrap_model_call(
        self, request: ModelRequest, handler: Callable[[ModelRequest], ModelResponse]
    ) -> ModelResponse:
        """Wraps each model call — full control over the call."""
        # Modify request before the call
        # ...
        response = handler(request)  # execute
        # Inspect response after the call
        return response

    def after_agent(self, state: AgentState, runtime: Runtime) -> dict[str, Any] | None:
        """Fires once at the end of each invoke/stream call."""
        print("Run complete.")
        return None
```

### Hook return values

| Hook | Return `None` | Return dict | Jump |
|------|:---:|:---:|:---:|
| `before_agent` | Continue | Update state | `{"jump_to": "end"}` with `can_jump_to=["end"]` |
| `before_model` | Continue | Update state | `{"jump_to": "end"}` |
| `after_model` | Continue | Update state | `{"jump_to": "end"}` |
| `after_agent` | Continue | Update state | - |
| `wrap_model_call` | N/A | N/A | Return early (short-circuit) |
| `wrap_tool_call` | N/A | N/A | Return early (skip tool) |

### Rate limiting via before_model

```python
from langchain.agents.middleware import before_model, hook_config, AgentState
from langchain.messages import AIMessage
from langgraph.runtime import Runtime
from typing import Any
from typing_extensions import NotRequired

class RateLimitState(AgentState):
    model_call_count: NotRequired[int]
    max_calls: NotRequired[int]

@before_model(can_jump_to=["end"], state_schema=RateLimitState)
def enforce_rate_limit(state: RateLimitState, runtime: Runtime) -> dict[str, Any] | None:
    count = state.get("model_call_count", 0)
    limit = state.get("max_calls", 10)

    if count >= limit:
        return {
            "messages": [AIMessage(f"Rate limit reached ({limit} calls). Please start a new conversation.")],
            "jump_to": "end",
        }

    return {"model_call_count": count + 1}
```

## Data source summary

| Source | Mutable | Scope | Access in tool | Access in middleware |
|---|:---:|---|---|---|
| Runtime context | No | Per-invocation | `runtime.context` | `request.runtime.context` |
| State | Yes | Per-thread | `runtime.state` | `request.state` / `state` param |
| Store | Yes | Cross-thread | `runtime.store` | `request.runtime.store` |
| Stream writer | N/A | Per-tool-call | `runtime.stream_writer` | `get_stream_writer()` |
| Execution info | No | Per-call | `runtime.execution_info` | `runtime.execution_info` |
| Server info | No | Per-request | `runtime.server_info` | N/A |

## Context engineering for multi-agent systems

When building multi-agent systems, context engineering determines which information
each agent receives:

```python
from langchain.agents import create_agent
from langchain.tools import tool, ToolRuntime
from langchain.agents import AgentState
from typing_extensions import NotRequired

class SupervisorState(AgentState):
    research_results: NotRequired[str]
    user_preferences: NotRequired[dict]

@tool
def call_writer_with_context(
    task: str,
    runtime: ToolRuntime[None, SupervisorState],
) -> str:
    """Call the writer agent with research context."""
    # Pass supervisor's research results to the writer
    research = runtime.state.get("research_results", "")
    user_prefs = runtime.state.get("user_preferences", {})

    enriched_task = (
        f"{task}\n\n"
        f"User preferences: {user_prefs}\n\n"
        f"Research context:\n{research}"
    )

    result = writer_agent.invoke({
        "messages": [{"role": "user", "content": enriched_task}]
    })
    return result["messages"][-1].text
```

### Preventing context bloat in subagents

A key advantage of the subagents pattern is context isolation — each subagent starts
with a clean context window:

```python
# BAD: Pass the entire conversation history to a subagent
# This defeats the purpose of context isolation
result = subagent.invoke({"messages": state["messages"]})

# GOOD: Pass only the relevant query
result = subagent.invoke({
    "messages": [
        {"role": "user", "content": specific_query}  # focused question only
    ]
})

# ALSO GOOD: Pass a summary of relevant prior context
relevant_summary = extract_relevant_context(state["messages"], task)
result = subagent.invoke({
    "messages": [
        {"role": "system", "content": f"Context: {relevant_summary}"},
        {"role": "user", "content": specific_query},
    ]
})
```
