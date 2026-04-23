# Graph API Reference

Source: `docs/graph-api.md`, `docs/use-graph-api.md`, `docs/thinking-in-langgraph.md`

## StateGraph

```python
from langgraph.graph import StateGraph, START, END
builder = StateGraph(State)
# Optional: separate I/O schemas
builder = StateGraph(OverallState, input_schema=InputState, output_schema=OutputState)
builder.add_node("my_node", fn)
builder.add_edge(START, "my_node")
builder.add_edge("my_node", END)
graph = builder.compile()             # MUST compile; validates structure
```

`compile()` accepts: `checkpointer`, `store`, `interrupt_before=["node_a"]`,
`interrupt_after=["node_b"]`, `cache`. All optional.

## State schemas

Three supported forms:
- `TypedDict` — fastest, no validation overhead (recommended default)
- `dataclass` — supports field default values
- Pydantic `BaseModel` — recursive validation, slower

**Multiple schemas:** A node can write to any channel in the union of all schemas
defined for the graph—even those not in its declared input schema. Private schemas
(not passed to `StateGraph()`) still register their keys as channels when a node
uses them.

## Reducers

Reducers control how node output merges into state. Default is overwrite.

```python
from typing import Annotated
from operator import add
from typing_extensions import TypedDict

class State(TypedDict):
    foo: int                          # overwrite on each node update
    bar: Annotated[list[str], add]    # append; never overwrites
```

Use `langgraph.types.Overwrite` to force an overwrite on a key that has a reducer.

### `add_messages` and `MessagesState`

```python
from langgraph.graph import MessagesState
from langgraph.graph.message import add_messages

class State(MessagesState):           # single 'messages' key + add_messages reducer
    documents: list[str]
```

`add_messages` deduplicates by message ID (enabling human edits without duplicates),
deserializes plain dicts to LangChain message objects, and appends genuinely new
messages. Pass `RemoveMessage(id=m.id)` or `REMOVE_ALL_MESSAGES` to delete messages.

## Nodes

Nodes are plain Python functions (sync or async).

```python
from langgraph.runtime import Runtime
from dataclasses import dataclass

@dataclass
class Context:
    user_id: str

def plain_node(state: State):
    return {"foo": "updated"}

def node_with_runtime(state: State, runtime: Runtime[Context]):
    uid = runtime.context.user_id
    store = runtime.store
    step = runtime.execution_info.thread_id
    return {"result": uid}
```

LangGraph injects `state`, `config` (RunnableConfig), and `runtime` (Runtime) based
on declared parameter names and types. Runtime carries: `context`, `store`,
`stream_writer`, `execution_info`, `server_info`.

Node name defaults to the function name when added without an explicit label.

### Node caching

```python
from langgraph.cache.memory import InMemoryCache
from langgraph.types import CachePolicy

builder.add_node("expensive", fn, cache_policy=CachePolicy(ttl=60))  # 60s TTL
graph = builder.compile(cache=InMemoryCache())
# Second call with same input returns {'cached': True} in metadata
```

## Edges

```python
# Always go A → B
builder.add_edge("a", "b")

# Conditional routing
def route(state) -> Literal["b", "c"]:
    return "b" if state["ok"] else "c"
builder.add_conditional_edges("a", route)
builder.add_conditional_edges("a", route, {True: "b", False: "c"})   # map output
```

A node with multiple outgoing edges runs all destination nodes in parallel (same
super-step). Entry points use `START` as the source.

## `Send` — map-reduce

```python
from langgraph.types import Send

def fan_out(state):
    return [Send("process", {"item": x}) for x in state["items"]]

builder.add_conditional_edges("collect", fan_out)
```

`Send(node_name, state_dict)` dispatches independent state copies to the same node
in parallel. The number of copies can vary at runtime — classic map-reduce.

## `Command`

Combines state update + routing in one return value from a node.

```python
from langgraph.types import Command

def my_node(state) -> Command[Literal["next"]]:
    return Command(update={"foo": "bar"}, goto="next")

# Navigate from subgraph to parent graph
def subgraph_node(state) -> Command:
    return Command(update={...}, goto="parent_node", graph=Command.PARENT)
```

**Warning:** `Command` only *adds* a dynamic edge — static `add_edge` edges still
execute. To suppress a static edge, remove it and use only `Command`.

**As invoke input:** `Command(resume=...)` is the only valid form. Never pass
`Command(update=...)` as invoke input to continue a multi-turn conversation; pass
a plain dict instead (which re-runs from `__start__`, not the last checkpoint).

## Runtime context

```python
from dataclasses import dataclass

@dataclass
class Ctx:
    db_pool: object

builder = StateGraph(State, context_schema=Ctx)
graph.invoke(inputs, context={"db_pool": pool})
```

Context is per-invocation dependency injection. Not persisted. Accessed via
`runtime.context` inside nodes. Passed via the `context=` kwarg to `invoke`/`stream`.

## Recursion limit

```python
graph.invoke(inputs, config={"recursion_limit": 200})   # top-level key, NOT in configurable
```

Default 1000. Raises `GraphRecursionError` when exceeded. For proactive handling:

```python
from langgraph.managed import RemainingSteps

class State(TypedDict):
    remaining: RemainingSteps         # auto-populated; read in any node
```

Step counter also in `config["metadata"]["langgraph_step"]` (and `langgraph_node`,
`langgraph_triggers`, `langgraph_path`, `langgraph_checkpoint_ns`).

## Graph migrations

- Add/remove state keys: fully compatible with existing threads.
- Rename keys: existing thread values are lost for renamed key.
- Rename/remove nodes: only safe for threads NOT interrupted at that node.
- Topology changes: safe for completed threads; restricted for interrupted threads.
