# Functional API

Source: `docs/functional-api.md`, `docs/use-functional-api.md`, `docs/choosing-apis.md`

## Purpose

Adds LangGraph persistence, memory, human-in-the-loop, and streaming to
existing Python code with minimal restructuring. Uses standard control flow
(if/else, for loops, function calls) instead of explicit graph topology.

Both APIs share the same runtime; mix them freely in one application.

## When to choose Functional API over Graph API

- Existing procedural code that would require significant refactoring to
  become a graph.
- Linear or simply branching workflows.
- Function-scoped state (no shared TypedDict across many nodes).
- Rapid prototyping with less boilerplate.

Choose Graph API when you need visualization, explicit shared state across many
nodes, or complex fan-out patterns. Source: `docs/choosing-apis.md`.

## @entrypoint

Marks a function as the workflow starting point. Produces a `Pregel` instance
with `invoke`, `ainvoke`, `stream`, `astream` methods.

```python
from langgraph.func import entrypoint
from langgraph.checkpoint.memory import InMemorySaver

@entrypoint(checkpointer=InMemorySaver())
def my_workflow(input_data: dict) -> dict:
    # standard Python: loops, conditionals, function calls
    ...
    return result
```

Rules:
- First argument is the workflow input (single positional arg; use a dict for
  multiple fields).
- Inputs and outputs must be JSON-serializable (required for checkpointing).
- Produces the same `invoke`/`stream` interface as a compiled `StateGraph`.

Source: `docs/functional-api.md`.

## @task

Wraps a discrete unit of work. Tasks:
- Are executed asynchronously (return a future immediately).
- Checkpoint their results — on resume, completed task results are loaded from
  the checkpoint rather than re-run.
- Can run in parallel when multiple futures are created before `.result()`.

```python
from langgraph.func import task

@task
def fetch_data(query: str) -> dict:
    # API call, DB lookup, etc.
    return {"result": ...}

@entrypoint(checkpointer=InMemorySaver())
def workflow(input: dict) -> dict:
    future = fetch_data(input["query"])   # returns immediately
    data = future.result()                # blocks until done
    return data
```

Tasks **cannot** be called from application code directly — only from within
an `@entrypoint`, another `@task`, or a graph node. Source: `docs/functional-api.md`.

## Parallel task execution

```python
@entrypoint(checkpointer=InMemorySaver())
async def workflow(items: list) -> list:
    futures = [process_item(x) for x in items]   # all start immediately
    return [await f for f in futures]              # wait for all
```

## Short-term memory (previous)

When a checkpointer is attached, the `previous` injectable parameter gives
access to the return value of the prior invocation on the same thread:

```python
@entrypoint(checkpointer=checkpointer)
def my_workflow(number: int, *, previous: int | None = None) -> int:
    return number + (previous or 0)

config = {"configurable": {"thread_id": "t1"}}
my_workflow.invoke(1, config)  # returns 1
my_workflow.invoke(2, config)  # returns 3 (previous=1)
```

Use `entrypoint.final` to decouple the return value from what is saved to the
checkpoint:
```python
@entrypoint(checkpointer=checkpointer)
def workflow(n: int, *, previous: int | None = None) -> entrypoint.final[int, int]:
    prev = previous or 0
    return entrypoint.final(value=prev, save=2 * n)  # saves 2*n but returns prev
```

Source: `docs/functional-api.md`.

## Injectable parameters

Declare as keyword-only arguments in the entrypoint function signature:

| Parameter | Type | Description |
|-----------|------|-------------|
| `previous` | Any | Return value of the prior invocation on this thread |
| `store` | `BaseStore` | Cross-thread long-term memory store |
| `writer` | `StreamWriter` | Custom stream writer (needed for async Python < 3.11) |
| `config` | `RunnableConfig` | Runtime configuration |

Source: `docs/functional-api.md`.

## Determinism requirement

Any randomness or non-determinism (API calls, `time.time()`, `random()`) must
live inside a `@task` so its result is checkpointed. On resume, the checkpointed
value is returned rather than re-running the task:

- In a task: `random()` returns 5 → interrupt → resume → 5 again (from checkpoint).
- Not in a task: `random()` returns 5 → interrupt → resume → `random()` runs again, returns 7.

If `interrupt()` call order changes between the original run and the resume
(because non-deterministic code changed which branch was taken), resume values
are mis-matched. Always encapsulate non-determinism in tasks. Source: `docs/functional-api.md`.

## Side effects

Wrap side effects (file writes, emails, DB inserts) in `@task` to prevent
re-execution on resume:

```python
# Wrong: file write happens again on resume
@entrypoint(checkpointer=checkpointer)
def workflow(inputs: dict):
    with open("out.txt", "w") as f:
        f.write("data")
    value = interrupt("approve?")

# Correct: task result is checkpointed; write skipped on resume
@task
def write_file():
    with open("out.txt", "w") as f:
        f.write("data")

@entrypoint(checkpointer=checkpointer)
def workflow(inputs: dict):
    write_file().result()
    value = interrupt("approve?")
```

Source: `docs/functional-api.md`.

## Differences from Graph API

| Concern | Graph API | Functional API |
|---------|-----------|----------------|
| Control flow | Explicit nodes + edges | Python `if`/`for`/calls |
| State | Shared TypedDict with reducers | Function arguments and return values |
| Checkpoints | After every super-step boundary | Task results saved to current checkpoint |
| Visualization | `graph.get_graph().draw_mermaid_png()` | Not supported (dynamic) |

Source: `docs/functional-api.md`.
