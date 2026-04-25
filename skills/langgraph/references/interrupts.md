# Interrupts and Human-in-the-Loop Reference

Source: `docs/interrupts.md`, `docs/graph-api.md`

## Overview

`interrupt()` pauses graph execution at an arbitrary point inside a node. LangGraph
saves state via the checkpointer, then waits indefinitely. Resume by invoking again
with `Command(resume=<value>)` on the same thread. The value passed to `Command(resume=...)`
becomes the return value of the `interrupt()` call inside the paused node.

Requirements:
1. A checkpointer (durable in production)
2. A `thread_id` in config
3. `interrupt()` call inside a node; payload must be JSON-serializable

Unlike static breakpoints (which pause before/after specific nodes), `interrupt()`
is dynamic — it can be placed anywhere in code and can be conditional.

## Basic pattern

```python
from langgraph.types import interrupt, Command
from langgraph.checkpoint.memory import MemorySaver
from langgraph.graph import StateGraph, START, END
from typing_extensions import TypedDict

class State(TypedDict):
    approved: bool

def approval_node(state: State):
    # Pauses here; payload surfaces to caller
    decision = interrupt({"question": "Approve?", "details": "some details"})
    return {"approved": decision}

builder = StateGraph(State)
builder.add_node("approval", approval_node)
builder.add_edge(START, "approval")
builder.add_edge("approval", END)

graph = builder.compile(checkpointer=MemorySaver())

# First run — hits interrupt
config = {"configurable": {"thread_id": "t1"}}
result = graph.invoke({"approved": False}, config)
print(result["__interrupt__"])
# [Interrupt(value={'question': 'Approve?', 'details': 'some details'}, id='...')]

# Resume — decision becomes return value of interrupt()
result = graph.invoke(Command(resume=True), config)
print(result["approved"])   # True
```

## v2 invoke format (LangGraph >= 1.1)

```python
result = graph.invoke(inputs, config, version="v2")
# result is GraphOutput with .value and .interrupts
if result.interrupts:
    payload = result.interrupts[0].value
    print(payload)
    graph.invoke(Command(resume="user answer"), config, version="v2")
```

Dict-style access (`result["__interrupt__"]`) still works but is deprecated.

## Common patterns

### Approve or reject

Full working example. Source: `docs/interrupts.md`.

```python
from typing import Literal, Optional
from langgraph.checkpoint.memory import MemorySaver
from langgraph.graph import StateGraph, START, END
from langgraph.types import Command, interrupt

class ApprovalState(TypedDict):
    action_details: str
    status: Optional[Literal["pending", "approved", "rejected"]]

def approval_node(state: ApprovalState) -> Command[Literal["proceed", "cancel"]]:
    decision = interrupt({
        "question": "Approve this action?",
        "details": state["action_details"],
    })
    return Command(goto="proceed" if decision else "cancel")

def proceed_node(state: ApprovalState):
    return {"status": "approved"}

def cancel_node(state: ApprovalState):
    return {"status": "rejected"}

builder = StateGraph(ApprovalState)
builder.add_node("approval", approval_node)
builder.add_node("proceed", proceed_node)
builder.add_node("cancel", cancel_node)
builder.add_edge(START, "approval")
builder.add_edge("proceed", END)
builder.add_edge("cancel", END)

graph = builder.compile(checkpointer=MemorySaver())

config = {"configurable": {"thread_id": "approval-123"}}
initial = graph.invoke(
    {"action_details": "Transfer $500", "status": "pending"}, config
)
print(initial["__interrupt__"])  # [Interrupt(value={'question': ..., 'details': ...})]

# Approve
resumed = graph.invoke(Command(resume=True), config)
print(resumed["status"])  # "approved"
```

### Review and edit state

Let humans review and modify LLM outputs before continuing.

```python
from langgraph.types import interrupt
from langgraph.checkpoint.memory import MemorySaver
from langgraph.graph import StateGraph, START, END

class ReviewState(TypedDict):
    generated_text: str

def review_node(state: ReviewState):
    updated = interrupt({
        "instruction": "Review and edit this content",
        "content": state["generated_text"],
    })
    return {"generated_text": updated}

builder = StateGraph(ReviewState)
builder.add_node("review", review_node)
builder.add_edge(START, "review")
builder.add_edge("review", END)

graph = builder.compile(checkpointer=MemorySaver())

config = {"configurable": {"thread_id": "review-42"}}
initial = graph.invoke({"generated_text": "Initial draft"}, config)
# [Interrupt(value={'instruction': ..., 'content': ...})]

final_state = graph.invoke(
    Command(resume="Improved draft after review"), config
)
print(final_state["generated_text"])  # "Improved draft after review"
```

### Interrupt inside a tool

Place `interrupt()` directly inside tool functions for per-call approval.

```python
import sqlite3
from langchain.tools import tool
from langchain_anthropic import ChatAnthropic
from langgraph.checkpoint.sqlite import SqliteSaver
from langgraph.graph import StateGraph, START, END
from langgraph.types import Command, interrupt

class AgentState(TypedDict):
    messages: list[dict]

@tool
def send_email(to: str, subject: str, body: str):
    """Send an email to a recipient."""
    # Pause before sending; payload surfaces in result["__interrupt__"]
    response = interrupt({
        "action": "send_email",
        "to": to,
        "subject": subject,
        "body": body,
        "message": "Approve sending this email?",
    })
    if response.get("action") == "approve":
        final_to = response.get("to", to)
        final_subject = response.get("subject", subject)
        final_body = response.get("body", body)
        print(f"[send_email] to={final_to} subject={final_subject}")
        return f"Email sent to {final_to}"
    return "Email cancelled by user"

model = ChatAnthropic(model="claude-sonnet-4-6").bind_tools([send_email])

def agent_node(state: AgentState):
    result = model.invoke(state["messages"])
    return {"messages": state["messages"] + [result]}

builder = StateGraph(AgentState)
builder.add_node("agent", agent_node)
builder.add_edge(START, "agent")
builder.add_edge("agent", END)

checkpointer = SqliteSaver(sqlite3.connect("tool-approval.db"))
graph = builder.compile(checkpointer=checkpointer)

config = {"configurable": {"thread_id": "email-workflow"}}
initial = graph.invoke(
    {"messages": [{"role": "user", "content": "Send an email to alice@example.com about the meeting"}]},
    config
)
print(initial["__interrupt__"])  # [Interrupt(value={'action': 'send_email', ...})]

# Resume with approval and optionally edited arguments
resumed = graph.invoke(
    Command(resume={"action": "approve", "subject": "Updated subject"}), config
)
```

### Validation loop

```python
from langgraph.types import interrupt
from langgraph.checkpoint.sqlite import SqliteSaver
from langgraph.graph import StateGraph, START, END

class FormState(TypedDict):
    age: int | None

def get_age_node(state: FormState):
    prompt = "What is your age?"
    while True:
        answer = interrupt(prompt)
        if isinstance(answer, int) and answer > 0:
            return {"age": answer}
        prompt = f"'{answer}' is not a valid age. Please enter a positive number."

builder = StateGraph(FormState)
builder.add_node("collect_age", get_age_node)
builder.add_edge(START, "collect_age")
builder.add_edge("collect_age", END)

checkpointer = SqliteSaver(sqlite3.connect("forms.db"))
graph = builder.compile(checkpointer=checkpointer)

config = {"configurable": {"thread_id": "form-1"}}
first = graph.invoke({"age": None}, config)
print(first["__interrupt__"])  # [Interrupt(value='What is your age?', ...)]

# Provide invalid data; the node re-prompts
retry = graph.invoke(Command(resume="thirty"), config)
print(retry["__interrupt__"])  # [Interrupt(value="'thirty' is not a valid age...", ...)]

# Provide valid data; loop exits and state updates
final = graph.invoke(Command(resume=30), config)
print(final["age"])  # 30
```

### Multiple parallel interrupts

When parallel branches each call `interrupt()`, resume by mapping interrupt IDs to values.
Source: `docs/interrupts.md`.

```python
from typing import Annotated
import operator

class State(TypedDict):
    vals: Annotated[list[str], operator.add]

def node_a(state):
    answer = interrupt("question_a")
    return {"vals": [f"a:{answer}"]}

def node_b(state):
    answer = interrupt("question_b")
    return {"vals": [f"b:{answer}"]}

graph = (
    StateGraph(State)
    .add_node("a", node_a)
    .add_node("b", node_b)
    .add_edge(START, "a")
    .add_edge(START, "b")
    .add_edge("a", END)
    .add_edge("b", END)
    .compile(checkpointer=InMemorySaver())
)

config = {"configurable": {"thread_id": "1"}}
interrupted_result = graph.invoke({"vals": []}, config)
# {'vals': [], '__interrupt__': [Interrupt(value='question_a', id='...'), Interrupt(value='question_b', id='...')]}

# Resume all pending interrupts at once using ID map
resume_map = {i.id: f"answer for {i.value}" for i in interrupted_result["__interrupt__"]}
result = graph.invoke(Command(resume=resume_map), config)
# {'vals': ['a:answer for question_a', 'b:answer for question_b']}
```

### HITL with streaming

```python
from langchain.messages import AIMessageChunk

async def run_with_hitl(graph, initial_input, config):
    while True:
        async for chunk in graph.astream(
            initial_input,
            stream_mode=["messages", "updates"],
            subgraphs=True,
            config=config,
            version="v2",
        ):
            if chunk["type"] == "messages":
                msg, _ = chunk["data"]
                if isinstance(msg, AIMessageChunk) and msg.content:
                    print(msg.content, end="", flush=True)

            elif chunk["type"] == "updates":
                if "__interrupt__" in chunk["data"]:
                    interrupt_info = chunk["data"]["__interrupt__"][0].value
                    user_response = input(f"\nHuman input needed: {interrupt_info}\n> ")
                    initial_input = Command(resume=user_response)
                    break  # restart the stream loop with the resume command
        else:
            break  # stream finished without interrupts
```

## Rules of interrupts

### Do NOT wrap in bare try/except

`interrupt()` pauses by raising a special exception. Catching it with a bare
`except Exception` suppresses the pause.

```python
# WRONG — catches the interrupt exception, preventing pause
def node_a(state: State):
    try:
        result = interrupt("question?")
    except Exception as e:
        print(e)    # this silently catches the interrupt signal
    return state

# CORRECT — catch specific exceptions only (never bare Exception)
def node_a(state: State):
    try:
        result = interrupt("question?")
        fetch_data()          # this can raise real errors
    except NetworkError:      # specific exception — does NOT catch interrupt
        handle_network_error()
    return {"result": result}

# ALSO CORRECT — separate interrupt from error-prone code
def node_a(state: State):
    result = interrupt("question?")   # no try/except here
    try:
        fetch_data()
    except Exception as e:
        print(e)
    return {"result": result}
```

### Do NOT reorder interrupt calls within a node

Matching is strictly index-based. Conditionally skipping or reordering calls
between the first run and a resume causes mis-routing.

```python
# WRONG — conditional interrupt changes call order on resume
def node_a(state: State):
    name = interrupt("What's your name?")
    if state.get("needs_age"):         # might be True on first run, False on resume
        age = interrupt("What's your age?")
    city = interrupt("What's your city?")
    return {"name": name, "city": city}

# CORRECT — stable order every run
def node_a(state: State):
    name = interrupt("What's your name?")
    age = interrupt("What's your age?")    # always called, even if result unused
    city = interrupt("What's your city?")
    return {"name": name, "age": age, "city": city}
```

### Payloads must be JSON-serializable

No functions, class instances, file handles, or other non-serializable objects.
Pass dicts with primitive values.

```python
# WRONG — function is not serializable
response = interrupt({
    "question": "What's your name?",
    "validator": validate_input      # will fail at checkpoint time
})

# CORRECT — primitive types only
response = interrupt({
    "question": "What's your name?",
    "min_length": 2,
    "max_length": 50,
})
```

### Pre-interrupt side effects must be idempotent

The node re-runs from its beginning on every resume. Operations before `interrupt()`
run again. Options:

```python
# Option 1: use upsert instead of insert (idempotent)
def node_a(state: State):
    db.upsert_user(user_id=state["user_id"], status="pending_approval")  # safe to re-run
    approved = interrupt("Approve this change?")
    return {"approved": approved}

# Option 2: place side effects AFTER the interrupt
def node_a(state: State):
    approved = interrupt("Approve this change?")
    if approved:
        db.create_audit_log(user_id=state["user_id"], action="approved")  # only runs once
    return {"approved": approved}

# Option 3: separate side effects into a different node
def approval_node(state: State):
    approved = interrupt("Approve?")
    return {"approved": approved}

def notification_node(state: State):
    if state["approved"]:
        send_notification(user_id=state["user_id"])
    return state
```

## Static breakpoints (debugging only)

```python
# At compile time
graph = builder.compile(
    interrupt_before=["node_a"],
    interrupt_after=["node_b", "node_c"],
    checkpointer=checkpointer,
)

config = {"configurable": {"thread_id": "some_thread"}}

# Run until first breakpoint
graph.invoke(inputs, config=config)

# Resume until next breakpoint
graph.invoke(None, config=config)

# At run time (overrides compile-time settings)
graph.invoke(inputs, interrupt_before=["node_a"], config=config)
graph.invoke(None, config=config)
```

Static breakpoints are for debugging — not recommended for production HITL workflows.
Use `interrupt()` instead for production.

## Subgraphs and interrupts

When a subgraph contains an interrupt, the parent resumes from the beginning of the
node that invoked the subgraph (not from the interrupt line). The subgraph also resumes
from its own node's beginning.

```python
def node_in_parent_graph(state: State):
    some_code()           # <-- re-executes when resumed
    subgraph_result = subgraph.invoke(some_input)  # subgraph has interrupt inside
    # ...

def node_in_subgraph(state: State):
    some_other_code()     # <-- also re-executes when resumed
    result = interrupt("What's your name?")
    # ...
```
