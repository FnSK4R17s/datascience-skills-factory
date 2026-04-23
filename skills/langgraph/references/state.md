# State Reference

Source: `docs/graph-api.md`, `docs/use-graph-api.md`

## What state is

State is a shared data structure representing a snapshot of the graph at any point.
Every node receives the current state as input and returns partial updates — only
the keys it changed. Updates are merged via reducers.

## Schema options

### TypedDict (recommended)

```python
from typing_extensions import TypedDict

class State(TypedDict):
    messages: list
    topic: str
```

### Dataclass (for defaults)

```python
from dataclasses import dataclass, field

@dataclass
class State:
    messages: list = field(default_factory=list)
    topic: str = ""
```

### Pydantic BaseModel (for validation)

```python
from pydantic import BaseModel

class State(BaseModel):
    messages: list
    topic: str
```

Pydantic adds validation overhead and is incompatible with the higher-level
`create_agent` factory. Prefer TypedDict unless recursive validation is required.

## Input / output schemas

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

Nodes can write to any key in the full union of all schemas, even if that schema was
not passed to `StateGraph()` — as long as the schema class exists.

## Reducers

```python
from typing import Annotated
from operator import add

class State(TypedDict):
    counter: int                              # default: overwrite
    history: Annotated[list[str], add]        # accumulate
    tags: Annotated[set, lambda a, b: a | b]  # custom reducer
```

### Overwrite bypass

When you need to force an overwrite on a key that has a reducer:

```python
from langgraph.types import Overwrite

class State(TypedDict):
    data: Annotated[list, add]
    data_reset: Annotated[list, Overwrite]    # always overwrites
```

## Working with messages

### `add_messages` reducer

```python
from typing import Annotated
from langgraph.graph.message import add_messages

class State(TypedDict):
    messages: Annotated[list, add_messages]
```

Behaviour:
- New messages (no matching ID in existing list) → appended.
- Updated messages (matching ID) → replaces existing entry.
- Accepts both `HumanMessage(...)` objects and `{"role": "user", "content": "..."}` dicts.
- Use `state["messages"][-1].content` to access content (dot notation, not key).

### `MessagesState` shortcut

```python
from langgraph.graph import MessagesState

class State(MessagesState):     # inherits: messages: Annotated[list[AnyMessage], add_messages]
    summary: str                # add your own keys
```

### Deleting messages

```python
from langchain.messages import RemoveMessage
from langgraph.graph.message import REMOVE_ALL_MESSAGES

# Remove specific messages
return {"messages": [RemoveMessage(id=m.id) for m in messages[:2]]}

# Remove all messages
return {"messages": [RemoveMessage(id=REMOVE_ALL_MESSAGES)]}
```

## Private / internal state channels

Nodes that declare a private TypedDict (not passed to `StateGraph`) can still write
to its keys — they register as internal channels not visible in input/output:

```python
class PrivateState(TypedDict):
    scratch: str

def node_a(state: OverallState) -> PrivateState:
    return {"scratch": "temp value"}        # writes to private channel

def node_b(state: PrivateState) -> OutputState:
    return {"result": state["scratch"]}
```

## Checkpoint namespace

The `checkpoint_ns` field in `config["configurable"]` identifies which graph a
checkpoint belongs to:
- `""` — root graph
- `"node_name:uuid"` — subgraph at that node
- Nested: `"outer:uuid|inner:uuid"`

Access in a node: `config["configurable"]["checkpoint_ns"]`
