# Interrupts and Human-in-the-Loop

Source: `docs/interrupts.md`, `docs/graph-api.md`

## Overview

`interrupt()` pauses graph execution at any point in a node and waits
indefinitely for external input. The graph state is saved by the checkpointer.
Execution resumes by re-invoking with `Command(resume=value)`.

Requirements:
1. A **checkpointer** attached at compile time.
2. A **thread_id** in config so the runtime knows which state to resume.
3. The `interrupt()` call itself (payload must be JSON-serializable).

## Pause

```python
from langgraph.types import interrupt

def approval_node(state: State):
    decision = interrupt({
        "question": "Approve this action?",
        "details": state["action_details"]
    })
    # `decision` is whatever was passed to Command(resume=...)
    return {"approved": decision}
```

What happens on `interrupt()`:
1. Execution suspends (via a special exception that must not be caught).
2. State is saved to the checkpointer.
3. The interrupt payload surfaces to the caller under `__interrupt__` (v1) or
   `result.interrupts` (v2 with `version="v2"`).
4. Graph waits until resumed.

Source: `docs/interrupts.md`.

## Resume

```python
from langgraph.types import Command

config = {"configurable": {"thread_id": "thread-1"}}

# First invocation — hits interrupt and pauses
result = graph.invoke({"input": "data"}, config=config)
print(result["__interrupt__"])  # [Interrupt(value=..., id=...)]

# Resume — passes value back into the node
graph.invoke(Command(resume=True), config=config)
```

**The node restarts from the beginning** when resumed — any code before
`interrupt()` re-executes. Place side effects after `interrupt()` or in
separate nodes. Source: `docs/interrupts.md`.

## Common patterns

### Approve / reject
```python
def approval_node(state: State) -> Command[Literal["proceed", "cancel"]]:
    approved = interrupt({"question": "Approve?", "details": state["details"]})
    return Command(goto="proceed" if approved else "cancel")
```

### Review and edit
```python
def review_node(state: State):
    edited = interrupt({"instruction": "Edit this", "content": state["draft"]})
    return {"draft": edited}
```

### Validate in a loop
```python
def collect_age(state: State):
    prompt = "What is your age?"
    while True:
        answer = interrupt(prompt)
        if isinstance(answer, int) and answer > 0:
            return {"age": answer}
        prompt = f"'{answer}' is not valid. Enter a positive number."
```

### Interrupt inside a tool
Place `interrupt()` inside a `@tool` function to pause before the tool executes.
The tool remains reusable across graph nodes. Source: `docs/interrupts.md`.

### Multiple parallel interrupts
When parallel branches each call `interrupt()`, resume all at once by mapping
interrupt IDs to values:

```python
result = graph.invoke({"vals": []}, config)
resume_map = {i.id: f"answer for {i.value}" for i in result["__interrupt__"]}
graph.invoke(Command(resume=resume_map), config)
```

Source: `docs/interrupts.md`.

## Static breakpoints (debugging only)

For step-through debugging, compile with `interrupt_before`/`interrupt_after`:

```python
graph = builder.compile(
    interrupt_before=["node_a"],
    interrupt_after=["node_b"],
    checkpointer=checkpointer,
)
# Resume by passing None
graph.invoke(None, config)
```

Not recommended for production human-in-the-loop — use `interrupt()` instead.
Source: `docs/interrupts.md`.

## Rules

| Rule | Consequence of violation |
|------|--------------------------|
| Never wrap `interrupt()` in bare `try/except Exception` | Catches the pause exception; interrupt never fires |
| Keep `interrupt()` call order consistent across node executions | Matching is index-based; mis-order mis-routes resume values |
| Only pass JSON-serializable payloads to `interrupt()` | Runtime error with persistent checkpointers |
| Side effects before `interrupt()` must be idempotent | Re-run on every resume; duplicate writes/records |
| `Command(resume=...)` is the only `Command` valid as `invoke()` input | `Command(update=...)` as input makes graph appear stuck |

Source: `docs/interrupts.md`, `docs/graph-api.md`.

## v2 streaming with interrupts

With `version="v2"`, `invoke()` returns a `GraphOutput` object:

```python
result = graph.invoke(inputs, config=config, version="v2")
if result.interrupts:
    print(result.interrupts[0].value)
    graph.invoke(Command(resume=True), config=config, version="v2")
```

When streaming, interrupt payloads appear in `chunk["interrupts"]` on `values`
stream parts. Source: `docs/streaming.md`.
