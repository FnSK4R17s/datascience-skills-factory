# Subgraphs Reference

Source: `docs/use-subgraphs.md`, `docs/add-memory.md`

## What subgraphs are

A subgraph is a compiled graph used as a node in another (parent) graph. Subgraphs
enable modular composition, multi-agent systems, and team-level isolation.

## Two composition patterns

### Pattern 1: Add subgraph directly as a node (shared state keys)

Use when parent and subgraph share at least some state keys. The subgraph reads
from and writes to the parent's state channels automatically.

```python
class SharedState(TypedDict):
    foo: str

subgraph_builder = StateGraph(SharedState)
subgraph_builder.add_node("step", step_fn)
subgraph_builder.add_edge(START, "step")
subgraph = subgraph_builder.compile()

parent_builder = StateGraph(SharedState)
parent_builder.add_node("run_sub", subgraph)   # compiled graph as node
parent_builder.add_edge(START, "run_sub")
graph = parent_builder.compile()
```

### Pattern 2: Invoke subgraph inside a node function (different state keys)

Use when parent and subgraph have different state schemas. The wrapping node
transforms state before and after calling the subgraph.

```python
class ParentState(TypedDict):
    foo: str

class SubState(TypedDict):
    bar: str

def call_subgraph(state: ParentState) -> ParentState:
    result = subgraph.invoke({"bar": state["foo"]})
    return {"foo": result["bar"]}

parent_builder.add_node("sub_wrapper", call_subgraph)
```

## Subgraph persistence modes

Control how subgraph state is retained between invocations via the `checkpointer`
argument on the subgraph's `.compile()`:

| `checkpointer=` | Mode | Behaviour |
|----------------|------|-----------|
| `None` (default) | Per-invocation | Each call starts fresh. Inherits parent checkpointer; supports interrupts within a call. |
| `True` | Per-thread | State accumulates across calls on the same thread. |
| `False` | Stateless | No checkpointing; no interrupts; runs like a plain function. |

The parent graph must have a checkpointer for any subgraph persistence to work.

### Per-invocation (default, recommended)

```python
subgraph = builder.compile()              # inherits parent checkpointer
```

- Each invocation starts with empty subgraph state.
- Supports `interrupt()` within the call.
- Multiple calls to different subgraphs in the same node are safe.

### Per-thread

```python
subgraph = builder.compile(checkpointer=True)
```

- Subgraph remembers state across invocations on the same parent thread.
- **Warning:** Do not call the same per-thread subgraph in parallel (same call, multiple
  times). Namespace conflicts occur. Use `ToolCallLimitMiddleware` or structure to avoid.
- Multiple *different* per-thread subgraphs called inside a node can conflict if
  called by index. Wrap each in its own named `StateGraph` node for stable namespaces.

### Stateless

```python
subgraph = builder.compile(checkpointer=False)
```

No durability, no interrupts. Fastest option.

## Viewing subgraph state

```python
# Get subgraph state while interrupted
state = graph.get_state(config, subgraphs=True)
sub_state = state.tasks[0].state       # StateSnapshot of the subgraph
```

Requires the subgraph to be added as a node (not called inside a tool or other
indirection). Only per-invocation and per-thread subgraphs can be inspected.

## Streaming from subgraphs

```python
for chunk in graph.stream(inputs, subgraphs=True, stream_mode="updates", version="v2"):
    print(chunk["ns"])   # () root; ("parent_node:uuid",) subgraph
    print(chunk["data"])
```

## Checkpoint namespacing

Subgraph checkpoints use `checkpoint_ns` to distinguish them from the parent:
- Parent: `""` (empty string)
- Subgraph at node `"sub"`: `"sub:uuid"`
- Nested: `"outer:uuid|inner:uuid"`

When two different per-thread subgraphs are called inside the same node function,
LangGraph assigns namespaces by call order (1st call, 2nd call, ...). Reordering
calls mixes up which subgraph loads which state. Fix: wrap each subgraph in a named
`StateGraph` node to get stable name-based namespaces.

## Navigating to parent graph

From inside a subgraph, use `Command.PARENT` to target the parent:

```python
def subgraph_node(state) -> Command:
    return Command(update={...}, goto="parent_node", graph=Command.PARENT)
```

When updating a key shared between parent and subgraph via `Command.PARENT`, the
parent state must have a reducer for that key.
