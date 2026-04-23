# Streaming Reference

Source: `docs/streaming.md`

## Methods

```python
graph.stream(inputs, config, stream_mode=..., version="v2")    # sync
graph.astream(inputs, config, stream_mode=..., version="v2")   # async
graph.invoke(inputs, config, version="v2")                     # returns GraphOutput
```

## v2 format (LangGraph >= 1.1, recommended)

Pass `version="v2"` to get a unified `StreamPart` dict for every chunk:

```python
{
    "type": "values" | "updates" | "messages" | "custom" | "checkpoints" | "tasks" | "debug",
    "ns": (),       # namespace tuple; populated for subgraph events
    "data": ...,    # payload varies by type
}
```

Use `chunk["type"]` to narrow and get typed `data`. Import types from `langgraph.types`:
`ValuesStreamPart`, `UpdatesStreamPart`, `MessagesStreamPart`, `CustomStreamPart`,
`CheckpointStreamPart`, `TasksStreamPart`, `DebugStreamPart`.

v1 (default, no `version="v2"`): format changes based on how many modes and whether
`subgraphs=True`. Single mode → raw data. Multiple modes → `(mode, data)` tuples.
Subgraphs → `(namespace, data)` tuples. Use v2 for new code.

## Stream modes

| Mode | Data shape | Use for |
|------|-----------|---------|
| `values` | Full state snapshot after each step | Know current graph state |
| `updates` | Dict of `{node_name: updates}` per step | Know what each node changed |
| `messages` | `(message_chunk, metadata)` from LLM calls | Token-by-token streaming |
| `custom` | Arbitrary data from `get_stream_writer()` | Progress updates, any LLM |
| `checkpoints` | Same format as `get_state()`; needs checkpointer | Checkpoint audit |
| `tasks` | Task start/finish events; needs checkpointer | Node-level observability |
| `debug` | All info (combines checkpoints + tasks + metadata) | Deep debugging |

Pass multiple modes as a list; all produce `StreamPart` dicts in v2.

## Example: multiple modes

```python
for chunk in graph.stream(inputs, stream_mode=["updates", "messages", "custom"],
                           version="v2"):
    if chunk["type"] == "updates":
        for node, state in chunk["data"].items():
            print(f"{node}: {state}")
    elif chunk["type"] == "messages":
        msg, meta = chunk["data"]
        print(msg.content, end="")
    elif chunk["type"] == "custom":
        print(f"progress: {chunk['data']}")
```

## Custom data with `get_stream_writer`

```python
from langgraph.config import get_stream_writer

def my_node(state):
    writer = get_stream_writer()
    writer({"status": "processing", "pct": 50})
    return {"result": "done"}
```

**Python < 3.11 caveat:** `get_stream_writer()` does not work in async nodes because
asyncio tasks before 3.11 lack context propagation. Instead, declare a `writer`
parameter and LangGraph injects it:

```python
from langgraph.types import StreamWriter

async def my_node(state, writer: StreamWriter):
    writer({"status": "processing"})
    return {"result": "done"}
```

## LLM token streaming (`messages` mode)

```python
for chunk in graph.stream(inputs, stream_mode="messages", version="v2"):
    if chunk["type"] == "messages":
        msg, meta = chunk["data"]
        # Filter by node
        if meta["langgraph_node"] == "call_model" and msg.content:
            print(msg.content, end="")
        # Filter by tag
        if "joke" in meta.get("tags", []) and msg.content:
            print(msg.content, end="")
```

Use `model.with_config({"tags": ["nostream"]})` to suppress tokens from a specific
model invocation in the `messages` stream.

## Any LLM (custom streaming)

```python
def call_custom_llm(state):
    writer = get_stream_writer()
    for token in my_custom_client.stream(...):
        writer({"token": token})
    return {"result": "..."}

# Stream with custom mode
for chunk in graph.stream(inputs, stream_mode="custom", version="v2"):
    if chunk["type"] == "custom":
        print(chunk["data"]["token"], end="")
```

## Subgraph streaming

```python
for chunk in graph.stream(inputs, subgraphs=True, stream_mode="updates", version="v2"):
    print(chunk["type"])   # "updates"
    print(chunk["ns"])     # () for root; ("node_name:uuid",) for subgraph
    print(chunk["data"])
```

## v2 invoke return type

```python
from langgraph.types import GraphOutput

result = graph.invoke(inputs, version="v2")
assert isinstance(result, GraphOutput)
result.value        # your output (dict, Pydantic model, dataclass)
result.interrupts   # tuple[Interrupt, ...]; empty if no interrupts
```

With Pydantic/dataclass state + v2 `values` mode, `chunk["data"]` is coerced to the
correct model instance automatically.

## Disable streaming for specific models

```python
model = init_chat_model("o1-preview", streaming=False)
# Fallback for models that don't support 'streaming' param:
model = ChatOpenAI(model="o1-preview", disable_streaming=True)
```

## Python < 3.11 async LLM streaming

Must pass `config` explicitly to `ainvoke()`:

```python
async def call_model(state, config):
    response = await model.ainvoke(messages, config)  # config propagates callbacks
    return {"messages": [response]}
```
