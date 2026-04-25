# Subgraphs Reference

Source: `docs/use-subgraphs.md`, `docs/add-memory.md`

## What subgraphs are

A subgraph is a compiled graph used as a node in another (parent) graph. Subgraphs
enable modular composition, multi-agent systems, and team-level isolation.

Use cases:
- Building multi-agent systems where each agent is a subgraph
- Reusing node sets across multiple graphs
- Distributing development — teams own individual subgraphs; parent only needs the interface

## Two composition patterns

### Pattern 1: Add subgraph directly as a node (shared state keys)

Use when parent and subgraph share at least some state keys. The subgraph reads
from and writes to the parent's state channels automatically.

```python
from typing_extensions import TypedDict
from langgraph.graph import StateGraph, START, END

class SharedState(TypedDict):
    foo: str
    bar: str

def subgraph_node_1(state: SharedState):
    return {"bar": "hi! " + state["foo"]}

subgraph_builder = StateGraph(SharedState)
subgraph_builder.add_node(subgraph_node_1)
subgraph_builder.add_edge(START, "subgraph_node_1")
subgraph = subgraph_builder.compile()

def parent_node_1(state: SharedState):
    return {"foo": "world " + state["foo"]}

parent_builder = StateGraph(SharedState)
parent_builder.add_node("parent_1", parent_node_1)
parent_builder.add_node("subgraph", subgraph)    # compiled graph added directly as node
parent_builder.add_edge(START, "parent_1")
parent_builder.add_edge("parent_1", "subgraph")
parent_builder.add_edge("subgraph", END)
graph = parent_builder.compile()

result = graph.invoke({"foo": "hello", "bar": ""})
```

### Pattern 2: Invoke subgraph inside a node function (different state schemas)

Use when parent and subgraph have different state schemas. The wrapping node
transforms state before and after calling the subgraph.

```python
from typing_extensions import TypedDict
from langgraph.graph import StateGraph, START, END

# Parent has "foo"; subgraph has "bar" — no shared keys
class SubgraphState(TypedDict):
    bar: str
    baz: str

def subgraph_node_1(state: SubgraphState):
    return {"baz": "baz"}

def subgraph_node_2(state: SubgraphState):
    return {"bar": state["bar"] + state["baz"]}

subgraph_builder = StateGraph(SubgraphState)
subgraph_builder.add_node(subgraph_node_1)
subgraph_builder.add_node(subgraph_node_2)
subgraph_builder.add_edge(START, "subgraph_node_1")
subgraph_builder.add_edge("subgraph_node_1", "subgraph_node_2")
subgraph = subgraph_builder.compile()

class ParentState(TypedDict):
    foo: str

def call_subgraph(state: ParentState) -> ParentState:
    # Transform parent → subgraph input
    subgraph_output = subgraph.invoke({"bar": state["foo"], "baz": ""})
    # Transform subgraph output → parent state update
    return {"foo": subgraph_output["bar"]}

parent_builder = StateGraph(ParentState)
parent_builder.add_node("node_1", call_subgraph)
parent_builder.add_edge(START, "node_1")
parent_builder.add_edge("node_1", END)
graph = parent_builder.compile()

result = graph.invoke({"foo": "hello"})
print(result["foo"])   # "hellobaz"
```

## Subgraph persistence modes

Control how subgraph state is retained between invocations via the `checkpointer`
argument on the subgraph's `.compile()`.

| `checkpointer=` | Mode | Behaviour |
|----------------|------|-----------|
| `None` (default) | Per-invocation | Each call starts fresh. Inherits parent checkpointer; supports interrupts within a call. |
| `True` | Per-thread | State accumulates across calls on the same parent thread. |
| `False` | Stateless | No checkpointing; no interrupts; runs like a plain function. |

The **parent graph must have a checkpointer** for any subgraph persistence to work.

### Per-invocation (default, recommended)

```python
subgraph = builder.compile()              # no checkpointer arg = inherits parent's
```

- Each invocation starts with empty subgraph state.
- Supports `interrupt()` within the call.
- Multiple calls to different subgraphs in the same node are safe.
- Subgraph state is visible in parent's checkpoint (under `checkpoint_ns`).

### Per-thread

```python
subgraph = builder.compile(checkpointer=True)
```

- Subgraph remembers state across invocations on the same parent thread.
- **Warning:** Do NOT call the same per-thread subgraph in parallel (same invocation,
  multiple times). Namespace conflicts occur.
- Multiple *different* per-thread subgraphs called inside a single node can conflict
  if called by call order. Wrap each in its own named `StateGraph` node for stable
  name-based namespaces.

### Stateless

```python
subgraph = builder.compile(checkpointer=False)
```

No durability, no interrupts. Fastest option. Use for pure data transformation subgraphs.

## Viewing subgraph state

```python
from langgraph.checkpoint.memory import InMemorySaver

checkpointer = InMemorySaver()
graph = parent_builder.compile(checkpointer=checkpointer)
config = {"configurable": {"thread_id": "1"}}

# Run until interrupt inside subgraph
graph.invoke(inputs, config)

# Get subgraph state while interrupted — requires subgraphs=True
state = graph.get_state(config, subgraphs=True)
sub_state = state.tasks[0].state       # StateSnapshot of the subgraph
print(sub_state.values)
print(sub_state.next)
```

Requires the subgraph to be added as a node (Pattern 1), not called inside a tool
or other indirection. Only per-invocation and per-thread subgraphs can be inspected.

## Streaming from subgraphs

```python
for chunk in graph.stream(
    inputs,
    subgraphs=True,
    stream_mode="updates",
    version="v2"
):
    if chunk["ns"]:   # non-empty namespace = subgraph event
        print(f"Subgraph {chunk['ns']}: {chunk['data']}")
    else:
        print(f"Root: {chunk['data']}")
```

Namespace format:
- `()` — root graph
- `("node_2:dfddc4ba-c3c5-6887-5012-a243b5b377c2",)` — subgraph at node_2
- `("outer:uuid|inner:uuid",)` — nested subgraph

## Checkpoint namespacing

Subgraph checkpoints use `checkpoint_ns` to distinguish them from the parent:
- Parent: `""` (empty string)
- Subgraph at node `"sub"`: `"sub:uuid"`
- Nested: `"outer:uuid|inner:uuid"`

When two different per-thread subgraphs are called inside the same node function,
LangGraph assigns namespaces by call order (1st call, 2nd call...). Reordering
calls mixes up which subgraph loads which state. Fix: wrap each subgraph in a named
`StateGraph` node to get stable name-based namespaces.

## Navigating to parent graph

From inside a subgraph, use `Command.PARENT` to target the parent:

```python
from langgraph.types import Command

def subgraph_node(state) -> Command:
    return Command(
        update={"status": "done"},
        goto="parent_node",       # node name in the parent graph
        graph=Command.PARENT
    )
```

When updating a key shared between parent and subgraph via `Command.PARENT`, the
parent state must have a reducer for that key.

## Multi-agent example

Each agent is a subgraph; the parent graph routes between them.

```python
from typing_extensions import TypedDict
from langgraph.graph import StateGraph, MessagesState, START, END
from typing import Annotated
from langchain.messages import AnyMessage
import operator

# Researcher agent subgraph
class ResearcherState(MessagesState):
    search_results: list[str]

researcher_builder = StateGraph(ResearcherState)
# ... add researcher nodes ...
researcher_agent = researcher_builder.compile()

# Writer agent subgraph
class WriterState(MessagesState):
    draft: str

writer_builder = StateGraph(WriterState)
# ... add writer nodes ...
writer_agent = writer_builder.compile()

# Parent graph routes between agents using shared MessagesState
class ParentState(MessagesState):
    next_agent: str

def supervisor(state: ParentState) -> Command:
    # LLM decides which agent to call next
    response = model.invoke(state["messages"])
    return Command(
        update={"next_agent": response.content},
        goto=response.content  # "researcher" or "writer" or END
    )

parent_builder = StateGraph(ParentState)
parent_builder.add_node("supervisor", supervisor)
parent_builder.add_node("researcher", researcher_agent)
parent_builder.add_node("writer", writer_agent)
parent_builder.add_edge(START, "supervisor")
parent_builder.add_edge("researcher", "supervisor")
parent_builder.add_edge("writer", "supervisor")

orchestrator = parent_builder.compile(checkpointer=InMemorySaver())
```
