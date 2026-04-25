# Streaming

Source: `docs/streaming.md`, `docs/messages.md`

## Overview

Streaming surfaces real-time output from agent runs. All streaming goes through
`agent.stream()` or `agent.astream()`. The recommended format is `version="v2"`,
which requires `langgraph>=1.1`. Without `version="v2"`, multi-mode streams yield
`(mode, data)` tuples — less ergonomic.

## Stream modes

| Mode | What it emits |
|------|--------------|
| `"updates"` | Full state after each agent step (one event per node) |
| `"messages"` | `(token, metadata)` tuples from every LLM call as tokens arrive |
| `"custom"` | Arbitrary data emitted by tools/middleware via `get_stream_writer` |

Combine modes: `stream_mode=["messages", "updates"]`.

## v2 streaming format

With `version="v2"`, every chunk is a `StreamPart` dict:

```python
{"type": "updates" | "messages" | "custom", "ns": [...], "data": <payload>}
```

Use `chunk["type"]` to dispatch, `chunk["data"]` for the payload. Every stream mode
produces this same shape — no more mode-specific tuple unpacking.

## Stream agent progress (updates mode)

Emits state after each node execution. A single tool call produces three update events:
model node (AIMessage with tool_call), tools node (ToolMessage), model node (final AIMessage).

```python
from langchain.agents import create_agent

def get_weather(city: str) -> str:
    """Get weather for a city."""
    return f"It's always sunny in {city}!"

agent = create_agent(model="openai:gpt-5.4", tools=[get_weather])

for chunk in agent.stream(
    {"messages": [{"role": "user", "content": "What is the weather in SF?"}]},
    stream_mode="updates",
    version="v2",
):
    if chunk["type"] == "updates":
        for step_name, step_data in chunk["data"].items():
            last = step_data["messages"][-1]
            print(f"[{step_name}] {last.content_blocks}")
```

Expected output sequence:
```
[model] [{'type': 'tool_call', 'name': 'get_weather', 'args': {'city': 'San Francisco'}, ...}]
[tools] [{'type': 'text', 'text': "It's always sunny in San Francisco!"}]
[model] [{'type': 'text', 'text': "It's always sunny in San Francisco!"}]
```

## Stream LLM tokens (messages mode)

Streams tokens as the LLM generates them. Metadata includes which node emitted the token.

```python
from langchain.messages import AIMessageChunk

for chunk in agent.stream(
    {"messages": [{"role": "user", "content": "Tell me about Paris."}]},
    stream_mode="messages",
    version="v2",
):
    if chunk["type"] == "messages":
        token, metadata = chunk["data"]
        node = metadata["langgraph_node"]
        if isinstance(token, AIMessageChunk):
            for block in token.content_blocks:
                if block["type"] == "text":
                    print(block["text"], end="", flush=True)
```

## Stream reasoning tokens

Filter `content_blocks` for `type == "reasoning"`. LangChain normalises Anthropic
`thinking` blocks and OpenAI reasoning summaries into the standard `"reasoning"` type.

```python
from langchain.messages import AIMessageChunk
from langchain_anthropic import ChatAnthropic

model = ChatAnthropic(
    model_name="claude-sonnet-4-6",
    thinking={"type": "enabled", "budget_tokens": 5000},
)
agent = create_agent(model=model, tools=[get_weather])

for chunk in agent.stream(
    {"messages": [{"role": "user", "content": "What's the weather in SF?"}]},
    stream_mode="messages",
    version="v2",
):
    if chunk["type"] == "messages":
        token, metadata = chunk["data"]
        if not isinstance(token, AIMessageChunk):
            continue
        for block in token.content_blocks:
            if block["type"] == "reasoning":
                print(f"[thinking] {block['reasoning']}", end="")
            elif block["type"] == "text":
                print(block["text"], end="")
```

Example output:
```
[thinking] The user is asking about the weather in San Francisco. I have a get_weather
[thinking]  tool available. Let me call it.
The weather in San Francisco is: It's always sunny in San Francisco!
```

## Emit custom updates from tools

```python
from langgraph.config import get_stream_writer

def long_task(item: str) -> str:
    """Process an item with progress reporting."""
    writer = get_stream_writer()
    writer(f"Starting: {item}")
    # ... work ...
    writer(f"50% complete")
    # ... more work ...
    writer(f"Done: {item}")
    return "result"

agent = create_agent(model="openai:gpt-5.4", tools=[long_task])

for chunk in agent.stream(
    {"messages": [{"role": "user", "content": "Process 'sales_report'"}]},
    stream_mode="custom",
    version="v2",
):
    if chunk["type"] == "custom":
        print(chunk["data"])
```

Alternatively, access via `runtime.stream_writer` in `ToolRuntime` (see tools reference).

Note: `get_stream_writer()` inside a tool means the tool cannot be called outside a
LangGraph execution context.

## Stream tool calls and completed messages together

Combine `"messages"` and `"updates"` for the richest view:

```python
from langchain.messages import AIMessage, AIMessageChunk, ToolMessage

def _render_token_chunk(token: AIMessageChunk) -> None:
    if token.text:
        print(token.text, end="|")
    if token.tool_call_chunks:
        print(token.tool_call_chunks)

def _render_completed(message) -> None:
    if isinstance(message, AIMessage) and message.tool_calls:
        print(f"Tool calls: {message.tool_calls}")
    if isinstance(message, ToolMessage):
        print(f"Tool result: {message.content_blocks}")

input_message = {"role": "user", "content": "What is the weather in Boston?"}

for chunk in agent.stream(
    {"messages": [input_message]},
    stream_mode=["messages", "updates"],
    version="v2",
):
    if chunk["type"] == "messages":
        token, metadata = chunk["data"]
        if isinstance(token, AIMessageChunk):
            _render_token_chunk(token)
    elif chunk["type"] == "updates":
        for source, update in chunk["data"].items():
            if source in ("model", "tools"):
                _render_completed(update["messages"][-1])
```

### Accumulate chunks to get complete tool calls

Use `chunk_position == "last"` to detect when a complete tool call has been assembled:

```python
full_message = None
for chunk in agent.stream(
    {"messages": [input_message]},
    stream_mode=["messages", "updates"],
    version="v2",
):
    if chunk["type"] == "messages":
        token, metadata = chunk["data"]
        if isinstance(token, AIMessageChunk):
            full_message = token if full_message is None else full_message + token
            if token.chunk_position == "last":
                # full_message now has the complete AIMessage
                if full_message.tool_calls:
                    print(f"Complete tool calls: {full_message.tool_calls}")
                full_message = None
    elif chunk["type"] == "updates":
        for source, update in chunk["data"].items():
            if source == "tools":
                _render_completed(update["messages"][-1])
```

## Human-in-the-loop during streaming

Interrupts appear in `"updates"` chunks under the `"__interrupt__"` key:

```python
from langchain.agents.middleware import HumanInTheLoopMiddleware
from langgraph.checkpoint.memory import InMemorySaver
from langgraph.types import Command, Interrupt

checkpointer = InMemorySaver()
agent = create_agent(
    "openai:gpt-5.4",
    tools=[get_weather],
    middleware=[HumanInTheLoopMiddleware(interrupt_on={"get_weather": True})],
    checkpointer=checkpointer,
)

config = {"configurable": {"thread_id": "hitl-session-1"}}
interrupts = []

# First run — will pause at get_weather call
for chunk in agent.stream(
    {"messages": [{"role": "user", "content": "Weather in Boston and SF?"}]},
    config=config,
    stream_mode=["messages", "updates"],
    version="v2",
):
    if chunk["type"] == "messages":
        token, metadata = chunk["data"]
        if isinstance(token, AIMessageChunk) and token.text:
            print(token.text, end="")
    elif chunk["type"] == "updates":
        for source, update in chunk["data"].items():
            if source == "__interrupt__":
                interrupts.extend(update)
                for action in update[0].value["action_requests"]:
                    print(f"\nPending: {action['description']}")

# Build decisions (approve Boston edit, approve SF as-is)
decisions = {}
for interrupt in interrupts:
    decisions[interrupt.id] = {
        "decisions": [
            {
                "type": "edit",
                "edited_action": {"name": "get_weather", "args": {"city": "Boston, MA"}},
            },
            {"type": "approve"},
        ]
    }

# Resume
for chunk in agent.stream(
    Command(resume=decisions),
    config=config,
    stream_mode=["messages", "updates"],
    version="v2",
):
    if chunk["type"] == "updates":
        for source, update in chunk["data"].items():
            if source == "tools":
                print(f"\nTool result: {update['messages'][-1].content}")
    elif chunk["type"] == "messages":
        token, _ = chunk["data"]
        if isinstance(token, AIMessageChunk) and token.text:
            print(token.text, end="")
```

## Multi-agent streaming

Name each agent and use `subgraphs=True` to stream tokens from all nested agents.
Disambiguate sources via `metadata["lc_agent_name"]`:

```python
from langchain.chat_models import init_chat_model

weather_agent = create_agent(
    model=init_chat_model("openai:gpt-5.4"),
    tools=[get_weather],
    name="weather_agent",  # required for disambiguation
)

def call_weather_agent(query: str) -> str:
    """Delegate to the weather specialist."""
    result = weather_agent.invoke({"messages": [{"role": "user", "content": query}]})
    return result["messages"][-1].text

supervisor = create_agent(
    model=init_chat_model("openai:gpt-5.4"),
    tools=[call_weather_agent],
    name="supervisor",
)

current_agent = None
for chunk in supervisor.stream(
    {"messages": [{"role": "user", "content": "Weather in Boston?"}]},
    stream_mode=["messages", "updates"],
    subgraphs=True,      # stream from nested agents
    version="v2",
):
    if chunk["type"] == "messages":
        token, metadata = chunk["data"]
        if agent_name := metadata.get("lc_agent_name"):
            if agent_name != current_agent:
                print(f"\n--- {agent_name} ---")
                current_agent = agent_name
        if isinstance(token, AIMessageChunk) and token.text:
            print(token.text, end="")
```

## v2 invoke

```python
result = agent.invoke(
    {"messages": [{"role": "user", "content": "Hello"}]},
    version="v2",
)
result.value       # dict with messages, structured_response, etc.
result.interrupts  # tuple of Interrupt objects (empty if none)
```

## Disable streaming for a specific model

```python
from langchain_openai import ChatOpenAI

# When you don't want a specific model to stream tokens (e.g., in multi-agent setups)
model = ChatOpenAI(model="gpt-5.4", streaming=False)

# Universal fallback (works on all BaseChatModel):
# model = ChatOpenAI(model="gpt-5.4", disable_streaming=True)
```

## Complete streaming patterns reference

| Pattern | stream_mode | version | Notes |
|---------|-------------|---------|-------|
| Progress only | `"updates"` | `"v2"` | Step-level; each node fires once |
| Token streaming | `"messages"` | `"v2"` | Per-token; includes tool call chunks |
| Custom progress | `"custom"` | `"v2"` | From `get_stream_writer()` in tools |
| Rich combined | `["messages", "updates"]` | `"v2"` | Both tokens + completed step state |
| Full kitchen sink | `["messages", "updates", "custom"]` | `"v2"` | Everything |
| Reasoning tokens | `"messages"` | `"v2"` | Filter blocks for `type == "reasoning"` |
| Multi-agent | `["messages", "updates"]` | `"v2"` | `subgraphs=True`, check `lc_agent_name` |
| HITL | `["messages", "updates"]` | `"v2"` | Watch `__interrupt__` in updates |
