# Streaming

Source: `docs/streaming.md`, `docs/messages.md`

## Overview

Streaming surfaces real-time output from agent runs. All streaming goes through
`agent.stream()` or `agent.astream()`. The recommended format is `version="v2"`,
which requires `langgraph>=1.1`.

## Stream modes

Pass one or more modes as `stream_mode`:

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

Without `version="v2"`, multi-mode streams yield `(mode, data)` tuples — less
convenient to dispatch.

## Stream agent progress (updates mode)

```python
for chunk in agent.stream(
    {"messages": [{"role": "user", "content": "..."}]},
    stream_mode="updates",
    version="v2",
):
    if chunk["type"] == "updates":
        for step_name, step_data in chunk["data"].items():
            last = step_data["messages"][-1]
            print(f"{step_name}: {last.content_blocks}")
```

A single tool call produces three update events: model node (AIMessage with
tool_call), tools node (ToolMessage with result), model node (final AIMessage).

## Stream LLM tokens (messages mode)

```python
for chunk in agent.stream(
    {"messages": [{"role": "user", "content": "..."}]},
    stream_mode="messages",
    version="v2",
):
    if chunk["type"] == "messages":
        token, metadata = chunk["data"]
        # metadata["langgraph_node"] — which node emitted this token
        for block in token.content_blocks:
            if block["type"] == "text":
                print(block["text"], end="")
```

## Stream reasoning tokens

Filter `content_blocks` for `type == "reasoning"`. Works the same regardless
of provider — LangChain normalises Anthropic `thinking` blocks and OpenAI
reasoning summaries into the standard `"reasoning"` type.

```python
from langchain.messages import AIMessageChunk

for chunk in agent.stream(
    {"messages": [{"role": "user", "content": "..."}]},
    stream_mode="messages",
    version="v2",
):
    if chunk["type"] == "messages":
        token, _ = chunk["data"]
        if not isinstance(token, AIMessageChunk):
            continue
        for block in token.content_blocks:
            if block["type"] == "reasoning":
                print(f"[thinking] {block['reasoning']}", end="")
            elif block["type"] == "text":
                print(block["text"], end="")
```

Reasoning output must be enabled on the model (e.g., `thinking={"type": "enabled",
"budget_tokens": 5000}` for `ChatAnthropic`).

## Emit custom updates from tools

```python
from langgraph.config import get_stream_writer

def long_task(item: str) -> str:
    """Process an item."""
    writer = get_stream_writer()
    writer(f"Processing: {item}")
    # ... do work ...
    writer(f"Done: {item}")
    return "result"
```

Consume with `stream_mode="custom"`:

```python
for chunk in agent.stream(..., stream_mode="custom", version="v2"):
    if chunk["type"] == "custom":
        print(chunk["data"])
```

Note: `get_stream_writer` inside a tool means the tool cannot be called outside
a LangGraph execution context. Alternatively, access via `runtime.stream_writer`
in `ToolRuntime`.

## Stream tool calls and completed messages together

```python
for chunk in agent.stream(
    {"messages": [input_msg]},
    stream_mode=["messages", "updates"],
    version="v2",
):
    if chunk["type"] == "messages":
        token, metadata = chunk["data"]
        if isinstance(token, AIMessageChunk):
            # token.text for text, token.tool_call_chunks for partial tool calls
            print(token.text, end="")
    elif chunk["type"] == "updates":
        for source, update in chunk["data"].items():
            if source == "tools":
                last = update["messages"][-1]
                print(f"Tool result: {last.content_blocks}")
```

Use `token.chunk_position == "last"` to detect when a complete tool call has
been assembled during `"messages"` streaming.

## Human-in-the-loop interrupts during streaming

Interrupts appear in `"updates"` chunks as `source == "__interrupt__"`:

```python
interrupts = []
for chunk in agent.stream(..., stream_mode=["messages", "updates"], version="v2"):
    if chunk["type"] == "updates":
        for source, update in chunk["data"].items():
            if source == "__interrupt__":
                interrupts.extend(update)
```

Resume with `Command(resume=decisions)`:

```python
for chunk in agent.stream(
    Command(resume=decisions),
    config=config,
    stream_mode=["messages", "updates"],
    version="v2",
):
    ...
```

## Multi-agent streaming

Set `name="agent_name"` on each `create_agent` call. Use `subgraphs=True` in
`stream()`. Disambiguate by `metadata["lc_agent_name"]` in `"messages"` chunks.

## v2 invoke

```python
result = agent.invoke({"messages": [...]}, version="v2")
result.value       # dict with messages, structured_response, etc.
result.interrupts  # tuple of Interrupt objects (empty if none)
```

## Disable streaming for a model

```python
from langchain_openai import ChatOpenAI

model = ChatOpenAI(model="gpt-4o", streaming=False)
# or use disable_streaming=True (available on all BaseChatModel)
```
