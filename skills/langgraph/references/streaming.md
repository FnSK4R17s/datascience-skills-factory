# Streaming Reference

Source: `docs/streaming.md`

## Methods

```python
graph.stream(inputs, config, stream_mode=..., version="v2")    # sync
graph.astream(inputs, config, stream_mode=..., version="v2")   # async
graph.invoke(inputs, config, version="v2")                     # returns GraphOutput
```

## v2 format (LangGraph >= 1.1, recommended)

Pass `version="v2"` to get a unified `StreamPart` dict for every chunk regardless
of how many modes you use or whether subgraphs are enabled:

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
Subgraphs → `(namespace, data)` tuples. Use v2 for all new code.

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

## Graph state streaming (`values` and `updates`)

Full working example. Source: `docs/streaming.md`.

```python
from typing import TypedDict
from langgraph.graph import StateGraph, START, END

class State(TypedDict):
    topic: str
    joke: str

def refine_topic(state: State):
    return {"topic": state["topic"] + " and cats"}

def generate_joke(state: State):
    return {"joke": f"This is a joke about {state['topic']}"}

graph = (
    StateGraph(State)
    .add_node(refine_topic)
    .add_node(generate_joke)
    .add_edge(START, "refine_topic")
    .add_edge("refine_topic", "generate_joke")
    .add_edge("generate_joke", END)
    .compile()
)

# updates mode — only what changed per node
for chunk in graph.stream({"topic": "ice cream"}, stream_mode="updates", version="v2"):
    if chunk["type"] == "updates":
        for node_name, state in chunk["data"].items():
            print(f"Node `{node_name}` updated: {state}")
# Node `refine_topic` updated: {'topic': 'ice cream and cats'}
# Node `generate_joke` updated: {'joke': 'This is a joke about ice cream and cats'}

# values mode — full state after each step
for chunk in graph.stream({"topic": "ice cream"}, stream_mode="values", version="v2"):
    if chunk["type"] == "values":
        print(f"topic: {chunk['data']['topic']}, joke: {chunk['data']['joke']}")
# topic: ice cream, joke:
# topic: ice cream and cats, joke:
# topic: ice cream and cats, joke: This is a joke about ice cream and cats
```

## LLM token streaming (`messages` mode)

`messages` mode streams LLM output token-by-token. Works even with `.invoke()`
(not just `.stream()`). Source: `docs/streaming.md`.

```python
from dataclasses import dataclass
from langchain.chat_models import init_chat_model
from langgraph.graph import StateGraph, START

@dataclass
class MyState:
    topic: str
    joke: str = ""

model = init_chat_model(model="gpt-5.4-mini")

def call_model(state: MyState):
    model_response = model.invoke(
        [{"role": "user", "content": f"Generate a joke about {state.topic}"}]
    )
    return {"joke": model_response.content}

graph = (
    StateGraph(MyState)
    .add_node(call_model)
    .add_edge(START, "call_model")
    .compile()
)

for chunk in graph.stream({"topic": "ice cream"}, stream_mode="messages", version="v2"):
    if chunk["type"] == "messages":
        message_chunk, metadata = chunk["data"]
        if message_chunk.content:
            print(message_chunk.content, end="|", flush=True)
```

### Filter by node

```python
for chunk in graph.stream(inputs, stream_mode="messages", version="v2"):
    if chunk["type"] == "messages":
        msg, metadata = chunk["data"]
        if msg.content and metadata["langgraph_node"] == "call_model":
            print(msg.content, end="", flush=True)
```

### Filter by tag

```python
from langchain.chat_models import init_chat_model

# Two models with different tags
joke_model = init_chat_model(model="gpt-5.4-mini", tags=["joke"])
poem_model = init_chat_model(model="gpt-5.4-mini", tags=["poem"])

# Stream only the joke tokens
async for chunk in graph.astream({"topic": "cats"}, stream_mode="messages", version="v2"):
    if chunk["type"] == "messages":
        msg, metadata = chunk["data"]
        if metadata["tags"] == ["joke"]:
            print(msg.content, end="|", flush=True)
```

### Suppress tokens from specific models

Use `"nostream"` tag to exclude tokens from the stream while still running the LLM:

```python
from langchain_anthropic import ChatAnthropic

stream_model = ChatAnthropic(model_name="claude-haiku-4-5-20251001")
internal_model = ChatAnthropic(model_name="claude-haiku-4-5-20251001").with_config(
    {"tags": ["nostream"]}   # tokens hidden from messages stream
)
```

## Custom data with `get_stream_writer`

Source: `docs/streaming.md`.

```python
from langgraph.config import get_stream_writer

def my_node(state):
    writer = get_stream_writer()
    writer({"status": "processing", "pct": 50})
    # ... do work ...
    writer({"status": "done", "pct": 100})
    return {"result": "done"}

# Full example with custom mode
from typing import TypedDict
from langgraph.graph import StateGraph, START, END

class State(TypedDict):
    topic: str
    joke: str

def generate_joke(state: State):
    writer = get_stream_writer()
    writer({"status": "thinking of a joke..."})
    return {"joke": f"Why did the {state['topic']} go to school? To get a sundae education!"}

graph = (
    StateGraph(State)
    .add_node(generate_joke)
    .add_edge(START, "generate_joke")
    .add_edge("generate_joke", END)
    .compile()
)

for chunk in graph.stream({"topic": "ice cream"}, stream_mode=["updates", "custom"], version="v2"):
    if chunk["type"] == "updates":
        for node_name, state in chunk["data"].items():
            print(f"Node {node_name} updated: {state}")
    elif chunk["type"] == "custom":
        print(f"Status: {chunk['data']['status']}")
# Status: thinking of a joke...
# Node generate_joke updated: {'joke': 'Why did the ice cream go to school? To get a sundae education!'}
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

## Custom streaming with any LLM

Use `stream_mode="custom"` with `get_stream_writer()` to stream from any API,
even if it doesn't implement the LangChain interface.

```python
from langgraph.config import get_stream_writer

def call_arbitrary_model(state):
    writer = get_stream_writer()
    for chunk in your_custom_streaming_client(state["topic"]):
        writer({"custom_llm_chunk": chunk})
    return {"result": "completed"}

for chunk in graph.stream(inputs, stream_mode="custom", version="v2"):
    if chunk["type"] == "custom":
        print(chunk["data"]["custom_llm_chunk"], end="", flush=True)
```

Extended example with raw OpenAI client:

```python
import json
import operator
from typing import TypedDict
from typing_extensions import Annotated
from langgraph.graph import StateGraph, START
from openai import AsyncOpenAI

openai_client = AsyncOpenAI()

async def stream_tokens(model_name: str, messages: list[dict]):
    response = await openai_client.chat.completions.create(
        messages=messages, model=model_name, stream=True
    )
    async for chunk in response:
        delta = chunk.choices[0].delta
        if delta.content:
            yield {"role": "assistant", "content": delta.content}

async def get_items(place: str) -> str:
    """List items one might find in a place."""
    writer = get_stream_writer()
    response = ""
    async for msg_chunk in stream_tokens(
        "gpt-5.4-mini",
        [{"role": "user", "content": f"List 3 items in {place}, with brief descriptions."}]
    ):
        response += msg_chunk["content"]
        writer(msg_chunk)
    return response

class State(TypedDict):
    messages: Annotated[list[dict], operator.add]

async def call_tool(state: State):
    ai_message = state["messages"][-1]
    tool_call = ai_message["tool_calls"][-1]
    function_arguments = json.loads(tool_call["function"]["arguments"])
    function_response = await get_items(**function_arguments)
    return {"messages": [{"role": "tool", "content": function_response}]}
```

## Subgraph streaming

```python
for chunk in graph.stream(inputs, subgraphs=True, stream_mode="updates", version="v2"):
    if chunk["ns"]:   # non-empty namespace = subgraph event
        print(f"Subgraph {chunk['ns']}: {chunk['data']}")
    else:
        print(f"Root: {chunk['data']}")
```

Full example showing namespace values:

```python
# () — root graph
# ('node_2:dfddc4ba-c3c5-6887-5012-a243b5b377c2',) — subgraph at node_2
# ('outer:uuid|inner:uuid',) — nested subgraph
```

## Multiple modes at once

```python
for chunk in graph.stream(
    inputs,
    stream_mode=["updates", "messages", "custom"],
    version="v2"
):
    if chunk["type"] == "updates":
        for node, state in chunk["data"].items():
            print(f"{node}: {state}")
    elif chunk["type"] == "messages":
        msg, meta = chunk["data"]
        print(msg.content, end="")
    elif chunk["type"] == "custom":
        print(f"progress: {chunk['data']}")
```

## Checkpoints and tasks modes

```python
from langgraph.checkpoint.memory import MemorySaver

graph = (
    StateGraph(State)
    # ... nodes and edges ...
    .compile(checkpointer=MemorySaver())
)
config = {"configurable": {"thread_id": "1"}}

# Checkpoint events (one per super-step)
for chunk in graph.stream(inputs, config=config, stream_mode="checkpoints", version="v2"):
    if chunk["type"] == "checkpoints":
        print(chunk["data"])

# Task start/finish events
for chunk in graph.stream(inputs, config=config, stream_mode="tasks", version="v2"):
    if chunk["type"] == "tasks":
        print(chunk["data"])

# Debug — everything
for chunk in graph.stream(inputs, config=config, stream_mode="debug", version="v2"):
    if chunk["type"] == "debug":
        print(chunk["data"])
```

## v2 invoke return type

```python
from langgraph.types import GraphOutput

result = graph.invoke(inputs, version="v2")
assert isinstance(result, GraphOutput)
result.value        # your output (dict, Pydantic model, dataclass)
result.interrupts   # tuple[Interrupt, ...]; empty if no interrupts

# Check and handle interrupt
if result.interrupts:
    payload = result.interrupts[0].value
    resumed = graph.invoke(Command(resume="my answer"), config, version="v2")
```

Dict-style access (`result["key"]`, `result["__interrupt__"]`) still works for
backwards compatibility but is deprecated. Migrate to `.value` and `.interrupts`.

## Migration guide from v1 to v2

| Scenario | v1 (default) | v2 (`version="v2"`) |
|---|---|---|
| Single stream mode | Raw data (dict) | `StreamPart` dict with `type`, `ns`, `data` |
| Multiple stream modes | `(mode, data)` tuples | Same `StreamPart` dict, filter on `chunk["type"]` |
| Subgraph streaming | `(namespace, data)` tuples | Same `StreamPart` dict, check `chunk["ns"]` |
| `invoke()` return type | Plain dict (state) | `GraphOutput` with `.value` and `.interrupts` |
| Interrupt location (stream) | `__interrupt__` key in state dict | `interrupts` field on `values` stream parts |
| Interrupt location (invoke) | `__interrupt__` key in result dict | `.interrupts` on `GraphOutput` |
| Pydantic/dataclass output | Returns plain dict | Coerces to model/dataclass instance automatically |

## Disable streaming for specific models

```python
from langchain.chat_models import init_chat_model

model = init_chat_model("claude-sonnet-4-6", streaming=False)

# Fallback for models that don't support 'streaming' param
from langchain_openai import ChatOpenAI
model = ChatOpenAI(model="o1-preview", disable_streaming=True)
```

## Python < 3.11 async LLM streaming

Must pass `config` explicitly to `ainvoke()`:

```python
async def call_model(state, config):
    response = await model.ainvoke(messages, config)  # config propagates callbacks
    return {"messages": [response]}
```

Without passing `config`, callbacks (and thus streaming) are not propagated in
async context on Python < 3.11.
