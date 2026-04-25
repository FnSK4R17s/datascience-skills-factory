# Agents

Source: `docs/agents.md`, `docs/overview.md`, `docs/structured-output.md`

## What is an agent?

An agent combines a language model with tools to create a system that reasons about tasks,
decides which tools to use, and iteratively works toward solutions. `create_agent` builds
a graph-based agent runtime using LangGraph. The loop is:

```
input → model → (tool call?) → tools → model → ... → final output
```

The agent runs until it either emits a final response (no tool calls) or hits an iteration
limit. This is the ReAct ("Reasoning + Acting") pattern.

## create_agent full signature

```python
from langchain.agents import create_agent

agent = create_agent(
    model,           # str | BaseChatModel — required
    tools=[...],     # list of callables or @tool-decorated functions
    system_prompt="...",   # str | SystemMessage | None
    name="my_agent",       # snake_case identifier for multi-agent use
    middleware=[...],      # list of middleware instances
    response_format=None,  # schema type, ToolStrategy, or ProviderStrategy
    state_schema=None,     # TypedDict subclass of AgentState (shortcut for tools-only state)
    context_schema=None,   # dataclass or TypedDict for immutable runtime context
    store=None,            # BaseStore for long-term memory
    checkpointer=None,     # for human-in-the-loop / persistence
)
```

Model can be:
- A model identifier string: `"openai:gpt-5.4"`, `"anthropic:claude-sonnet-4-6"`,
  `"google_genai:gemini-2.5-flash-lite"` — provider:model format, or just model name
  (auto-inferred for major providers).
- A provider class instance: `ChatOpenAI(model="gpt-5.4", temperature=0.1, max_tokens=1000)`.
  Use this for full parameter control.

Provider class instances should NOT have `bind_tools` pre-called — this conflicts with
`response_format` (see structured output reference).

## Invocation

```python
# Basic invoke
result = agent.invoke(
    {"messages": [{"role": "user", "content": "Hello"}]},
)

# With context (immutable per-run config)
result = agent.invoke(
    {"messages": [{"role": "user", "content": "Hello"}]},
    context={"user_id": "abc"},  # or UserContext(user_id="abc") if context_schema is a dataclass
)

# With thread_id for persistence/memory
result = agent.invoke(
    {"messages": [{"role": "user", "content": "Hello"}]},
    {"configurable": {"thread_id": "session-1"}},
)

# result is a dict: {"messages": [...], "structured_response": ...}
last_msg = result["messages"][-1]
print(last_msg.text)           # convenience str property
print(last_msg.content_blocks) # normalized list of typed content dicts
```

For async use `await agent.ainvoke(...)`.

### v2 invoke result

```python
# With version="v2", invoke returns a GraphOutput object
result = agent.invoke(
    {"messages": [{"role": "user", "content": "Hello"}]},
    version="v2",
)
print(result.value)       # dict with messages, structured_response, etc.
print(result.interrupts)  # tuple of Interrupt objects (empty if none)
```

## AgentState and custom state

All agents carry `AgentState` which includes `messages`. Extend it with `TypedDict`:

```python
from langchain.agents import AgentState, create_agent
from typing import TypedDict
from typing_extensions import NotRequired

class MyState(AgentState):
    user_name: str
    call_count: NotRequired[int]  # NotRequired allows omitting field at invocation

agent = create_agent(model, tools=tools, state_schema=MyState)
result = agent.invoke({
    "messages": [{"role": "user", "content": "Hello"}],
    "user_name": "Alice",
    "call_count": 0,
})
```

**Important:** Pydantic models and dataclasses are NOT accepted for state schemas in v1+.
They are still valid for tool input schemas and structured output schemas.

### State via middleware (preferred)

Defining custom state via middleware is preferred when the state is logically owned by
a specific middleware component. This keeps state extensions conceptually scoped:

```python
from langchain.agents.middleware import AgentMiddleware, AgentState
from typing import Any
from typing_extensions import NotRequired

class CustomState(AgentState):
    user_preferences: NotRequired[dict]
    model_call_count: NotRequired[int]

class CustomMiddleware(AgentMiddleware):
    state_schema = CustomState  # extends the agent's state schema
    tools = [my_extra_tool]     # tools scoped to this middleware

    def before_model(self, state: CustomState, runtime) -> dict[str, Any] | None:
        count = state.get("model_call_count", 0)
        return {"model_call_count": count + 1}

    def after_model(self, state: CustomState, runtime) -> dict[str, Any] | None:
        prefs = state.get("user_preferences", {})
        print(f"User preferences: {prefs}")
        return None

agent = create_agent(
    model,
    tools=tools,
    middleware=[CustomMiddleware()],
)

result = agent.invoke({
    "messages": [{"role": "user", "content": "I prefer technical explanations"}],
    "user_preferences": {"style": "technical", "verbosity": "detailed"},
})
```

## Structured output (response_format)

The agent returns structured data in `result["structured_response"]`. Three forms:

### 1. Auto-select (pass schema type directly)

```python
from pydantic import BaseModel, Field

class Report(BaseModel):
    summary: str = Field(description="One-sentence summary")
    confidence: float = Field(description="0.0 to 1.0")

agent = create_agent(model, tools=tools, response_format=Report)
result = agent.invoke({"messages": [{"role": "user", "content": "Analyse..."}]})
report = result["structured_response"]  # Report instance
```

LangChain auto-selects `ProviderStrategy` if the model supports native structured output
(OpenAI, Anthropic, Google Gemini, xAI), otherwise `ToolStrategy`.

### 2. ProviderStrategy (explicit native JSON from provider)

```python
from langchain.agents.structured_output import ProviderStrategy

agent = create_agent(
    model="openai:gpt-5.4",
    tools=tools,
    response_format=ProviderStrategy(Report),
    # strict=True  # OpenAI and xAI only (langchain>=1.2)
)
```

### 3. ToolStrategy (explicit, works with any model supporting tool calling)

```python
from langchain.agents.structured_output import ToolStrategy
from typing import Literal, Union

class ProductReview(BaseModel):
    rating: int | None = Field(ge=1, le=5)
    sentiment: Literal["positive", "negative"]
    key_points: list[str]

class CustomerComplaint(BaseModel):
    issue_type: Literal["product", "service", "shipping"]
    severity: Literal["low", "medium", "high"]
    description: str

agent = create_agent(
    model="openai:gpt-5.4",
    tools=[search_tool],
    response_format=ToolStrategy(
        schema=Union[ProductReview, CustomerComplaint],  # model picks the right schema
        handle_errors=True,               # retry on validation failure (default)
        tool_message_content="Analysis captured.",  # optional custom ack
    )
)
result = agent.invoke({"messages": [{"role": "user", "content": "Analyze review..."}]})
# result["structured_response"] is ProductReview or CustomerComplaint
```

`handle_errors` options:
| Value | Behaviour |
|-------|-----------|
| `True` (default) | Catch all errors, use default retry message |
| `False` | All errors propagate, no retry |
| `str` | Catch all errors, use this fixed retry message |
| `type[Exception]` | Only catch this type, default message |
| `tuple[type[Exception], ...]` | Only catch these types |
| `Callable[[Exception], str]` | Custom handler returns retry message |

Custom error handler:
```python
from langchain.agents.structured_output import (
    StructuredOutputValidationError,
    MultipleStructuredOutputsError,
)

def my_error_handler(error: Exception) -> str:
    if isinstance(error, StructuredOutputValidationError):
        return "Format error, please retry with valid schema."
    elif isinstance(error, MultipleStructuredOutputsError):
        return "Return exactly one structured response."
    return f"Error: {error}"

agent = create_agent(
    model="openai:gpt-5.4",
    response_format=ToolStrategy(schema=Report, handle_errors=my_error_handler),
)
```

## System prompt

Static string, `SystemMessage`, or dynamic via middleware:

```python
# Simple string
agent = create_agent(model, tools, system_prompt="You are a helpful assistant.")

# SystemMessage (allows provider-specific features like Anthropic prompt caching)
from langchain.messages import SystemMessage

agent = create_agent(
    model="anthropic:claude-sonnet-4-6",
    tools=tools,
    system_prompt=SystemMessage(content=[
        {"type": "text", "text": "You are an AI assistant."},
        {
            "type": "text",
            "text": "<large document content>",
            "cache_control": {"type": "ephemeral"},  # Anthropic prompt caching
        },
    ]),
)

# Dynamic system prompt via middleware
from langchain.agents.middleware import dynamic_prompt, ModelRequest

@dynamic_prompt
def role_based_prompt(request: ModelRequest) -> str:
    role = request.runtime.context.get("user_role", "user")
    if role == "expert":
        return "You are a helpful assistant. Provide detailed technical responses."
    elif role == "beginner":
        return "You are a helpful assistant. Explain concepts simply, avoid jargon."
    return "You are a helpful assistant."

agent = create_agent(model, tools, middleware=[role_based_prompt])
```

## Agent name (for multi-agent)

```python
agent = create_agent(
    model,
    tools,
    name="research_assistant"  # snake_case; becomes node name in multi-agent graphs
)
```

Names must be snake_case. Some providers reject spaces or special characters.

## Dynamic model selection

Use `@wrap_model_call` middleware to swap models at runtime:

```python
from langchain.agents.middleware import wrap_model_call, ModelRequest, ModelResponse
from langchain_openai import ChatOpenAI
from langchain_anthropic import ChatAnthropic

basic_model = ChatOpenAI(model="gpt-5.4-mini")
advanced_model = ChatAnthropic(model="claude-sonnet-4-6")

@wrap_model_call
def dynamic_model_selection(request: ModelRequest, handler) -> ModelResponse:
    message_count = len(request.state["messages"])
    if message_count > 10:
        model = advanced_model
    else:
        model = basic_model
    return handler(request.override(model=model))

agent = create_agent(model=basic_model, tools=tools, middleware=[dynamic_model_selection])
```

## Multi-agent and subgraphs

Name agents with `name="snake_case"`. The name becomes the node name when the agent
is embedded as a subgraph.

```python
# Wrap a subagent as a tool
inner_agent = create_agent(model, tools=[weather_tool], name="weather_agent")

def call_weather_agent(query: str) -> str:
    """Ask the weather specialist agent."""
    result = inner_agent.invoke({"messages": [{"role": "user", "content": query}]})
    return result["messages"][-1].text

outer_agent = create_agent(
    model,
    tools=[call_weather_agent],
    name="supervisor",
    system_prompt="You coordinate specialist agents.",
)
```

When streaming multi-agent output, set `subgraphs=True` on `stream()` and use
the `lc_agent_name` key in chunk metadata to disambiguate sources (see streaming reference).

## Runtime context (context_schema)

Pass immutable per-invocation data. Define as a dataclass or TypedDict:

```python
from dataclasses import dataclass
from langchain.agents import create_agent
from langchain.tools import tool, ToolRuntime

@dataclass
class UserContext:
    user_id: str
    role: str  # "admin", "editor", "viewer"

@tool
def get_account(runtime: ToolRuntime[UserContext]) -> str:
    """Get account info for the current user."""
    return f"Account for {runtime.context.user_id} (role: {runtime.context.role})"

agent = create_agent(
    model="openai:gpt-5.4",
    tools=[get_account],
    context_schema=UserContext,
)

# At invocation time — context is immutable during the run
result = agent.invoke(
    {"messages": [{"role": "user", "content": "What's my account?"}]},
    context=UserContext(user_id="user123", role="admin"),
)
```

## Complete example: customer support agent

```python
from dataclasses import dataclass
from typing import Literal
from typing_extensions import NotRequired
from pydantic import BaseModel, Field

from langchain.agents import create_agent, AgentState
from langchain.agents.middleware import (
    HumanInTheLoopMiddleware,
    SummarizationMiddleware,
    PIIMiddleware,
    ModelFallbackMiddleware,
)
from langchain.agents.structured_output import ToolStrategy
from langchain.tools import tool, ToolRuntime
from langchain.messages import ToolMessage
from langgraph.checkpoint.memory import InMemorySaver
from langgraph.store.memory import InMemoryStore
from langgraph.types import Command

# State schema
class SupportState(AgentState):
    ticket_id: NotRequired[str]
    issue_category: NotRequired[str]

# Context schema
@dataclass
class CustomerContext:
    customer_id: str
    account_tier: Literal["free", "pro", "enterprise"]

# Structured output schema
class Resolution(BaseModel):
    action: Literal["resolved", "escalated", "needs_more_info"]
    summary: str = Field(description="Brief resolution summary")
    ticket_id: str

# Tools
@tool
def lookup_account(runtime: ToolRuntime[CustomerContext, SupportState]) -> str:
    """Look up customer account details."""
    cid = runtime.context.customer_id
    tier = runtime.context.account_tier
    return f"Customer {cid}: {tier} tier account"

@tool
def create_ticket(category: str, runtime: ToolRuntime[CustomerContext, SupportState]) -> Command:
    """Create a support ticket for this issue."""
    import uuid
    ticket_id = str(uuid.uuid4())[:8]
    return Command(
        update={
            "ticket_id": ticket_id,
            "issue_category": category,
            "messages": [
                ToolMessage(
                    content=f"Ticket {ticket_id} created for {category} issue.",
                    tool_call_id=runtime.tool_call_id,
                )
            ],
        }
    )

@tool
def send_resolution(message: str, runtime: ToolRuntime) -> str:
    """Send a resolution message to the customer."""
    return f"Resolution sent: {message}"

agent = create_agent(
    model="anthropic:claude-sonnet-4-6",
    tools=[lookup_account, create_ticket, send_resolution],
    system_prompt="You are a customer support agent. Look up accounts, create tickets, and resolve issues.",
    state_schema=SupportState,
    context_schema=CustomerContext,
    response_format=ToolStrategy(Resolution),
    checkpointer=InMemorySaver(),
    store=InMemoryStore(),
    middleware=[
        SummarizationMiddleware(model="openai:gpt-5.4-mini", trigger=("tokens", 4000)),
        PIIMiddleware("credit_card", strategy="mask", apply_to_input=True),
        HumanInTheLoopMiddleware(interrupt_on={"send_resolution": True}),
        ModelFallbackMiddleware("openai:gpt-5.4"),
    ],
)

# Invoke
result = agent.invoke(
    {"messages": [{"role": "user", "content": "My payment is failing."}]},
    context=CustomerContext(customer_id="cust_123", account_tier="pro"),
)
resolution = result["structured_response"]  # Resolution instance
print(resolution.action, resolution.summary)
```
