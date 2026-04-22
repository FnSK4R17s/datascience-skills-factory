# Streaming

LangGraph graphs expose `.stream()` (sync) and `.astream()` (async) to yield
events as the graph executes. Pass `version="v2"` for a unified, type-safe
output format.

## Stream modes

| Mode | What it emits | When to use |
|------|---------------|-------------|
| `values` | Full state snapshot after each superstep | Debug — most verbose |
| `updates` | Only the changed keys from each node | Production default |
| `messages` | `(message_chunk, metadata)` tuples from LLM calls | Token streaming |
| `custom` | Arbitrary data from `get_stream_writer()` | Progress, custom events |
| `checkpoints` | Checkpoint events (same format as `get_state()`) | Audit, persistence |
| `tasks` | Task start/finish events with results and errors | Observability |
| `debug` | Everything — combines checkpoints + tasks + metadata | Deep debugging |

## v2 format (LangGraph >= 1.1)

Pass `version="v2"` to get a consistent `StreamPart` dict for every chunk,
regardless of mode or subgraph nesting:

```python
{"type": "updates" | "values" | "messages" | ..., "ns": (), "data": ...}
```

Without v2, the format changes based on combinations of modes and `subgraphs`:
single mode returns raw data, multiple modes return `(mode, data)` tuples,
subgraphs add a namespace prefix. Use v2 to avoid this.

## Common patterns

### Node updates (production default)

```python
for chunk in graph.stream(inputs, stream_mode="updates", version="v2"):
    if chunk["type"] == "updates":
        for node_name, state_update in chunk["data"].items():
            print(f"{node_name}: {state_update}")
```

### Token streaming from LLM calls

`messages` mode emits tokens even when the LLM is called with `.invoke()`
(not `.stream()`). LangGraph intercepts the underlying streaming:

```python
for chunk in graph.stream(inputs, stream_mode="messages", version="v2"):
    if chunk["type"] == "messages":
        msg_chunk, metadata = chunk["data"]
        if msg_chunk.content:
            print(msg_chunk.content, end="", flush=True)
```

Filter by node: `metadata["langgraph_node"] == "my_node"`
Filter by LLM tag: `metadata["tags"] == ["my_tag"]`

Exclude an LLM from the stream with the `nostream` tag:
```python
model = ChatAnthropic(...).with_config({"tags": ["nostream"]})
```

### Custom progress events

```python
from langgraph.config import get_stream_writer

def my_node(state):
    writer = get_stream_writer()
    writer({"progress": 0, "status": "starting"})
    # ... do work ...
    writer({"progress": 100, "status": "done"})
    return {"result": "..."}

for chunk in graph.stream(inputs, stream_mode="custom", version="v2"):
    if chunk["type"] == "custom":
        print(chunk["data"])
```

**Note:** `get_stream_writer()` uses contextvars and does not work in async
code on Python < 3.11. Use a `writer: StreamWriter` parameter instead:

```python
from langgraph.types import StreamWriter

async def my_node(state: State, writer: StreamWriter):
    writer({"status": "working"})
    return {"result": "..."}
```

### Multiple modes at once

```python
for chunk in graph.stream(inputs, stream_mode=["updates", "custom"], version="v2"):
    if chunk["type"] == "updates":
        ...
    elif chunk["type"] == "custom":
        ...
```

### Subgraph events

```python
for chunk in graph.stream(inputs, stream_mode="updates", subgraphs=True, version="v2"):
    print(chunk["ns"])    # () for root, ("node_name:task_id",) for subgraph
    print(chunk["data"])
```

### Async

```python
async for chunk in graph.astream(inputs, stream_mode="updates", version="v2"):
    if chunk["type"] == "updates":
        ...
```

## v2 invoke format

With `version="v2"`, `invoke()` returns a `GraphOutput` object:

```python
from langgraph.types import GraphOutput

result = graph.invoke(inputs, config=config, version="v2")
result.value       # your state dict (or Pydantic/dataclass instance)
result.interrupts  # tuple[Interrupt, ...], empty if none occurred
```

Dict-style access (`result["key"]`, `result["__interrupt__"]`) still works
but is deprecated. Migrate to `result.value` and `result.interrupts`.

## Detecting interrupts while streaming

With v2 and `stream_mode=["updates"]`, interrupt payloads appear in
`values` stream parts. For HITL interactive loops:

```python
async for chunk in graph.astream(
    initial_input,
    stream_mode=["messages", "updates"],
    subgraphs=True,
    config=config,
    version="v2",
):
    if chunk["type"] == "messages":
        msg, _ = chunk["data"]
        print(msg.content, end="")
    elif chunk["type"] == "updates" and "__interrupt__" in chunk["data"]:
        payload = chunk["data"]["__interrupt__"][0].value
        user_response = await get_user_input(payload)
        initial_input = Command(resume=user_response)
        break
```

## Python < 3.11 async caveat

Must explicitly pass `config` to async LLM calls:

```python
async def call_model(state, config):
    response = await model.ainvoke(messages, config)  # config required < 3.11
    return {"result": response.content}
```

## Streaming from non-LangChain LLMs

Use `stream_mode="custom"` + `get_stream_writer()` to forward any streaming
API's output:

```python
def call_arbitrary_model(state):
    writer = get_stream_writer()
    for chunk in my_streaming_api(state["topic"]):
        writer({"token": chunk})
    return {"result": "done"}
```
