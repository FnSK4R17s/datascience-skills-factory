# Streaming

Source: `docs/streaming.md`

## Methods

`graph.stream(input, ...)` (sync) and `graph.astream(input, ...)` (async) yield
streamed output as iterators. Pass one or more stream modes to control content.

## v2 output format (recommended)

Pass `version="v2"` for a **unified `StreamPart` format** regardless of mode
count or subgraph settings. Available from LangGraph >= 1.1.

Every chunk is:
```python
{
    "type": "values" | "updates" | "messages" | "custom" | "checkpoints" | "tasks" | "debug",
    "ns": (),        # namespace tuple; populated for subgraph events
    "data": ...      # payload type varies by mode
}
```

Filter by `chunk["type"]` for full type narrowing.

## Stream modes

| Mode | Data | Typical use |
|------|------|-------------|
| `updates` | `{node_name: state_delta}` per step | See what each node changed |
| `values` | Full state dict after each step | Inspect complete state evolution |
| `messages` | `(message_chunk, metadata)` tuples | Stream LLM tokens to a UI |
| `custom` | Arbitrary dict from `get_stream_writer()` | Progress, tool events, non-LangChain LLMs |
| `checkpoints` | Same format as `get_state()` | Observe checkpoint writes |
| `tasks` | Task start/finish events | Debug parallelism; requires checkpointer |
| `debug` | Combines `checkpoints` + `tasks` + extra metadata | Maximum visibility |

Source: `docs/streaming.md`.

## Usage examples

### updates (most common)
```python
for chunk in graph.stream(inputs, stream_mode="updates", version="v2"):
    if chunk["type"] == "updates":
        for node_name, delta in chunk["data"].items():
            print(f"{node_name}: {delta}")
```

### messages (LLM tokens)
```python
for chunk in graph.stream(inputs, stream_mode="messages", version="v2"):
    if chunk["type"] == "messages":
        msg, metadata = chunk["data"]
        if msg.content:
            print(msg.content, end="", flush=True)
```

Filter tokens by node or model tag via `metadata["langgraph_node"]` or
`metadata["tags"]`. Source: `docs/streaming.md`.

### custom data
```python
from langgraph.config import get_stream_writer

def my_node(state: State):
    writer = get_stream_writer()
    writer({"status": "starting step 1"})
    ...

for chunk in graph.stream(inputs, stream_mode="custom", version="v2"):
    if chunk["type"] == "custom":
        print(chunk["data"]["status"])
```

`get_stream_writer()` works in nodes and tools. In async code on Python < 3.11,
add a `writer: StreamWriter` parameter to the node instead. Source: `docs/streaming.md`.

### Multiple modes at once
```python
for chunk in graph.stream(inputs, stream_mode=["updates", "custom"], version="v2"):
    if chunk["type"] == "updates":
        ...
    elif chunk["type"] == "custom":
        ...
```

### Subgraph output
```python
for chunk in graph.stream(inputs, subgraphs=True, stream_mode="updates", version="v2"):
    # chunk["ns"] is () for root, ("node_name:uuid",) for subgraph
    if chunk["ns"]:
        print(f"Subgraph {chunk['ns']}: {chunk['data']}")
```

## Omit model tokens

Tag a model call with `"nostream"` to exclude its tokens from `messages` mode
(the call still runs and produces output):

```python
internal_model = ChatAnthropic(...).with_config({"tags": ["nostream"]})
```

Source: `docs/streaming.md`.

## v2 invoke format

`invoke(..., version="v2")` returns `GraphOutput`:
```python
result = graph.invoke(inputs, config=config, version="v2")
result.value       # the output state / return value
result.interrupts  # tuple[Interrupt, ...]; empty if none occurred
```

Dict-style access (`result["key"]`) still works but is deprecated in v2.
Source: `docs/streaming.md`.

## v1 vs v2 format comparison

| Scenario | v1 (default) | v2 (`version="v2"`) |
|----------|-------------|---------------------|
| Single stream mode | Raw data dict | `StreamPart` dict |
| Multiple stream modes | `(mode, data)` tuples | Same `StreamPart`, filter on `type` |
| Subgraph streaming | `(namespace, data)` tuples | Same `StreamPart`, check `ns` |
| `invoke()` return type | Plain dict | `GraphOutput` with `.value` and `.interrupts` |

## Python < 3.11 async

Pass `RunnableConfig` explicitly to `ainvoke()` calls for messages mode to work.
Use `writer: StreamWriter` parameter instead of `get_stream_writer()` for
custom mode. Source: `docs/streaming.md`.
