# Interrupts (Human-in-the-Loop)

`interrupt()` pauses graph execution at any point and waits indefinitely
for external input. Requires a checkpointer and a `thread_id` in config.

## How it works

1. `interrupt(payload)` raises a special internal exception.
2. LangGraph catches it, saves a checkpoint, and surfaces the payload.
3. You call `graph.invoke(Command(resume=value), config)` to continue.
4. The interrupted node re-runs from its beginning; the `interrupt()` call
   now returns `value` instead of pausing.

## Minimum example

```python
from langgraph.types import interrupt, Command
from langgraph.checkpoint.memory import InMemorySaver

def approval_node(state: State):
    approved = interrupt("Approve this action?")  # pauses here
    return {"approved": approved}

graph = builder.compile(checkpointer=InMemorySaver())

config = {"configurable": {"thread_id": "t1"}}

# First call — graph pauses at interrupt()
result = graph.invoke({"action": "..."}, config)
# result["__interrupt__"] -> [Interrupt(value="Approve this action?")]

# Resume — graph continues, interrupt() returns True
result = graph.invoke(Command(resume=True), config)
```

## Detecting interrupts

**v1 (default):** check for `"__interrupt__"` key in the result dict.

**v2 (LangGraph >= 1.1):** pass `version="v2"` to get a `GraphOutput`:

```python
result = graph.invoke(inputs, config=config, version="v2")
if result.interrupts:
    payload = result.interrupts[0].value
    graph.invoke(Command(resume=user_answer), config=config, version="v2")
```

When streaming with `version="v2"`, interrupt payloads appear in the
`interrupts` field of `values` stream parts.

## Common patterns

### Approve / reject with routing

```python
from typing import Literal
from langgraph.types import interrupt, Command

def gate(state: State) -> Command[Literal["proceed", "cancel"]]:
    decision = interrupt({"question": "Approve?", "details": state["details"]})
    return Command(goto="proceed" if decision else "cancel")
```

### Review and edit state

```python
def review(state: State):
    edited = interrupt({"instruction": "Edit this", "content": state["draft"]})
    return {"draft": edited}
```

### Interrupt inside a tool

```python
from langchain.tools import tool

@tool
def send_email(to: str, subject: str, body: str):
    """Send an email."""
    response = interrupt({"action": "send_email", "to": to, "subject": subject})
    if response.get("action") == "approve":
        return f"Sent to {to}"
    return "Cancelled"
```

### Validation loop (re-prompt until valid)

```python
def collect_age(state: State):
    prompt = "What is your age?"
    while True:
        answer = interrupt(prompt)
        if isinstance(answer, int) and answer > 0:
            break
        prompt = f"'{answer}' is not valid. Enter a positive integer."
    return {"age": answer}
```

### Multiple parallel interrupts

When parallel branches each hit `interrupt()`, resume with a dict keyed
by interrupt ID:

```python
result = graph.invoke({"vals": []}, config)
resume_map = {i.id: f"answer for {i.value}" for i in result["__interrupt__"]}
graph.invoke(Command(resume=resume_map), config)
```

## Rules — violations cause silent or confusing bugs

### Do NOT wrap interrupt() in bare try/except

`interrupt()` works by raising a special exception. A bare `except Exception`
swallows it and the graph never pauses:

```python
# WRONG
try:
    answer = interrupt("Approve?")
except Exception:
    pass

# OK — specific exception type will not catch the interrupt signal
try:
    answer = interrupt("Approve?")
    do_risky_thing()
except NetworkError:
    handle()
```

### Do NOT reorder interrupt() calls within a node

On resume, the node re-runs from the top. LangGraph matches resume values
to interrupt calls by **index** (first call gets first resume value, etc.).
If the order changes between the initial run and the resume, values go to
the wrong calls.

```python
# WRONG — order may differ on resume
if condition:
    name = interrupt("name?")
city = interrupt("city?")

# OK — always same order
name = interrupt("name?")
city = interrupt("city?")
```

### Do NOT pass non-serialisable values to interrupt()

Checkpointers serialise the interrupt payload. Pass only JSON-serialisable
types (str, int, bool, list, dict with simple values). No functions, no
class instances.

### Make side effects before interrupt() idempotent

The node re-runs from the top on resume. Any side effect before `interrupt()`
runs again. Use upsert patterns, not insert:

```python
# WRONG — creates duplicate records on every resume
db.insert_audit_log(...)
approved = interrupt("Approve?")

# OK — idempotent, or move the side effect after the interrupt
approved = interrupt("Approve?")
if approved:
    db.insert_audit_log(...)  # runs once, after approval
```

## Static breakpoints (debugging only)

For stepping through a graph in development — not recommended for production
human-in-the-loop:

```python
graph = builder.compile(
    checkpointer=checkpointer,
    interrupt_before=["node_a"],
    interrupt_after=["node_b"],
)

config = {"configurable": {"thread_id": "debug"}}
graph.invoke(inputs, config)          # runs until first breakpoint
graph.invoke(None, config)            # resume to next breakpoint
```

Can also be set per-invocation:

```python
graph.invoke(inputs, config, interrupt_before=["node_a"])
```
