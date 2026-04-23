# Functional API Reference

Source: `docs/functional-api.md`, `docs/use-functional-api.md`, `docs/choosing-apis.md`

## Purpose

Add persistence, memory, HITL, and streaming to existing Python code with minimal
restructuring. No explicit state schema or edge declarations needed. Uses standard
Python control flow (if/else, loops, function calls).

Both APIs share the same runtime (`Pregel`). Mix freely in one application.

## API vs Graph API

| Feature | Graph API | Functional API |
|---------|-----------|----------------|
| Control flow | Nodes + edges (explicit) | Standard Python (implicit) |
| State | Shared TypedDict/Pydantic | Function-scoped; `previous` for persistence |
| Visualization | Supported | Not supported (dynamic at runtime) |
| Checkpointing | After every super-step | Task results saved within same checkpoint |
| Boilerplate | More explicit | Minimal |
| Best for | Complex branching, fan-out, visual design | Linear workflows, rapid iteration |

## `@entrypoint`

```python
from langgraph.func import entrypoint
from langgraph.checkpoint.memory import InMemorySaver

@entrypoint(checkpointer=InMemorySaver())
def my_workflow(inputs: dict) -> dict:
    # inputs must be JSON-serializable
    result = slow_task(inputs["x"]).result()
    return {"output": result}
```

Decorating produces a `Pregel` instance. Call with `invoke`, `ainvoke`, `stream`, or
`astream`.

```python
config = {"configurable": {"thread_id": "t1"}}
my_workflow.invoke({"x": 5}, config)
await my_workflow.ainvoke({"x": 5}, config)
for chunk in my_workflow.stream({"x": 5}, config): ...
```

### Injectable parameters

Declare these as keyword-only args; LangGraph injects them automatically:

| Parameter | Type | Purpose |
|-----------|------|---------|
| `previous` | `Any` | Return value from last invocation on this thread |
| `store` | `BaseStore` | Long-term cross-thread memory |
| `writer` | `StreamWriter` | Custom streaming (Python < 3.11 async) |
| `config` | `RunnableConfig` | Runtime configuration |

```python
@entrypoint(checkpointer=ckpt, store=store)
def workflow(inputs, *, previous=None, store: BaseStore, writer: StreamWriter, config):
    ...
```

### Short-term memory (`previous`)

```python
@entrypoint(checkpointer=checkpointer)
def counter(n: int, *, previous: int = 0) -> int:
    return n + previous

counter.invoke(1, config)  # 1
counter.invoke(2, config)  # 3 (previous = 1)
```

### `entrypoint.final` — decouple return from saved value

```python
@entrypoint(checkpointer=ckpt)
def wf(n: int, *, previous=None) -> entrypoint.final[int, int]:
    return entrypoint.final(value=previous or 0, save=n * 2)
    # Caller receives `previous`, checkpoint stores `n*2`
```

## `@task`

```python
from langgraph.func import task

@task
def fetch_data(url: str) -> str:
    return requests.get(url).text
```

- Returns immediately with a future-like object.
- Call `.result()` to get the value (sync) or `await` (async).
- Results are checkpointed — not re-computed on resume.
- Can only be called from within an `@entrypoint`, another `@task`, or a graph node.
  **Never call directly from application code.**

```python
@entrypoint(checkpointer=ckpt)
def workflow(inputs):
    # Parallel execution
    f1 = fetch_data(inputs["url1"])
    f2 = fetch_data(inputs["url2"])
    return {"a": f1.result(), "b": f2.result()}
```

## Resuming after error

Re-invoke with `None` and the same thread ID after fixing the underlying issue:

```python
my_workflow.invoke(None, config)   # resumes from last checkpoint
```

## Interrupts in the Functional API

Works identically to the Graph API — call `interrupt()` inside `@task` or the
entrypoint function:

```python
from langgraph.types import interrupt, Command

@task
def check_with_human(draft: str) -> bool:
    return interrupt({"draft": draft, "action": "approve?"})

@entrypoint(checkpointer=ckpt)
def review_workflow(topic: str) -> dict:
    essay = write_essay(topic).result()
    approved = check_with_human(essay).result()
    return {"essay": essay, "approved": approved}
```

Resume: `review_workflow.invoke(Command(resume=True), config)`

## Serialization requirements

Both `@entrypoint` inputs/outputs and `@task` outputs must be JSON-serializable.
Use primitive types: dicts, lists, strings, numbers, booleans.
Non-serializable types cause a runtime error when a checkpointer is configured.

## Determinism rules

When resuming, the entrypoint re-runs from the beginning. Task results that were
already computed are retrieved from the checkpoint rather than re-executed. For this
to work correctly:

1. Wrap all non-deterministic operations (random, `time.time()`) in `@task`.
2. Keep `interrupt()` call order identical across the initial run and resume.
3. Wrap side effects (file writes, API calls) in `@task` — not bare code in the
   entrypoint body.

```python
# WRONG — time.time() in entrypoint body changes on resume
@entrypoint(checkpointer=ckpt)
def wf(inputs):
    t = time.time()     # different value on resume

# CORRECT — time.time() in task, result replayed on resume
@task
def get_time() -> float:
    return time.time()

@entrypoint(checkpointer=ckpt)
def wf(inputs):
    t = get_time().result()
```

## Idempotency

If a `@task` starts but fails before completing, it is re-run on resume. Design tasks
to be idempotent (upsert instead of insert, check-before-create) to avoid duplication.
