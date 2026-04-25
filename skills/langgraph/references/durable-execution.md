# Durable Execution Reference

Source: `docs/durable-execution.md`, `docs/functional-api.md`

## What it is

Durable execution means a workflow saves its progress at key points so it can
resume exactly where it left off after a failure, a long pause, or a human review.
LangGraph provides this via checkpointers — any graph compiled with a checkpointer
gets durable execution for free.

> If you are using LangGraph with a checkpointer, you already have durable execution
> enabled. You can pause and resume workflows at any point, even after interruptions
> or failures. Source: `docs/durable-execution.md`.

## Requirements

1. A checkpointer attached at `compile()`.
2. A `thread_id` in `config["configurable"]` for every invocation.
3. Non-deterministic operations and side effects wrapped in `@task` nodes.

## Resumption starting points

| API | Resume starts at |
|-----|-----------------|
| Graph API (`StateGraph`) | Beginning of the **node** where execution stopped |
| Functional API (`@entrypoint`) | Beginning of the **entrypoint** function |
| Subgraph inside a node | Beginning of the **parent node** that called the subgraph |

The code path replays from that point — it does NOT resume from the exact line
where it stopped.

## Determinism and consistent replay

On resume, all code in the starting point re-runs. To prevent side effects from
running twice:
- Wrap API calls, file writes, random values, and `time.time()` in `@task`.
- Task results already in the checkpoint are retrieved — not re-executed.
- Keep `interrupt()` call order stable across runs (index-based matching).

### Basic pattern — functional API

Source: `docs/durable-execution.md`

```python
from langgraph.func import task, entrypoint
from langgraph.checkpoint.memory import InMemorySaver

@task
def call_api(url: str) -> str:          # safe to replay — result cached
    return requests.get(url).text

@entrypoint(checkpointer=InMemorySaver())
def workflow(inputs: dict) -> dict:
    # call_api result is retrieved from checkpoint on resume, not re-fetched
    data = call_api(inputs["url"]).result()
    human_ok = interrupt("Approve?")
    return {"data": data, "approved": human_ok}

config = {"configurable": {"thread_id": "wf-1"}}
result = workflow.invoke({"url": "https://example.com"}, config)
# Hits interrupt — saves checkpoint with `data` already computed

# Resume: call_api is NOT re-fetched; result comes from checkpoint
workflow.invoke(Command(resume=True), config)
```

### Node refactoring example — Graph API

When a node has multiple operations that should be durable individually:

```python
# Before — entire node re-runs if interrupted mid-way
from typing import NotRequired
from typing_extensions import TypedDict
from langgraph.graph import StateGraph, START, END
from langgraph.checkpoint.memory import InMemorySaver
import requests

class State(TypedDict):
    urls: list[str]
    results: NotRequired[list[str]]

def call_api(state: State):
    """Makes API requests — no durability for individual calls."""
    results = [requests.get(url).text[:100] for url in state["urls"]]
    return {"results": results}

# After — each API call is a task; checkpointed individually
from langgraph.func import task

@task
def _make_request(url: str) -> str:
    """Each request is checkpointed separately."""
    return requests.get(url).text[:100]

def call_api_durable(state: State):
    """All requests run in parallel and are individually durable."""
    futures = [_make_request(url) for url in state["urls"]]
    return {"results": [f.result() for f in futures]}

checkpointer = InMemorySaver()
builder = StateGraph(State)
builder.add_node("call_api", call_api_durable)
builder.add_edge(START, "call_api")
builder.add_edge("call_api", END)
graph = builder.compile(checkpointer=checkpointer)

config = {"configurable": {"thread_id": "api-run-1"}}
graph.invoke({"urls": ["https://example.com", "https://httpbin.org/get"]}, config)
```

## Durability modes

Control when checkpoints are written — balance performance vs recovery guarantee.

```python
# Default mode varies by implementation; set explicitly for predictable behavior
graph.stream(inputs, durability="sync")    # write before next step starts
graph.stream(inputs, durability="async")   # write while next step runs
graph.stream(inputs, durability="exit")    # write only on graph exit/error/interrupt
```

| Mode | When checkpoint is written | Recovery guarantee |
|------|--------------------------|-------------------|
| `exit` | On complete / error / interrupt | Only at graph boundaries; best performance |
| `async` | Async while next step runs | Small window of loss on crash |
| `sync` | Before each step | Every step; most overhead; most durable |

Choose `sync` for financial workflows, medical data, or any case where losing a
single step is unacceptable. Choose `async` for most production workloads. Choose
`exit` for long-running processes where intermediate state is not important.

## Recovering from failures

After a transient failure (LLM timeout, network error), resume with the same thread
ID and pass `None` as input:

```python
# After fixing the underlying issue (e.g., service came back online)
graph.invoke(None, config)   # Graph API
my_workflow.invoke(None, config)  # Functional API
```

The graph restarts from the last successful checkpoint and skips already-completed steps.

## Idempotency

If a `@task` starts but crashes before returning, it is re-run on resume. Design
tasks to tolerate re-execution:

```python
# WRONG — insert creates duplicates on retry
@task
def save_record(data: dict) -> str:
    record_id = db.insert(data)   # creates new record every time; fails on retry
    return record_id

# CORRECT — upsert is idempotent
@task
def save_record(data: dict) -> str:
    record_id = data["id"]
    db.upsert(record_id, data)    # same result whether run once or many times
    return record_id

# CORRECT — idempotency key on external API
@task
def charge_customer(amount: float, idempotency_key: str) -> str:
    response = payment_api.charge(
        amount=amount,
        idempotency_key=idempotency_key   # API deduplicates if retried
    )
    return response.transaction_id

# CORRECT — check before creating
@task
def send_welcome_email(user_id: str) -> bool:
    if email_log.has_sent(user_id, "welcome"):
        return True   # already sent; skip
    email_service.send_welcome(user_id)
    email_log.record(user_id, "welcome")
    return True
```

## Pending writes — sibling node protection

When a graph node fails mid-execution in a given super-step, LangGraph stores
pending checkpoint writes from any other nodes that completed successfully in that
step. When you resume, the successful sibling nodes are NOT re-run.

This means in a parallel fan-out:
- node_a completes (writes to state, checkpointed)
- node_b fails (exception raised)
- On resume: node_a result is preserved; only node_b re-runs
