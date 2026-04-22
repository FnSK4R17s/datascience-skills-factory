# Graph API

StateGraph is the core primitive. Nodes are Python functions; edges are
routing rules. Compile before invoking.

## Minimal example

```python
from langgraph.graph import StateGraph, START, END
from typing_extensions import TypedDict

class State(TypedDict):
    value: str

def my_node(state: State) -> dict:
    return {"value": state["value"].upper()}

graph = (
    StateGraph(State)
    .add_node("my_node", my_node)
    .add_edge(START, "my_node")
    .add_edge("my_node", END)
    .compile()
)

result = graph.invoke({"value": "hello"})
```

## Nodes

A node is any callable: `fn(state) -> partial_state_dict`. It can also accept
`config: RunnableConfig` (second argument) and `runtime: Runtime[Context]`
(third argument, or as a named parameter).

```python
from langgraph.runtime import Runtime

def node_with_context(state: State, runtime: Runtime[MyContext]) -> dict:
    user_id = runtime.context.user_id
    return {"result": f"Hello {user_id}"}
```

Nodes return only the keys they changed — not the full state.

## Edges

```python
# Unconditional: always go A -> B
graph.add_edge("a", "b")

# Conditional: router_fn(state) -> node_name (or list of names)
graph.add_conditional_edges("a", router_fn)

# With explicit mapping of return values to node names
graph.add_conditional_edges("a", router_fn, {True: "b", False: "c"})

# Fan-out: return a list -> all run in parallel (same superstep)
graph.add_conditional_edges("a", lambda s: ["b", "c"])
```

Multiple outgoing edges from the same node run in parallel in the next superstep.

## Command — combine routing and state updates in one step

Return `Command` from a node to update state AND route simultaneously:

```python
from langgraph.types import Command
from typing import Literal

def my_node(state: State) -> Command[Literal["next_node"]]:
    return Command(
        update={"foo": "bar"},   # state update
        goto="next_node"         # routing
    )
```

Use `Command` when you need both. Use conditional edges when routing only.

`Command(goto=..., graph=Command.PARENT)` navigates from a subgraph node
to a node in the parent graph.

**Warning:** `Command(update=...)` as input to `invoke()` is wrong for
multi-turn conversations — pass a plain dict instead. `Command(resume=...)`
as invoke input is the only correct use (for resuming after an interrupt).

## Send — map-reduce fan-out with different state per branch

```python
from langgraph.types import Send

def fan_out(state: OverallState):
    # Each Send creates a separate branch with its own state
    return [Send("worker_node", {"item": item}) for item in state["items"]]

graph.add_conditional_edges("splitter", fan_out)
```

## Compile

```python
graph = builder.compile(
    checkpointer=checkpointer,   # required for persistence + interrupts
    store=store,                 # optional: cross-thread memory store
    interrupt_before=["node_a"], # optional: static breakpoints (debugging)
    interrupt_after=["node_b"],  # optional: static breakpoints (debugging)
)
```

Compile does basic structural validation (orphan nodes, missing edges).

## Runtime context

Pass side-channel data to nodes without putting it in state:

```python
from dataclasses import dataclass

@dataclass
class Context:
    user_id: str
    db_url: str

graph = StateGraph(State, context_schema=Context).compile(...)
graph.invoke(inputs, context={"user_id": "u1", "db_url": "..."})
```

## Recursion limit

Default is 1000 supersteps (since v1.0.6). Override at runtime:

```python
graph.invoke(inputs, config={"recursion_limit": 50})
```

Note: `recursion_limit` goes at the top level of config, not inside
`configurable`. Raises `GraphRecursionError` when exceeded.

Use `RemainingSteps` managed value to detect approaching limit inside nodes:

```python
from langgraph.managed import RemainingSteps
from typing import Annotated

class State(TypedDict):
    remaining_steps: RemainingSteps  # auto-populated by LangGraph
```

## Node caching

```python
from langgraph.cache.memory import InMemoryCache
from langgraph.types import CachePolicy

builder.add_node("expensive", fn, cache_policy=CachePolicy(ttl=60))
graph = builder.compile(cache=InMemoryCache())
```

Cached results are marked with `__metadata__: {cached: True}` in updates mode.

## Multiple schemas

Nodes can declare input and output schemas independently. A node can write
to any channel in the graph's union of schemas, even if its declared input
schema is narrower:

```python
StateGraph(OverallState, input_schema=InputState, output_schema=OutputState)
```

## Graph migrations with checkpointers

- Rename/remove nodes: safe for finished threads; risky for interrupted ones.
- Add/remove state keys: fully backwards and forwards compatible.
- Rename state keys: existing threads lose that key's saved value.
