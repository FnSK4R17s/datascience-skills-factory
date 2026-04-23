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
3. **Update**: apply all channel writes from this step.

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
  super-steps run sequentially. Adding multiple edges from the same node runs them
  in parallel within one super-step.
- **Checkpointing**: a checkpoint is saved at each super-step boundary. The `step`
  counter in checkpoint metadata corresponds to super-step number.
- **Time travel granularity**: you can only replay or fork from super-step boundaries
  (i.e. checkpoint boundaries), not from arbitrary lines of code.

## Direct Pregel API (advanced)

Most users should use `StateGraph` or `@entrypoint`. The direct `Pregel` API is for
specialized use cases where the high-level APIs are insufficient.

```python
from langgraph.channels import EphemeralValue, LastValue, Topic, BinaryOperatorAggregate
from langgraph.pregel import Pregel, NodeBuilder

node1 = (
    NodeBuilder()
    .subscribe_only("input_ch")
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

app.invoke({"input_ch": "hello"})   # {'output_ch': 'HELLO'}
```

`NodeBuilder` supports: `.subscribe_only("ch")` (read value directly),
`.subscribe_to("ch")` (read as dict), `.do(fn)`, `.write_to("ch", ...)`.

## Inspecting compiled graph internals

```python
graph = builder.compile()

# Nodes are PregelNode instances
print(graph.nodes)
# {'__start__': <PregelNode ...>, 'my_node': <PregelNode ...>, ...}

# Channels are LangGraph channel objects
print(graph.channels)
# {'key': <LastValue ...>, '__start__': <EphemeralValue ...>, ...}
```

## Recursion limit and step counter

`config={"recursion_limit": N}` limits the number of super-steps. The step counter
is in `config["metadata"]["langgraph_step"]` within any node. Access it to implement
graceful degradation (see `references/graph-api.md`).
