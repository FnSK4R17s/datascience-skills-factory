# State

State is the shared data structure passed between nodes. Every node receives
the full state and returns a partial update — only the keys it changed.

## Schema options

```python
from typing_extensions import TypedDict

# Preferred: TypedDict (fastest, no validation overhead)
class State(TypedDict):
    query: str
    results: list[str]
    count: int

# Pydantic: recursive validation, but slower
from pydantic import BaseModel
class State(BaseModel):
    query: str
    results: list[str] = []

# dataclass: useful when you want default values in TypedDict-style
from dataclasses import dataclass, field
@dataclass
class State:
    query: str
    results: list[str] = field(default_factory=list)
```

Note: `create_agent` (langchain, not langgraph) does not support Pydantic state.

## Reducers — how updates are merged

By default, a node's returned value **overwrites** the existing key.
Add a reducer to accumulate instead:

```python
from typing import Annotated
from operator import add

class State(TypedDict):
    counter: int              # overwrite on each update
    items: Annotated[list[str], add]  # accumulate: lists concatenated
```

The reducer function is `fn(existing_value, new_value) -> merged_value`.

### Built-in: `add_messages`

The most common reducer. Handles append and in-place update (by message ID):

```python
from langgraph.graph.message import add_messages
from langchain.messages import AnyMessage

class State(TypedDict):
    messages: Annotated[list[AnyMessage], add_messages]
```

`add_messages` also deserialises dict-format messages into LangChain objects:

```python
graph.invoke({"messages": [{"type": "human", "content": "Hello"}]})
# and
graph.invoke({"messages": [HumanMessage(content="Hello")]})
# both work
```

### MessagesState shortcut

Pre-built state with a single `messages` key + `add_messages` reducer:

```python
from langgraph.graph import MessagesState

# Extend it to add more fields:
class State(MessagesState):
    documents: list[str]
    user_id: str
```

### Overwrite bypass

Force an overwrite even on a reducer-annotated key:

```python
from langgraph.types import Overwrite
from typing import Annotated

class State(TypedDict):
    messages: Annotated[list[AnyMessage], add_messages]
    # Overwrite lets a node replace the whole list, ignoring add_messages
    last_reset: Annotated[list[AnyMessage], Overwrite]
```

## Channels and private state

Every key in the state is a "channel". Nodes can write to any channel that
exists in the graph's union of schemas, even if that key is not in the
node's declared input schema.

Private state: define a separate TypedDict for node-internal communication.
The keys only exist while those nodes are active and are not exposed in the
graph's I/O schemas:

```python
class PrivateState(TypedDict):
    intermediate_result: str

def node_a(state: InputState) -> PrivateState:
    return {"intermediate_result": "computed"}

def node_b(state: PrivateState) -> OutputState:
    return {"final": state["intermediate_result"]}
```

## State inspection at runtime

```python
config = {"configurable": {"thread_id": "1"}}
snapshot = graph.get_state(config)

snapshot.values        # current state dict
snapshot.next          # tuple of node names to run next; () = graph done
snapshot.metadata      # step counter, writes, source ("loop" / "update")
snapshot.created_at    # ISO timestamp
snapshot.parent_config # config of previous checkpoint
snapshot.tasks         # pending PregelTask objects (errors, interrupts)
```

## Updating state externally

```python
# Creates a new checkpoint with the update applied through reducers
graph.update_state(config, {"messages": [HumanMessage("correction")]})

# Treat the update as if it came from a specific node (affects next-node logic)
graph.update_state(config, {"messages": [...]}, as_node="my_node")
```

## RemainingSteps managed value

A special channel populated automatically by LangGraph with the number of
supersteps remaining before the recursion limit is hit:

```python
from langgraph.managed import RemainingSteps
from typing import Annotated

class State(TypedDict):
    remaining_steps: RemainingSteps  # do not set this yourself
```

Read it inside a node to implement graceful degradation before hitting
`GraphRecursionError`.
