# Interrupts and Human-in-the-Loop Reference

Source: `docs/interrupts.md`, `docs/graph-api.md`

## Overview

`interrupt()` pauses graph execution at an arbitrary point inside a node. LangGraph
saves state via the checkpointer, then waits indefinitely. Resume by invoking again
with `Command(resume=<value>)` on the same thread.

Requirements:
1. A checkpointer (durable in production)
2. A `thread_id` in config
3. `interrupt()` call inside a node; payload must be JSON-serializable

## Basic pattern

```python
from langgraph.types import interrupt, Command

def approval_node(state):
    # Pauses here; payload surfaces to caller
    decision = interrupt({"question": "Approve?", "details": state["action"]})
    return {"approved": decision}

# First run — hits interrupt
config = {"configurable": {"thread_id": "t1"}}
result = graph.invoke(inputs, config)
# v1: result["__interrupt__"][0].value
# v2: result.interrupts[0].value

# Resume — decision becomes return value of interrupt()
graph.invoke(Command(resume=True), config)
```

## v2 invoke format (LangGraph >= 1.1)

```python
result = graph.invoke(inputs, config, version="v2")
# result is GraphOutput with .value and .interrupts
if result.interrupts:
    payload = result.interrupts[0].value
    graph.invoke(Command(resume="user answer"), config, version="v2")
```

Dict-style access (`result["__interrupt__"]`) still works but is deprecated.

## Common patterns

### Approve / reject

```python
def gate(state) -> Command[Literal["proceed", "cancel"]]:
    ok = interrupt({"action": state["cmd"]})
    return Command(goto="proceed" if ok else "cancel")
```

### Review and edit

```python
def review(state):
    edited = interrupt({"content": state["draft"]})
    return {"draft": edited}   # edited text replaces draft
```

### Interrupt inside a tool

```python
from langchain.tools import tool

@tool
def send_email(to: str, body: str):
    """Send an email."""
    resp = interrupt({"to": to, "body": body, "action": "approve sending?"})
    if resp.get("action") == "approve":
        # ... actually send
        return "sent"
    return "cancelled"
```

### Validation loop

```python
def collect_age(state):
    prompt = "Enter age:"
    while True:
        answer = interrupt(prompt)
        if isinstance(answer, int) and answer > 0:
            return {"age": answer}
        prompt = f"'{answer}' invalid. Enter positive integer:"
```

### Multiple parallel interrupts

When parallel nodes each call `interrupt()`, resume by mapping interrupt IDs to values:

```python
result = graph.invoke(inputs, config)
resume_map = {i.id: f"answer to {i.value}" for i in result["__interrupt__"]}
graph.invoke(Command(resume=resume_map), config)
```

### HITL with streaming

```python
async for chunk in graph.astream(inputs, stream_mode=["messages", "updates"],
                                  subgraphs=True, config=config, version="v2"):
    if chunk["type"] == "updates" and "__interrupt__" in chunk["data"]:
        user_response = await get_input(chunk["data"]["__interrupt__"][0].value)
        # Re-invoke with resume
```

## Rules of interrupts

### Do NOT wrap in bare try/except

```python
# WRONG — catches the interrupt exception
try:
    result = interrupt("question")
except Exception:
    pass

# CORRECT — catch specific exceptions only
try:
    result = interrupt("question")
    fetch_data()
except NetworkError:
    ...
```

### Do NOT reorder interrupt calls between executions

Resume matching is strictly index-based. Conditionally skipping an interrupt or
reordering them between the first and resumed run causes mis-routing.

```python
# WRONG — conditional interrupt changes call order on resume
if state.get("needs_info"):
    info = interrupt("info?")
name = interrupt("name?")

# CORRECT — stable order every run
name = interrupt("name?")
info = interrupt("info?")  # always called, even if unused
```

### Payloads must be JSON-serializable

No functions, class instances, file handles, or other non-serializable objects.
Pass dicts with primitive values.

### Pre-interrupt side effects must be idempotent

The node re-runs from its beginning on every resume. Any operation before `interrupt()`
runs again. Use idempotent writes (upsert, not insert), or place side effects after
the interrupt call, or move them to a separate node.

## Static breakpoints (debugging only)

```python
# At compile time
graph = builder.compile(interrupt_before=["node_a"], interrupt_after=["node_b"],
                        checkpointer=checkpointer)

# At run time (overrides compile-time settings)
graph.invoke(inputs, interrupt_before=["node_a"], config=config)

# Resume
graph.invoke(None, config)   # run until next breakpoint
```

Static breakpoints are for debugging — not recommended for production HITL workflows.
Use `interrupt()` instead for production.

## Subgraphs and interrupts

When a subgraph contains an interrupt, the parent resumes from the beginning of the
node that invoked the subgraph (not from the interrupt line). The subgraph also resumes
from its own node's beginning.
