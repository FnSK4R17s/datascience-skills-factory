# Middleware

Source: `docs/middleware__overview.md`, `docs/middleware__built-in.md`, `docs/middleware__custom.md`, `docs/agents.md`

Middleware intercepts the agent loop at well-defined points to add logging, retries,
dynamic behaviour, guardrails, and more — without modifying core agent logic. Add
middleware to `create_agent(..., middleware=[...])`.

## The agent loop

```
input → before_agent → [before_model → wrap_model_call → model → after_model → tools] → after_agent → output
```

Middleware exposes hooks at every step:

| Decorator / method | When it fires | Style |
|--------------------|---------------|-------|
| `@before_agent` | Before the first model call of a run (once per invocation) | Node |
| `@before_model` | Before each model invocation | Node |
| `@after_model` | After each model invocation | Node |
| `@after_agent` | After the agent produces its final output (once per invocation) | Node |
| `@wrap_model_call` | Wraps the model call; must call `handler(request)` to proceed | Wrap |
| `@wrap_tool_call` | Wraps each tool execution; must call `handler(request)` to proceed | Wrap |
| `@dynamic_prompt` | Generates a system prompt from the current request | Convenience |

## Decorator-based middleware (simple, one hook)

### Node-style decorators

Node hooks run sequentially. Return `None` to continue, or a dict to update state.

```python
from langchain.agents.middleware import before_model, after_model, AgentState
from langchain.messages import AIMessage
from langgraph.runtime import Runtime
from typing import Any

@before_model
def log_before(state: AgentState, runtime: Runtime) -> dict[str, Any] | None:
    print(f"About to call model with {len(state['messages'])} messages")
    return None  # continue unchanged

@after_model
def log_after(state: AgentState, runtime: Runtime) -> dict[str, Any] | None:
    last = state["messages"][-1]
    print(f"Model responded: {last.text[:100]}")
    return None
```

### Wrap-style decorators

Wrap hooks control execution flow. You decide whether to call `handler` zero, one, or
multiple times (retry logic):

```python
from langchain.agents.middleware import wrap_model_call, wrap_tool_call, ModelRequest, ModelResponse
from langchain.messages import ToolMessage
from langchain.tools.tool_node import ToolCallRequest
from typing import Callable

@wrap_model_call
def retry_model(
    request: ModelRequest,
    handler: Callable[[ModelRequest], ModelResponse],
) -> ModelResponse:
    for attempt in range(3):
        try:
            return handler(request)
        except Exception as e:
            if attempt == 2:
                raise
            print(f"Retry {attempt + 1}/3 after: {e}")

@wrap_tool_call
def monitor_tools(
    request: ToolCallRequest,
    handler: Callable[[ToolCallRequest], ToolMessage],
) -> ToolMessage:
    print(f"Executing: {request.tool_call['name']}({request.tool_call['args']})")
    try:
        result = handler(request)
        print("Tool succeeded")
        return result
    except Exception as e:
        print(f"Tool failed: {e}")
        raise

from langchain.agents import create_agent
agent = create_agent(model, tools, middleware=[log_before, retry_model, monitor_tools])
```

### Dynamic prompt decorator

```python
from langchain.agents.middleware import dynamic_prompt, ModelRequest
from dataclasses import dataclass

@dataclass
class Context:
    user_role: str
    locale: str

@dynamic_prompt
def role_prompt(request: ModelRequest) -> str:
    role = request.runtime.context.user_role
    locale = request.runtime.context.locale
    if role == "expert":
        return f"You are a technical assistant. Respond in {locale}. Provide detailed technical explanations."
    elif role == "beginner":
        return f"You are a friendly assistant. Respond in {locale}. Explain concepts simply without jargon."
    return f"You are a helpful assistant. Respond in {locale}."

agent = create_agent(model, tools, middleware=[role_prompt], context_schema=Context)
```

## Class-based middleware (AgentMiddleware)

Use when middleware needs its own state, tools, multiple hooks, or async implementations:

```python
from langchain.agents.middleware import AgentMiddleware, AgentState, ModelRequest, ModelResponse, hook_config
from langchain.messages import AIMessage, ToolMessage
from langchain.tools.tool_node import ToolCallRequest
from langgraph.runtime import Runtime
from langgraph.types import Command
from typing import Any, Callable
from typing_extensions import NotRequired

class CustomState(AgentState):
    call_count: NotRequired[int]
    last_error: NotRequired[str]

class MonitoringMiddleware(AgentMiddleware):
    state_schema = CustomState

    def before_agent(self, state: CustomState, runtime: Runtime) -> dict[str, Any] | None:
        print(f"Run started, thread: {runtime.execution_info.thread_id if runtime.execution_info else 'unknown'}")
        return None

    def before_model(self, state: CustomState, runtime: Runtime) -> dict[str, Any] | None:
        count = state.get("call_count", 0)
        return {"call_count": count + 1}

    def after_model(self, state: CustomState, runtime: Runtime) -> dict[str, Any] | None:
        last = state["messages"][-1]
        print(f"Model call #{state.get('call_count', 0)}: {last.text[:50]}")
        return None

    def wrap_tool_call(
        self, request: ToolCallRequest, handler: Callable
    ) -> ToolMessage | Command:
        print(f"Tool: {request.tool_call['name']}")
        try:
            return handler(request)
        except Exception as e:
            print(f"Tool error: {e}")
            return ToolMessage(
                content=f"Tool failed: {e}. Please try a different approach.",
                tool_call_id=request.tool_call["id"],
            )

    def after_agent(self, state: CustomState, runtime: Runtime) -> dict[str, Any] | None:
        print(f"Run complete. Total model calls: {state.get('call_count', 0)}")
        return None

    # Async versions (for async agent.ainvoke / agent.astream)
    async def abefore_model(self, state: CustomState, runtime: Runtime) -> dict[str, Any] | None:
        return self.before_model(state, runtime)

    async def aafter_model(self, state: CustomState, runtime: Runtime) -> dict[str, Any] | None:
        return self.after_model(state, runtime)

agent = create_agent(model, tools, middleware=[MonitoringMiddleware()])
```

## State updates from middleware

### Node-style: return a dict

```python
from langchain.agents.middleware import after_model, AgentState
from typing_extensions import NotRequired

class TrackingState(AgentState):
    model_call_count: NotRequired[int]

@after_model(state_schema=TrackingState)
def increment_counter(state: TrackingState, runtime) -> dict | None:
    return {"model_call_count": state.get("model_call_count", 0) + 1}
```

### Wrap-style: return ExtendedModelResponse with Command

```python
from langchain.agents.middleware import wrap_model_call, ModelRequest, ModelResponse, ExtendedModelResponse, AgentState
from langgraph.types import Command
from typing import Callable
from typing_extensions import NotRequired, Annotated

def _last_wins(a, b):
    return b

class UsageState(AgentState):
    total_tokens: NotRequired[int]
    last_model: NotRequired[Annotated[str, _last_wins]]

@wrap_model_call(state_schema=UsageState)
def track_usage(
    request: ModelRequest,
    handler: Callable[[ModelRequest], ModelResponse],
) -> ExtendedModelResponse:
    response = handler(request)
    # Access token usage from response metadata
    usage = response.usage_metadata if hasattr(response, "usage_metadata") else {}
    tokens = usage.get("total_tokens", 0)
    return ExtendedModelResponse(
        model_response=response,
        command=Command(update={
            "total_tokens": tokens,
            "last_model": str(request.model),
        }),
    )
```

## Agent jumps

Exit early from middleware with `jump_to`:

```python
from langchain.agents.middleware import before_model, hook_config, AgentState
from langchain.messages import AIMessage
from langgraph.runtime import Runtime
from typing import Any

# Available jump targets: "end", "tools", "model"

@before_model(can_jump_to=["end"])  # must declare valid targets
def rate_limit_guard(state: AgentState, runtime: Runtime) -> dict[str, Any] | None:
    if len(state["messages"]) >= 50:
        return {
            "messages": [AIMessage("Conversation limit reached. Starting fresh.")],
            "jump_to": "end",
        }
    return None

# Class-based equivalent
from langchain.agents.middleware import AgentMiddleware

class BlockedContentMiddleware(AgentMiddleware):
    @hook_config(can_jump_to=["end"])
    def after_model(self, state: AgentState, runtime: Runtime) -> dict[str, Any] | None:
        last = state["messages"][-1]
        if "BLOCKED" in last.content:
            return {
                "messages": [AIMessage("I cannot respond to that request.")],
                "jump_to": "end",
            }
        return None
```

## Execution order

For `middleware=[A, B, C]`:

- `before_agent`: A → B → C
- `before_model`: A → B → C
- `wrap_model_call`: A wraps B wraps C wraps model (A outermost)
- `after_model`: C → B → A (reverse)
- `after_agent`: C → B → A (reverse)

## Built-in middleware catalogue

Source: `docs/middleware__built-in.md`

### SummarizationMiddleware

Compresses conversation history when approaching token limits.

```python
from langchain.agents.middleware import SummarizationMiddleware

# Single trigger condition
agent = create_agent(
    model="openai:gpt-5.4",
    tools=[...],
    middleware=[
        SummarizationMiddleware(
            model="openai:gpt-5.4-mini",   # cheap model for summarization
            trigger=("tokens", 4000),       # summarize when context > 4000 tokens
            keep=("messages", 20),          # retain last 20 messages after summarization
        ),
    ],
)

# Multiple trigger conditions (OR logic)
agent2 = create_agent(
    model="openai:gpt-5.4",
    tools=[...],
    middleware=[
        SummarizationMiddleware(
            model="openai:gpt-5.4-mini",
            trigger=[
                ("tokens", 3000),    # or...
                ("messages", 6),     # whichever comes first
            ],
            keep=("fraction", 0.3),  # keep 30% of context window
        ),
    ],
)

# Fractional limits (requires model profile data, langchain>=1.1)
agent3 = create_agent(
    model="openai:gpt-5.4",
    tools=[...],
    middleware=[
        SummarizationMiddleware(
            model="openai:gpt-5.4-mini",
            trigger=("fraction", 0.8),   # trigger at 80% of context window
            keep=("fraction", 0.3),       # keep 30% after summarization
        ),
    ],
)
```

`trigger` and `keep` accept: `("fraction", float)`, `("tokens", int)`, `("messages", int)`.

### HumanInTheLoopMiddleware

Pauses execution before specified tool calls for human review. Requires a checkpointer.

```python
from langchain.agents.middleware import HumanInTheLoopMiddleware
from langgraph.checkpoint.memory import InMemorySaver

agent = create_agent(
    model="openai:gpt-5.4",
    tools=[write_file, execute_sql, read_data],
    checkpointer=InMemorySaver(),
    middleware=[
        HumanInTheLoopMiddleware(
            interrupt_on={
                "write_file": True,           # all decisions: approve, edit, reject
                "execute_sql": {
                    "allowed_decisions": ["approve", "reject"],  # no editing
                    "description": "SQL operation pending DBA approval",
                },
                "read_data": False,            # auto-approve, no interrupt
            },
            description_prefix="Action pending approval",
        ),
    ],
)
```

See `references/human-in-the-loop.md` for full interrupt/resume flow.

### ModelCallLimitMiddleware

Caps total model invocations per run or thread.

```python
from langchain.agents.middleware import ModelCallLimitMiddleware
from langgraph.checkpoint.memory import InMemorySaver

agent = create_agent(
    model="openai:gpt-5.4",
    tools=[...],
    checkpointer=InMemorySaver(),  # required for thread_limit
    middleware=[
        ModelCallLimitMiddleware(
            thread_limit=50,   # max calls across all runs in a thread
            run_limit=10,      # max calls per single invocation
            exit_behavior="end",  # or "error"
        ),
    ],
)
```

### ToolCallLimitMiddleware

Caps tool invocations globally or per tool.

```python
from langchain.agents.middleware import ToolCallLimitMiddleware

agent = create_agent(
    model="openai:gpt-5.4",
    tools=[search_tool, database_tool, scraper_tool],
    middleware=[
        ToolCallLimitMiddleware(thread_limit=20, run_limit=10),           # global
        ToolCallLimitMiddleware(tool_name="search", thread_limit=5, run_limit=3),  # per-tool
        ToolCallLimitMiddleware(tool_name="scraper", run_limit=2, exit_behavior="error"),
    ],
)
```

`exit_behavior` options: `"continue"` (default, block with error message), `"error"`
(raise exception), `"end"` (stop with message, single-tool scenarios only).

### ModelFallbackMiddleware

Falls back to alternate models when primary fails.

```python
from langchain.agents.middleware import ModelFallbackMiddleware

agent = create_agent(
    model="openai:gpt-5.4",
    tools=[...],
    middleware=[
        ModelFallbackMiddleware(
            "openai:gpt-5.4-mini",          # first fallback
            "anthropic:claude-sonnet-4-6",  # second fallback
        ),
    ],
)
```

### PIIMiddleware

Detects and handles Personally Identifiable Information.

```python
from langchain.agents.middleware import PIIMiddleware
import re

# Built-in types: "email", "credit_card", "ip", "mac_address", "url"
agent = create_agent(
    model="openai:gpt-5.4",
    tools=[...],
    middleware=[
        PIIMiddleware("email", strategy="redact", apply_to_input=True),
        PIIMiddleware("credit_card", strategy="mask", apply_to_input=True),
        PIIMiddleware("ip", strategy="hash", apply_to_input=True, apply_to_output=True),
    ],
)

# strategy options: "redact" → [REDACTED_EMAIL], "mask" → ****,
#                  "hash" → deterministic hash, "block" → raise exception

# Custom PII type with regex pattern
agent2 = create_agent(
    model="openai:gpt-5.4",
    tools=[...],
    middleware=[
        PIIMiddleware(
            "api_key",
            detector=r"sk-[a-zA-Z0-9]{32}",  # regex string
            strategy="block",
            apply_to_input=True,
        ),
        PIIMiddleware(
            "phone_number",
            detector=re.compile(r"\+?\d{1,3}[\s.-]?\d{3,4}[\s.-]?\d{4}"),
            strategy="mask",
        ),
    ],
)

# Custom PII detector function
def detect_ssn(content: str) -> list[dict[str, str | int]]:
    """Detect US Social Security Numbers with validation."""
    matches = []
    pattern = r"\d{3}-\d{2}-\d{4}"
    for match in re.finditer(pattern, content):
        ssn = match.group(0)
        first_three = int(ssn[:3])
        if first_three not in [0, 666] and not (900 <= first_three <= 999):
            matches.append({"text": ssn, "start": match.start(), "end": match.end()})
    return matches

agent3 = create_agent(
    model="openai:gpt-5.4",
    tools=[...],
    middleware=[
        PIIMiddleware("ssn", detector=detect_ssn, strategy="hash", apply_to_input=True),
    ],
)
```

### TodoListMiddleware

Equips agents with task planning and tracking via a `write_todos` tool.

```python
from langchain.agents.middleware import TodoListMiddleware

agent = create_agent(
    model="openai:gpt-5.4",
    tools=[read_file, write_file, run_tests],
    middleware=[TodoListMiddleware()],
)
```

### LLMToolSelectorMiddleware

Pre-selects relevant tools using a cheap model before calling the main model. Useful when
you have 10+ tools.

```python
from langchain.agents.middleware import LLMToolSelectorMiddleware

agent = create_agent(
    model="openai:gpt-5.4",
    tools=[tool1, tool2, tool3, tool4, tool5, tool6, tool7, tool8],
    middleware=[
        LLMToolSelectorMiddleware(
            model="openai:gpt-5.4-mini",   # cheap model for selection
            max_tools=3,                    # expose at most 3 tools per call
            always_include=["search"],      # always available (doesn't count against max)
        ),
    ],
)
```

### ToolRetryMiddleware

Retries failed tool calls with exponential backoff.

```python
from langchain.agents.middleware import ToolRetryMiddleware

agent = create_agent(
    model="openai:gpt-5.4",
    tools=[api_tool, database_tool],
    middleware=[
        ToolRetryMiddleware(
            max_retries=3,
            backoff_factor=2.0,       # delay = initial * (factor ^ attempt)
            initial_delay=1.0,        # seconds
            max_delay=60.0,           # cap on backoff
            jitter=True,              # ±25% random variation (prevents thundering herd)
            tools=["api_tool"],       # only retry this tool (None = all tools)
            retry_on=(ConnectionError, TimeoutError),  # only retry these exceptions
            on_failure="return_message",  # or "raise" or callable
        ),
    ],
)
```

`on_failure` options: `"return_message"` (return error ToolMessage, let LLM handle),
`"raise"` (re-raise exception), `callable(exception) -> str` (custom message).

### ModelRetryMiddleware

Retries failed model calls.

```python
from langchain.agents.middleware import ModelRetryMiddleware

def should_retry(error: Exception) -> bool:
    if hasattr(error, "status_code"):
        return error.status_code in (429, 503)
    return isinstance(error, (TimeoutError, ConnectionError))

agent = create_agent(
    model="openai:gpt-5.4",
    tools=[...],
    middleware=[
        ModelRetryMiddleware(
            max_retries=3,
            retry_on=should_retry,   # callable or exception tuple
            on_failure="continue",   # return AIMessage with error instead of raising
            backoff_factor=2.0,
            initial_delay=1.0,
            max_delay=60.0,
            jitter=True,
        ),
    ],
)
```

### LLMToolEmulatorMiddleware

Emulates tool execution with an LLM for testing or prototyping.

```python
from langchain.agents.middleware import LLMToolEmulator

# Emulate all tools
agent = create_agent(
    model="openai:gpt-5.4",
    tools=[get_weather, send_email, search_database],
    middleware=[LLMToolEmulator()],
)

# Emulate only specific tools (real tools for send_email)
agent2 = create_agent(
    model="openai:gpt-5.4",
    tools=[get_weather, send_email, search_database],
    middleware=[LLMToolEmulator(tools=["get_weather", "search_database"])],
)
```

### ContextEditingMiddleware

Trims old tool outputs from context when approaching token limits.

```python
from langchain.agents.middleware import ContextEditingMiddleware, ClearToolUsesEdit

agent = create_agent(
    model="openai:gpt-5.4",
    tools=[...],
    middleware=[
        ContextEditingMiddleware(
            edits=[
                ClearToolUsesEdit(
                    trigger=100000,          # clear when > 100K tokens
                    keep=3,                  # always keep 3 most recent tool results
                    clear_tool_inputs=False, # also clear tool call args from AI messages
                    exclude_tools=[],        # never clear these tool outputs
                    placeholder="[cleared]", # replacement text for cleared outputs
                    clear_at_least=0,        # min tokens to reclaim (0 = as needed)
                ),
            ],
            token_count_method="approximate",  # or "model"
        ),
    ],
)
```

### ShellToolMiddleware

Exposes a persistent shell session to agents.

```python
from langchain.agents.middleware import ShellToolMiddleware, HostExecutionPolicy, DockerExecutionPolicy, RedactionRule

# Basic with host execution (trusted environment, e.g., inside container)
agent = create_agent(
    model="openai:gpt-5.4",
    tools=[],
    middleware=[
        ShellToolMiddleware(
            workspace_root="/workspace",
            execution_policy=HostExecutionPolicy(),
        ),
    ],
)

# Docker isolation (separate container per run)
agent_docker = create_agent(
    model="openai:gpt-5.4",
    tools=[],
    middleware=[
        ShellToolMiddleware(
            workspace_root="/workspace",
            startup_commands=["pip install requests"],
            execution_policy=DockerExecutionPolicy(
                image="python:3.11-slim",
                command_timeout=60.0,
            ),
            redaction_rules=[
                RedactionRule(pii_type="api_key", detector=r"sk-[a-zA-Z0-9]{32}"),
            ],
        ),
    ],
)
```

Note: Shell sessions do not currently support human-in-the-loop interrupts.

### FilesystemFileSearchMiddleware

Provides glob and grep tools for filesystem search.

```python
from langchain.agents.middleware import FilesystemFileSearchMiddleware

agent = create_agent(
    model="openai:gpt-5.4",
    tools=[],
    middleware=[
        FilesystemFileSearchMiddleware(
            root_path="/workspace",
            use_ripgrep=True,
            max_file_size_mb=10,
        ),
    ],
)

# Agent now has glob_search(pattern) and grep_search(pattern, include=) tools
result = agent.invoke({"messages": [{"role": "user", "content": "Find all Python files containing 'async def'"}]})
```

### FilesystemMiddleware (deepagents)

Gives agents a filesystem for storing context and long-term memories.

```python
from deepagents.middleware.filesystem import FilesystemMiddleware
from deepagents.backends import CompositeBackend, StateBackend, StoreBackend
from langgraph.store.memory import InMemoryStore

store = InMemoryStore()

agent = create_agent(
    model="anthropic:claude-sonnet-4-6",
    store=store,
    middleware=[
        FilesystemMiddleware(
            backend=CompositeBackend(
                default=StateBackend(),        # ephemeral (lost between threads)
                routes={"/memories/": StoreBackend()}  # persistent (survives threads)
            ),
        ),
    ],
)
# Agent gets ls, read_file, write_file, edit_file tools
# Files under /memories/ persist across threads; all others are ephemeral
```

### SubAgentMiddleware (deepagents)

Lets the agent spawn subagents via a `task` tool.

```python
from langchain.tools import tool
from langchain.agents import create_agent
from deepagents.middleware.subagents import SubAgentMiddleware

@tool
def get_weather(city: str) -> str:
    """Get the weather in a city."""
    return f"The weather in {city} is sunny."

agent = create_agent(
    model="anthropic:claude-sonnet-4-6",
    middleware=[
        SubAgentMiddleware(
            default_model="anthropic:claude-sonnet-4-6",
            default_tools=[],
            subagents=[
                {
                    "name": "weather",
                    "description": "Gets weather data for cities.",
                    "system_prompt": "Use get_weather to fetch city weather.",
                    "tools": [get_weather],
                    "model": "openai:gpt-5.4",
                    "middleware": [],
                }
            ],
        )
    ],
)
```

## Custom middleware patterns

### Dynamic prompt injection

```python
from langchain.agents.middleware import wrap_model_call, ModelRequest, ModelResponse
from langchain.messages import SystemMessage
from typing import Callable

@wrap_model_call
def add_context(
    request: ModelRequest,
    handler: Callable[[ModelRequest], ModelResponse],
) -> ModelResponse:
    """Inject additional context into the system message."""
    # request.system_message is always a SystemMessage object
    # Use content_blocks to get list representation
    new_content = list(request.system_message.content_blocks) + [
        {"type": "text", "text": f"Current date: 2026-04-25. User timezone: UTC+5."}
    ]
    new_system = SystemMessage(content=new_content)
    return handler(request.override(system_message=new_system))
```

### Anthropic prompt caching in middleware

```python
@wrap_model_call
def add_cached_knowledge(
    request: ModelRequest,
    handler: Callable[[ModelRequest], ModelResponse],
) -> ModelResponse:
    """Inject a large document into the system prompt with Anthropic cache control."""
    new_content = list(request.system_message.content_blocks) + [
        {
            "type": "text",
            "text": "<large document — e.g., 50K token knowledge base>",
            "cache_control": {"type": "ephemeral"},  # Anthropic caches this
        }
    ]
    new_system = SystemMessage(content=new_content)
    return handler(request.override(system_message=new_system))
```

### Dynamic tool filtering by permissions

```python
from langchain.agents.middleware import wrap_model_call, ModelRequest, ModelResponse
from dataclasses import dataclass
from typing import Callable

@dataclass
class Context:
    user_role: str  # "admin", "editor", "viewer"

@wrap_model_call
def filter_tools_by_role(
    request: ModelRequest,
    handler: Callable[[ModelRequest], ModelResponse],
) -> ModelResponse:
    if request.runtime is None or request.runtime.context is None:
        role = "viewer"
    else:
        role = request.runtime.context.user_role

    if role == "admin":
        pass  # all tools available
    elif role == "editor":
        tools = [t for t in request.tools if t.name != "delete_data"]
        request = request.override(tools=tools)
    else:  # viewer
        tools = [t for t in request.tools if t.name.startswith("read_")]
        request = request.override(tools=tools)

    return handler(request)

agent = create_agent(
    model="openai:gpt-5.4",
    tools=[read_data, write_data, delete_data],
    middleware=[filter_tools_by_role],
    context_schema=Context,
)
```

### Runtime tool registration (discovered tools)

When tools are discovered at runtime (e.g., from an MCP server, API registry):

```python
from langchain.tools import tool
from langchain.agents import create_agent
from langchain.agents.middleware import AgentMiddleware, ModelRequest, ToolCallRequest
from langchain.messages import ToolMessage

@tool
def calculate_tip(bill_amount: float, tip_percentage: float = 20.0) -> str:
    """Calculate the tip amount for a bill."""
    tip = bill_amount * (tip_percentage / 100)
    return f"Tip: ${tip:.2f}, Total: ${bill_amount + tip:.2f}"

class DynamicToolMiddleware(AgentMiddleware):
    """Registers and handles tools discovered at runtime."""

    def wrap_model_call(self, request: ModelRequest, handler):
        # Inject the dynamic tool into every model request
        updated = request.override(tools=[*request.tools, calculate_tip])
        return handler(updated)

    def wrap_tool_call(self, request: ToolCallRequest, handler):
        # Route tool calls to the dynamic tool's implementation
        if request.tool_call["name"] == "calculate_tip":
            return handler(request.override(tool=calculate_tip))
        return handler(request)

agent = create_agent(
    model="openai:gpt-5.4",
    tools=[get_weather],       # static tools only here
    middleware=[DynamicToolMiddleware()],
)
# Agent can now use both get_weather AND calculate_tip
```

### LLM-as-judge guardrail (after_agent)

```python
from langchain.agents.middleware import after_agent, AgentState
from langchain.messages import AIMessage
from langchain.chat_models import init_chat_model
from langgraph.config import get_stream_writer
from langgraph.runtime import Runtime
from pydantic import BaseModel
from typing import Literal, Any

class SafetyEval(BaseModel):
    evaluation: Literal["safe", "unsafe"]
    reason: str

safety_model = init_chat_model("openai:gpt-5.4")

@after_agent(can_jump_to=["end"])
def safety_guardrail(state: AgentState, runtime: Runtime) -> dict[str, Any] | None:
    """Block unsafe responses using an LLM judge."""
    if not state["messages"]:
        return None
    last = state["messages"][-1]
    if not isinstance(last, AIMessage):
        return None

    structured = safety_model.with_structured_output(SafetyEval)
    result = structured.invoke([
        {"role": "system", "content": "Evaluate this AI response as safe or unsafe."},
        {"role": "user", "content": f"Response: {last.text}"},
    ])

    if result.evaluation == "unsafe":
        state["messages"][-1] = AIMessage(
            "I cannot provide that response. Please rephrase your request."
        )

    return None  # state mutation is enough; no dict update needed
```
