# Agents

Source: `docs/agents.md`, `docs/overview.md`, `docs/structured-output.md`

## create_agent signature

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

Model can be a model identifier string (`"openai:gpt-4o"`, `"anthropic:claude-sonnet-4-6"`)
or a provider class instance (`ChatOpenAI(...)`, `ChatAnthropic(...)`). Provider class gives
full control over `temperature`, `max_tokens`, `timeout`, etc.

Provider class instances should NOT have `bind_tools` pre-called — this conflicts with
`response_format` (see structured output).

## Invocation

```python
result = agent.invoke(
    {"messages": [{"role": "user", "content": "Hello"}]},
    context={"user_id": "abc"},  # optional runtime context
)
# result is a dict with "messages" key (and "structured_response" if response_format set)
last_msg = result["messages"][-1]
print(last_msg.text)           # convenience str property
print(last_msg.content_blocks) # normalized list of typed content dicts
```

For async invocation use `await agent.ainvoke(...)`.

## AgentState and custom state

All agents carry `AgentState` which includes `messages`. Extend it with `TypedDict`:

```python
from langchain.agents import AgentState
from typing import TypedDict

class MyState(AgentState):
    user_name: str
    call_count: int

agent = create_agent(model, tools=tools, state_schema=MyState)
result = agent.invoke({
    "messages": [...],
    "user_name": "Alice",
    "call_count": 0,
})
```

Note: Pydantic models and dataclasses are not accepted for state schemas in v1+
(they are still valid for tool input schemas and structured output schemas).

Defining state via middleware is preferred when the state is logically owned by
a specific middleware component.

## Structured output (response_format)

The agent returns structured data in `result["structured_response"]`. Three forms:

### 1. Auto-select (pass schema type directly)

```python
from pydantic import BaseModel

class Report(BaseModel):
    summary: str
    confidence: float

agent = create_agent(model, tools=tools, response_format=Report)
result = agent.invoke({...})
report = result["structured_response"]  # Report instance
```

LangChain selects `ProviderStrategy` if the model supports native structured output,
otherwise falls back to `ToolStrategy`.

### 2. ProviderStrategy (explicit)

```python
from langchain.agents.structured_output import ProviderStrategy

agent = create_agent(
    model,
    response_format=ProviderStrategy(Report)
)
```

Supported by OpenAI, Anthropic (Claude), Google Gemini, xAI (Grok). Pass `strict=True`
where the provider supports it (OpenAI, xAI).

### 3. ToolStrategy (explicit, works with any model that supports tool calling)

```python
from langchain.agents.structured_output import ToolStrategy
from typing import Union

agent = create_agent(
    model,
    response_format=ToolStrategy(
        schema=Union[Report, ErrorResponse],
        handle_errors=True,   # retry on validation failure (default)
        tool_message_content="Report generated.",  # optional custom ack
    )
)
```

`handle_errors` accepts: `True` (all errors, default message), `False` (propagate),
`str` (fixed retry message), `type[Exception]` or tuple, or a callable
`(Exception) -> str`.

Supported schema types for both strategies: Pydantic `BaseModel`, `dataclass`,
`TypedDict`, JSON Schema dict. For `ToolStrategy` only: `Union` of schemas.

## Dynamic model selection

Use `@wrap_model_call` middleware to swap models at runtime — see `middleware.md`.

## Multi-agent and subgraphs

Name agents with `name="snake_case"`. The name becomes the node name when the agent
is embedded as a subgraph. Use `result["messages"][-1].text` to extract the last
response when calling one agent from another.

```python
inner_agent = create_agent(model, tools=[...], name="weather_agent")

def call_inner(query: str) -> str:
    """Ask the weather agent."""
    res = inner_agent.invoke({"messages": [{"role": "user", "content": query}]})
    return res["messages"][-1].text

outer_agent = create_agent(model, tools=[call_inner], name="supervisor")
```

When streaming multi-agent output, set `subgraphs=True` on `stream()` and use
the `lc_agent_name` key in chunk metadata to disambiguate sources.
