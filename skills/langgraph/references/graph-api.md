# Graph API

Source: `docs/graph-api.md`, `docs/quickstart.md`, `docs/thinking-in-langgraph.md`

## Core model

Graphs execute in discrete **super-steps**. All nodes scheduled for a step run
(potentially in parallel); a checkpoint is written at the boundary. The graph
terminates when all nodes are inactive and no messages are in transit.

Three components:
1. **State** — shared data structure, a TypedDict or Pydantic model.
2. **Nodes** — Python functions that receive state and return a dict of updates.
3. **Edges** — fixed or conditional routes between nodes.

## StateGraph lifecycle

```python
from langgraph.graph import StateGraph, START, END

builder = StateGraph(MyState)
builder.add_node("node_a", node_a_fn)
builder.add_edge(START, "node_a")
builder.add_edge("node_a", END)
graph = builder.compile()          # MUST compile before use
```

`compile()` validates structure (no orphan nodes) and is where you attach
checkpointers and breakpoints. Source: `docs/graph-api.md`.

## Nodes

A node is any Python function (sync or async):

```python
def my_node(state: State) -> dict:
    return {"key": "value"}  # partial update — only changed keys required
```

Optional second/third parameters injected by LangGraph at runtime:
- `config: RunnableConfig` — thread_id, tags, tracing metadata.
- `runtime: Runtime[ContextSchema]` — context, store, stream_writer, execution_info.

When `add_node` is called without a name, the function name becomes the node name.

### Node caching

Nodes can cache results by input. Attach `cache_policy=CachePolicy(ttl=N)` when
adding the node and pass `cache=InMemoryCache()` (or another implementation) to
`compile()`. Cached hits are marked `__metadata__: {"cached": True}` in stream
output. Source: `docs/graph-api.md`.

## Edges

| Method | Behaviour |
|--------|-----------|
| `add_edge(src, dst)` | Always route src → dst |
| `add_conditional_edges(src, fn)` | fn(state) returns node name or list of names |
| `add_conditional_edges(src, fn, mapping)` | fn return value mapped through dict to node names |
| `add_edge(START, "node")` | Entry point |
| `add_conditional_edges(START, fn)` | Conditional entry |

Multiple outgoing edges from a node cause **parallel execution** in the next
super-step. Source: `docs/graph-api.md`.

## Command — combine routing and state update

Return `Command` from a node to update state **and** route in one step:

```python
from langgraph.types import Command
from typing import Literal

def my_node(state: State) -> Command[Literal["next_node"]]:
    return Command(
        update={"key": "value"},
        goto="next_node"
    )
```

`Command` parameters:
- `update` — state dict, applied through reducers.
- `goto` — node name(s) to route to (adds dynamic edges; static `add_edge` edges still fire).
- `graph=Command.PARENT` — navigate from subgraph node to parent graph.
- `resume` — **only** valid as input to `invoke()`/`stream()` after an `interrupt()`.

Use `Command` when you need both state update and routing. Use conditional edges
when routing only. Source: `docs/graph-api.md`.

## Send — dynamic fan-out (map-reduce)

When the number of parallel branches is not known ahead of time, return `Send`
objects from a conditional edge:

```python
from langgraph.types import Send

def fanout_edge(state: OverallState):
    return [Send("process_item", {"item": x}) for x in state["items"]]

builder.add_conditional_edges("generator", fanout_edge)
```

Each `Send(node_name, state)` routes a separate copy of state to the named node.
Source: `docs/graph-api.md`.

## Multiple schemas

A graph can have separate input/output schemas (subsets of OverallState) and
private internal schemas:

```python
builder = StateGraph(
    OverallState,
    input_schema=InputState,
    output_schema=OutputState
)
```

Nodes can write to any channel defined across all schemas, even if the channel
is not in their declared input type. Source: `docs/graph-api.md`.

## Runtime context

Pass dependency injection data that is not part of graph state:

```python
from dataclasses import dataclass
from langgraph.runtime import Runtime

@dataclass
class Ctx:
    llm_provider: str

builder = StateGraph(State, context_schema=Ctx)
graph = builder.compile()
graph.invoke(inputs, context={"llm_provider": "anthropic"})

def my_node(state: State, runtime: Runtime[Ctx]):
    llm = get_llm(runtime.context.llm_provider)
```

Source: `docs/graph-api.md`.

## Recursion limit

Default is 1000 super-steps. Set per-invocation via top-level config (not
inside `configurable`):

```python
graph.invoke(inputs, config={"recursion_limit": 50})
```

Use `RemainingSteps` managed value in state for proactive graceful degradation.
Reactive option: catch `GraphRecursionError` externally. Source: `docs/graph-api.md`.

## Graph migrations

When using a checkpointer, graph topology changes are safe for threads that
have reached END. For interrupted threads, renaming/removing nodes that the
thread would re-enter is unsupported. Adding/removing state keys has full
forward/backward compatibility; renaming keys loses saved values for that key.
Source: `docs/graph-api.md`.

## Retry policies

Attach per-node retry logic:

```python
from langgraph.types import RetryPolicy

builder.add_node(
    "api_call",
    api_call_fn,
    retry_policy=RetryPolicy(max_attempts=3, initial_interval=1.0)
)
```

Source: `docs/thinking-in-langgraph.md`.
