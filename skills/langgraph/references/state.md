# State Reference

Source: `docs/graph-api.md`, `docs/use-graph-api.md`

## What state is

State is a shared data structure representing a snapshot of the graph at any point.
Every node receives the current state as input and returns partial updates — only
the keys it changed. Updates are merged via reducers. LangGraph checkpoints the full
state after every super-step.

## Schema options

### TypedDict (recommended)

```python
from typing_extensions import TypedDict

class State(TypedDict):
    messages: list
    topic: str
    count: int
```

Fastest option. No validation overhead. Use for most graphs.

### Dataclass (for defaults)

```python
from dataclasses import dataclass, field

@dataclass
class State:
    messages: list = field(default_factory=list)
    topic: str = ""
    count: int = 0
```

Use when you need default values without redefining `__init__`.

### Pydantic BaseModel (for validation)

```python
from pydantic import BaseModel, validator
from typing import List

class State(BaseModel):
    messages: List[str]
    topic: str
    count: int = 0

    @validator("count")
    def count_non_negative(cls, v):
        if v < 0:
            raise ValueError("count must be >= 0")
        return v
```

Pydantic adds validation overhead and is **incompatible** with the higher-level
`create_agent` factory. Prefer TypedDict unless recursive validation is required.

## Input / output schemas

Use separate schemas to control what the caller sees vs internal keys.

```python
class InputState(TypedDict):
    user_input: str

class OutputState(TypedDict):
    result: str

class OverallState(TypedDict):
    user_input: str
    result: str
    _internal: str           # not exposed externally

builder = StateGraph(OverallState, input_schema=InputState, output_schema=OutputState)
```

Key rule: nodes can write to any channel in the union of ALL declared schemas,
even if that schema was not passed to `StateGraph()` — as long as the schema class exists.

## Reducers

Without a reducer, each node write **overwrites** the previous value.

```python
from typing import Annotated
from operator import add

class State(TypedDict):
    counter: int                              # default: overwrite
    history: Annotated[list[str], add]        # accumulate — each write appends
    tags: Annotated[set, lambda a, b: a | b]  # custom reducer — union of sets
```

### Behavior walkthrough

```python
# State: {"counter": 0, "history": []}

# node_a returns: {"counter": 5, "history": ["step_a"]}
# After: {"counter": 5, "history": ["step_a"]}

# node_b returns: {"counter": 10, "history": ["step_b"]}
# After (with operator.add): {"counter": 10, "history": ["step_a", "step_b"]}
# After (no reducer): {"counter": 10, "history": ["step_b"]}   # "step_a" LOST
```

### Overwrite bypass

When you need to force an overwrite on a key that has a reducer:

```python
from langgraph.types import Overwrite

class State(TypedDict):
    data: Annotated[list, add]             # normally accumulates
    data_reset: Annotated[list, Overwrite]  # always overwrites even though annotated
```

## Working with messages

### `add_messages` reducer

`add_messages` is the recommended reducer for conversation history. It deduplicates
by message ID, enables in-place editing without duplication, and deserializes plain
dicts to LangChain `Message` objects.

```python
from typing import Annotated
from langgraph.graph.message import add_messages
from langchain.messages import AnyMessage

class State(TypedDict):
    messages: Annotated[list[AnyMessage], add_messages]
```

Both formats are accepted as input:
```python
# Object form
{"messages": [HumanMessage(content="hello")]}

# Dict form — deserialized automatically
{"messages": [{"type": "human", "content": "hello"}]}
```

Access message content with **dot notation** after deserialization:
```python
last_msg = state["messages"][-1]
print(last_msg.content)    # dot notation
print(last_msg.role)       # for ChatMessage subclasses
# NOT: last_msg["content"]  — messages are objects, not dicts
```

### `MessagesState` shortcut

```python
from langgraph.graph import MessagesState

class State(MessagesState):     # inherits: messages: Annotated[list[AnyMessage], add_messages]
    summary: str                # add your own keys freely
    documents: list[str]
```

### Deleting messages

```python
from langchain.messages import RemoveMessage
from langgraph.graph.message import REMOVE_ALL_MESSAGES

def prune_node(state: State):
    # Remove the two oldest messages
    to_delete = [RemoveMessage(id=m.id) for m in state["messages"][:2]]
    return {"messages": to_delete}

def reset_node(state: State):
    # Remove everything
    return {"messages": [RemoveMessage(id=REMOVE_ALL_MESSAGES)]}
```

When deleting, ensure the remaining message list is valid for your LLM provider:
- Most providers require history to start with a user/human message.
- Tool call messages must always be followed by their corresponding tool result.

## Private / internal state channels

Nodes that declare a private TypedDict (not passed to `StateGraph`) can still write
to its keys — they register as internal channels not visible in input/output.

```python
class PrivateState(TypedDict):
    scratch: str

class OverallState(TypedDict):
    result: str

def node_a(state: OverallState) -> PrivateState:
    return {"scratch": "temp value"}        # writes to private channel

def node_b(state: PrivateState) -> OverallState:
    return {"result": state["scratch"].upper()}

builder = StateGraph(OverallState)
builder.add_node("node_a", node_a)
builder.add_node("node_b", node_b)
builder.add_edge(START, "node_a")
builder.add_edge("node_a", "node_b")
builder.add_edge("node_b", END)

graph = builder.compile()
# Caller only sees OverallState; "scratch" is invisible externally
result = graph.invoke({"result": ""})
print(result["result"])   # "TEMP VALUE"
```

## Checkpoint namespace

The `checkpoint_ns` field in `config["configurable"]` identifies which graph a
checkpoint belongs to:
- `""` — root graph
- `"node_name:uuid"` — subgraph at that node
- Nested: `"outer:uuid|inner:uuid"`

Access in a node:
```python
from langchain_core.runnables import RunnableConfig

def my_node(state: State, config: RunnableConfig):
    ns = config["configurable"]["checkpoint_ns"]
    if ns == "":
        print("I'm in the root graph")
    else:
        print(f"I'm in subgraph: {ns}")
```
