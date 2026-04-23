# State

Source: `docs/graph-api.md`, `docs/thinking-in-langgraph.md`

## Schema options

| Option | When to use |
|--------|-------------|
| `TypedDict` | Standard choice; most performant |
| `dataclass` | When you need default field values |
| `Pydantic BaseModel` | When you need recursive runtime validation (slower) |

Note: `create_agent` (LangChain higher-level) does not support Pydantic state.
Source: `docs/graph-api.md`.

## Reducers

Each state key has a reducer that controls how updates from nodes are merged
into the existing state.

**Default (no annotation)** — last write wins (overwrites):

```python
class State(TypedDict):
    foo: int      # overwritten on each update
    bar: list     # overwritten (not appended)
```

**Custom reducer via `Annotated`** — apply a function to merge:

```python
from typing import Annotated
from operator import add

class State(TypedDict):
    foo: int
    bar: Annotated[list[str], add]   # appended with operator.add
```

`Overwrite` type bypasses any reducer and forces a direct replace for a specific
update. Source: `docs/graph-api.md`.

## Messages and MessagesState

For chat agents, use `add_messages` as the reducer. It handles:
- Appending new messages.
- Deduplication by message ID (so human edits via `update_state` don't duplicate).
- Deserializing plain dicts to LangChain `Message` objects.

```python
from langgraph.graph import MessagesState  # prebuilt
# MessagesState has: messages: Annotated[list[AnyMessage], add_messages]

# Extend it:
class State(MessagesState):
    documents: list[str]

# Or define manually:
from langgraph.graph.message import add_messages
from typing import Annotated
from langchain.messages import AnyMessage

class State(TypedDict):
    messages: Annotated[list[AnyMessage], add_messages]
```

`add_messages` also accepts plain dicts:
```python
{"messages": [{"type": "human", "content": "hello"}]}
```
Source: `docs/graph-api.md`.

## State design principles

- Store **raw data**, not formatted text. Format inside nodes on demand.
- A key that can be derived from other keys should not be in state.
- Keys that multiple nodes need to read should live in state.
- Reducers are per-key; different keys can have different merge strategies.

Source: `docs/thinking-in-langgraph.md`.

## Private / internal state channels

Nodes can write to channels defined in any schema registered with the graph,
even if that schema is not the primary `OverallState`. Define a `PrivateState`
TypedDict; nodes that read/write it declare it as their input/output type. The
graph gains access to the channels automatically when those node functions are
added. Source: `docs/graph-api.md`.
