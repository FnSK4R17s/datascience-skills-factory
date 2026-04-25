# Time Travel Reference

Source: `docs/use-time-travel.md`, `docs/persistence.md`

## Overview

Time travel lets you replay or fork a past execution using saved checkpoints.

- **Replay**: Re-run nodes from a prior checkpoint. Nodes *before* the checkpoint are
  skipped (results already saved). Nodes *after* re-execute — including LLM calls,
  API calls, and `interrupt()` calls. Results may differ.
- **Fork**: Create a modified branch from a prior checkpoint, then continue execution
  from that modified state.

Requires a checkpointer on the graph.

## Replay

```python
from langgraph.checkpoint.memory import InMemorySaver
from langgraph.graph import StateGraph, START, END
from typing_extensions import TypedDict

class State(TypedDict):
    value: str

def node_a(state: State):
    return {"value": "from_a"}

def node_b(state: State):
    return {"value": "from_b"}

builder = StateGraph(State)
builder.add_node("node_a", node_a)
builder.add_node("node_b", node_b)
builder.add_edge(START, "node_a")
builder.add_edge("node_a", "node_b")
builder.add_edge("node_b", END)

graph = builder.compile(checkpointer=InMemorySaver())
config = {"configurable": {"thread_id": "1"}}

# Initial run
graph.invoke({"value": "initial"}, config)

# 1. Find the checkpoint to replay from
history = list(graph.get_state_history(config))
# history is newest-first

# 2. Select a checkpoint (e.g. before node_b)
before_b = next(s for s in history if s.next == ("node_b",))
print(f"Replaying from step {before_b.metadata['step']}")
print(f"State at that point: {before_b.values}")

# 3. Replay from that checkpoint
result = graph.invoke(None, before_b.config)
# node_b and everything after it re-execute with potentially different outcomes
```

Replaying from the final checkpoint (no `next` nodes) is a no-op.

## Fork

Fork creates a new branch with modified state without rolling back the original history.

```python
# 1. Find the checkpoint to fork from
history = list(graph.get_state_history(config))
before_b = next(s for s in history if s.next == ("node_b",))

# 2. Fork: modify state, returns config for the new branch
fork_config = graph.update_state(
    before_b.config,
    values={"value": "modified_for_fork"},   # override state
)

# 3. Continue execution from the fork
result = graph.invoke(None, fork_config)
# Executes node_b onwards with the modified state
print(result["value"])   # node_b received modified state
```

`update_state` creates a new checkpoint. The original execution history is intact.
Reducers apply to the values passed — channels with reducers *accumulate* rather
than overwrite.

## `as_node` parameter

`update_state` records which node produced the update, determining which node runs
next. LangGraph infers this from the checkpoint's history. Specify explicitly when:

- Parallel branches ran in the same step (ambiguous "last node").
- Setting up state on a fresh thread (no execution history).
- Skipping to a later node (make it appear as if an earlier node already ran).

```python
fork_config = graph.update_state(
    before_b.config,
    values={"value": "modified"},
    as_node="node_a",          # treat update as if node_a produced it
)
# Execution resumes at node_a's successors (i.e. node_b)
```

## Interrupts and time travel

Interrupts are always re-triggered during time travel. Replay or fork from before an
interrupted node — the node re-runs and `interrupt()` fires again, waiting for a new
`Command(resume=...)`.

```python
# Scenario: graph has two sequential interrupt() calls
# Fork between them — preserve first answer, change second

history = list(graph.get_state_history(config))

# Find the snapshot where the second interrupt is about to fire
# (first interrupt has already been answered)
between = next(
    s for s in history
    if s.next == ("ask_second_question",)
)

fork_config = graph.update_state(between.config, {"notes": "modified context"})
result = graph.invoke(None, fork_config)
# ask_first_question's result preserved from checkpoint
# ask_second_question pauses for new input
```

## Subgraphs and time travel

| Subgraph checkpointer | Granularity |
|-----------------------|-------------|
| `None` (default — inherits parent) | Only parent-level checkpoints. Entire subgraph re-executes from scratch on time travel. Cannot replay *within* the subgraph. |
| `True` (own checkpoint history) | Subgraph creates per-step checkpoints. Can time-travel from a point inside the subgraph. |

Accessing subgraph checkpoint config for forking:

```python
# Get current subgraph state after an interrupt
parent_state = graph.get_state(config, subgraphs=True)
sub_config = parent_state.tasks[0].state.config

fork_config = graph.update_state(sub_config, {"data": "modified"})
graph.invoke(None, fork_config)   # resumes from inside the subgraph
```

## Finding specific checkpoints

```python
history = list(graph.get_state_history(config))

# Before a specific node
before_b = next(s for s in history if s.next == ("node_b",))

# At a specific step number
step_3 = next(s for s in history if s.metadata["step"] == 3)

# Created by update_state (not by graph execution)
forks = [s for s in history if s.metadata["source"] == "update"]

# Where an interrupt occurred
interrupted = next(
    s for s in history
    if s.tasks and any(t.interrupts for t in s.tasks)
)

# Most recent checkpoint before a given timestamp
import datetime
cutoff = datetime.datetime(2024, 1, 1, tzinfo=datetime.timezone.utc)
before_cutoff = [s for s in history if datetime.datetime.fromisoformat(s.created_at) < cutoff]
```

## Practical debugging workflow

```python
# Step 1: Run the graph
config = {"configurable": {"thread_id": "debug-1"}}
result = graph.invoke(inputs, config)

# Step 2: Inspect history
for snap in graph.get_state_history(config):
    print(f"Step {snap.metadata['step']:2d} | next={snap.next} | values={snap.values}")

# Step 3: Fork from the problematic checkpoint
problem_snap = ...  # found via step 2
fork_config = graph.update_state(
    problem_snap.config,
    values={"data": "corrected_value"},
    as_node="the_node_before_problem",
)

# Step 4: Re-run from the fork to verify fix
result = graph.invoke(None, fork_config)
print(result)
```
