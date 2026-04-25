# Pregel Execution Model Reference

Source: `docs/pregel.md`

## Overview

[Pregel](https://research.google/pubs/pub37252/) is Google's large-scale graph
processing algorithm (also called Bulk Synchronous Parallel). LangGraph's runtime
is named after it because it follows the same three-phase step model.

Compiling a `StateGraph` or decorating with `@entrypoint` produces a `Pregel`
instance — the actual executor. Most users never need to interact with `Pregel`
directly; this reference covers the execution model and when it matters.

## Execution cycle (super-steps)

Each super-step has three phases:

1. **Plan**: determine which actors (nodes) to activate — those subscribed to
   channels updated in the previous step, or entry-point nodes on step 0.
2. **Execution**: run all selected actors in parallel until all complete, one fails,
   or a timeout is reached. Channel updates written during this phase are invisible to
   other actors until the next step.
3. **Update**: apply all channel writes from this step, save checkpoint.

Repeat until no actors are selected or the recursion limit is reached.

## Key concepts

**Actors (PregelNode)**: subscribe to one or more channels, read from them, and write
to them. Each node in a `StateGraph` becomes a `PregelNode`.

**Channels**: communication medium between actors. Built-in channel types:

| Channel | Description |
|---------|-------------|
| `LastValue` | Stores the last value sent; default for state keys |
| `Topic` | Configurable pub/sub; can deduplicate or accumulate across steps |
| `BinaryOperatorAggregate` | Persistent value updated by applying a binary op (e.g. sum) |
| `EphemeralValue` | Transient; exists only within one super-step |

## Why super-steps matter

- **Parallelism**: nodes in the same super-step run in parallel; nodes in different
  super-steps run sequentially. Adding multiple edges from the same source node runs
  all destination nodes in parallel within one super-step.
- **Checkpointing**: a checkpoint is saved at each super-step boundary. The `step`
  counter in checkpoint metadata corresponds to super-step number.
- **Time travel granularity**: you can only replay or fork from super-step boundaries
  (checkpoint boundaries), not from arbitrary lines of code within a node.

## Worked example: super-step sequence

For a sequential graph `START → A → B → C → END`:

| Super-step | Nodes active | Checkpoint saved |
|---|---|---|
| 0 | `__start__` (processes input) | Yes — with initial values |
| 1 | `A` | Yes — after A completes |
| 2 | `B` | Yes — after B completes |
| 3 | `C` | Yes — after C completes |

Total: 4 checkpoints for a 3-node sequential graph.

For a parallel graph `START → (A, B in parallel) → C → END`:

| Super-step | Nodes active | Checkpoint saved |
|---|---|---|
| 0 | `__start__` | Yes |
| 1 | `A` and `B` (same super-step) | Yes — after both complete |
| 2 | `C` | Yes |

Total: 3 checkpoints. A and B share checkpoint boundary.

## Direct Pregel API (advanced)

Most users should use `StateGraph` or `@entrypoint`. The direct `Pregel` API is for
specialized use cases where the high-level APIs are insufficient.

```python
from langgraph.channels import EphemeralValue, LastValue, Topic, BinaryOperatorAggregate
from langgraph.pregel import Pregel, NodeBuilder

node1 = (
    NodeBuilder()
    .subscribe_only("input_ch")      # read the value directly (not as dict)
    .do(lambda x: x.upper())
    .write_to("output_ch")
)

app = Pregel(
    nodes={"node1": node1},
    channels={
        "input_ch": EphemeralValue(str),
        "output_ch": EphemeralValue(str),
    },
    input_channels=["input_ch"],
    output_channels=["output_ch"],
)

result = app.invoke({"input_ch": "hello"})
# {'output_ch': 'HELLO'}
```

`NodeBuilder` supports: `.subscribe_only("ch")` (read value directly),
`.subscribe_to("ch")` (read as dict), `.do(fn)`, `.write_to("ch", ...)`.

## Inspecting compiled graph internals

```python
from langgraph.graph import StateGraph, START, END
from typing_extensions import TypedDict

class State(TypedDict):
    foo: str

builder = StateGraph(State)
builder.add_node("my_node", lambda s: {"foo": "bar"})
builder.add_edge(START, "my_node")
builder.add_edge("my_node", END)
graph = builder.compile()

# Nodes are PregelNode instances
print(graph.nodes)
# {'__start__': <PregelNode ...>, 'my_node': <PregelNode ...>, ...}

# Channels are LangGraph channel objects
print(graph.channels)
# {'foo': <LastValue ...>, '__start__': <EphemeralValue ...>, ...}

# Graph structure for visualization
graph_repr = graph.get_graph()
for node in graph_repr.nodes.values():
    print(f"Node: {node.id}, type: {node.data}")
for edge in graph_repr.edges:
    print(f"Edge: {edge.source} -> {edge.target}")
```

## Recursion limit and step counter

`config={"recursion_limit": N}` limits the number of super-steps. The step counter
is in `config["metadata"]["langgraph_step"]` within any node.

```python
from langchain_core.runnables import RunnableConfig

def my_node(state: dict, config: RunnableConfig) -> dict:
    current_step = config["metadata"]["langgraph_step"]
    print(f"Currently on step: {current_step}")
    return state
```

Use `RemainingSteps` managed value for proactive handling — see `references/graph-api.md`.

## Message passing model

When a node completes, it sends messages along one or more edges to other nodes.
These recipient nodes then execute their functions, pass the resulting messages to
the next set of nodes, and the process continues.

A node becomes **active** when it receives a new message (state) on any of its
incoming edges or channels. At the end of each super-step, nodes with no incoming
messages vote to **halt** by marking themselves as inactive. Graph execution
terminates when all nodes are inactive and no messages are in transit.

This model is why adding multiple outgoing edges from a node runs all destination
nodes in parallel — they all receive messages in the same super-step and activate
simultaneously.
