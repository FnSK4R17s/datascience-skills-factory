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

When to use Graph API:
- Complex decision trees with multiple decision points
- Explicit state shared across many nodes
- Parallel execution paths that merge later
- Team collaboration where visual graph aids understanding

When to use Functional API:
- Minimal changes to existing procedural code
- Standard Python control flow (if/else, loops, function calls)
- Function-scoped state without explicit state management
- Rapid prototyping

## `@entrypoint`

The `@entrypoint` decorator marks a function as the starting point of a workflow.
Decorating produces a `Pregel` instance with `invoke`, `ainvoke`, `stream`, `astream`.

```python
from langgraph.func import entrypoint
from langgraph.checkpoint.memory import InMemorySaver

@entrypoint(checkpointer=InMemorySaver())
def my_workflow(inputs: dict) -> dict:
    # inputs must be JSON-serializable
    result = some_task(inputs["x"]).result()
    return {"output": result}

config = {"configurable": {"thread_id": "t1"}}
my_workflow.invoke({"x": 5}, config)
await my_workflow.ainvoke({"x": 5}, config)
for chunk in my_workflow.stream({"x": 5}, config): ...
async for chunk in my_workflow.astream({"x": 5}, config): ...
```

The function **must accept a single positional argument** as workflow input.
If you need multiple inputs, use a dictionary.

### Injectable parameters

Declare these as keyword-only args; LangGraph injects them automatically:

| Parameter | Type | Purpose |
|-----------|------|---------|
| `previous` | `Any` | Return value from last invocation on this thread |
| `store` | `BaseStore` | Long-term cross-thread memory |
| `writer` | `StreamWriter` | Custom streaming (Python < 3.11 async) |
| `config` | `RunnableConfig` | Runtime configuration |

```python
from langchain_core.runnables import RunnableConfig
from langgraph.store.base import BaseStore
from langgraph.types import StreamWriter

@entrypoint(checkpointer=ckpt, store=store)
def workflow(
    inputs,
    *,
    previous=None,
    store: BaseStore,
    writer: StreamWriter,
    config: RunnableConfig
):
    thread_id = config["configurable"]["thread_id"]
    # previous is the return value from the last invocation on this thread
    ...
```

### Short-term memory (`previous`)

`previous` gives access to the return value of the prior invocation on the same thread.

```python
@entrypoint(checkpointer=checkpointer)
def counter(n: int, *, previous: int = 0) -> int:
    return n + previous

config = {"configurable": {"thread_id": "t1"}}
counter.invoke(1, config)  # 1 (previous was None → 0)
counter.invoke(2, config)  # 3 (previous was 1)
counter.invoke(5, config)  # 8 (previous was 3)
```

### `entrypoint.final` — decouple return from saved value

Return something different to the caller vs what gets saved for the next `previous`:

```python
@entrypoint(checkpointer=ckpt)
def wf(n: int, *, previous=None) -> entrypoint.final[int, int]:
    # Caller receives `previous or 0`; checkpoint stores `n * 2`
    return entrypoint.final(value=previous or 0, save=n * 2)

config = {"configurable": {"thread_id": "1"}}
wf.invoke(3, config)  # Returns: 0 (previous was None), saves: 6
wf.invoke(1, config)  # Returns: 6 (previous was 6), saves: 2
```

Type annotation: `entrypoint.final[return_type, save_type]`

## `@task`

`@task` represents a discrete unit of work. Key characteristics:
- Returns immediately with a future-like object
- Call `.result()` to get value synchronously, or `await` for async
- Results are checkpointed — not re-computed on resume
- Must only be called from within an `@entrypoint`, another `@task`, or a graph node

```python
from langgraph.func import task

@task
def fetch_data(url: str) -> str:
    return requests.get(url).text

@task
async def async_fetch(url: str) -> str:
    async with aiohttp.ClientSession() as s:
        async with s.get(url) as r:
            return await r.text()
```

### Parallel execution with tasks

Tasks launched before calling `.result()` run concurrently:

```python
@entrypoint(checkpointer=ckpt)
def workflow(inputs):
    # Launch both fetches concurrently
    f1 = fetch_data(inputs["url1"])
    f2 = fetch_data(inputs["url2"])
    # Both are running in parallel; .result() blocks until each finishes
    return {"a": f1.result(), "b": f2.result()}
```

## Full working examples

### Essay review with HITL (from docs)

Source: `docs/functional-api.md`

```python
import time
from langgraph.func import entrypoint, task
from langgraph.types import interrupt, Command
from langgraph.checkpoint.memory import InMemorySaver

@task
def write_essay(topic: str) -> str:
    """Write an essay about the given topic."""
    time.sleep(1)   # Simulate long-running task
    return f"An essay about topic: {topic}"

@entrypoint(checkpointer=InMemorySaver())
def workflow(topic: str) -> dict:
    """Write an essay and ask for human review."""
    essay = write_essay("cat").result()
    is_approved = interrupt({
        "essay": essay,
        "action": "Please approve/reject the essay",
    })
    return {
        "essay": essay,
        "is_approved": is_approved,
    }

config = {"configurable": {"thread_id": "essay-1"}}

# First run — writes essay, then interrupts
for item in workflow.stream("cat", config):
    print(item)
# > {'write_essay': 'An essay about topic: cat'}
# > {'__interrupt__': (Interrupt(value={'essay': ..., 'action': ...}, id='...'),)}

# Resume with human review
human_review = True
for item in workflow.stream(Command(resume=human_review), config):
    print(item)
# > {'workflow': {'essay': 'An essay about topic: cat', 'is_approved': True}}
```

### Resuming after error

```python
# After fixing the underlying issue (e.g. LLM timeout)
my_workflow.invoke(None, config)   # resumes from last checkpoint
```

### Interrupts in tasks

Works identically to the Graph API:

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

config = {"configurable": {"thread_id": "review-1"}}
result = review_workflow.invoke("cats", config)
# result contains __interrupt__ key

review_workflow.invoke(Command(resume=True), config)
```

## Serialization requirements

Both `@entrypoint` inputs/outputs and `@task` outputs must be JSON-serializable.
Use primitive types: dicts, lists, strings, numbers, booleans.

```python
# CORRECT — primitive types
@task
def fetch_data(url: str) -> dict:       # dict with primitives
    return {"text": requests.get(url).text, "status": 200}

# WRONG — non-serializable type
@task
def get_response(url: str) -> requests.Response:   # Response not JSON-serializable
    return requests.get(url)   # will fail when checkpointer tries to save
```

## Determinism rules

On resume, the entrypoint re-runs from the beginning. Task results already in the
checkpoint are retrieved rather than re-executed. For this to work:

1. Wrap all non-deterministic operations (`random`, `time.time()`) in `@task`.
2. Keep `interrupt()` call order identical across the initial run and resume.
3. Wrap side effects (file writes, API calls) in `@task` — not bare code in the entrypoint body.

### Side effects — wrong vs correct

```python
# WRONG — file write runs again on resume (entrypoint body re-executes)
@entrypoint(checkpointer=checkpointer)
def my_workflow(inputs: dict) -> int:
    with open("output.txt", "w") as f:
        f.write("Side effect executed")    # runs TWICE if interrupted and resumed
    value = interrupt("question")
    return value

# CORRECT — file write wrapped in task; result replayed from checkpoint on resume
@task
def write_to_file():
    with open("output.txt", "w") as f:
        f.write("Side effect executed")

@entrypoint(checkpointer=checkpointer)
def my_workflow(inputs: dict) -> int:
    write_to_file().result()              # checkpointed; not re-run on resume
    value = interrupt("question")
    return value
```

### Non-deterministic control flow — wrong vs correct

```python
# WRONG — time.time() in entrypoint body gives different value on resume
@entrypoint(checkpointer=checkpointer)
def my_workflow(inputs: dict) -> int:
    t1 = time.time()   # different value on first run vs resume!
    if t1 - inputs["t0"] > 1:
        result = slow_task(1).result()
        value = interrupt("question")
    else:
        result = slow_task(2).result()
        value = interrupt("question")
    return {"result": result, "value": value}

# CORRECT — time.time() in task; same result replayed on resume
@task
def get_time() -> float:
    return time.time()

@entrypoint(checkpointer=checkpointer)
def my_workflow(inputs: dict) -> int:
    t1 = get_time().result()    # result saved to checkpoint; same on resume
    if t1 - inputs["t0"] > 1:
        result = slow_task(1).result()
        value = interrupt("question")
    else:
        result = slow_task(2).result()
        value = interrupt("question")
    return {"result": result, "value": value}
```

## Idempotency

If a `@task` starts but fails before completing, it is re-run on resume. Design tasks
to tolerate re-execution:
- Upsert (not insert) database records.
- Use idempotency keys on external API calls.
- Check for existing results before creating new ones.

## When to use a `@task`

Use tasks when you need:
- **Checkpointing**: save result of long-running op; avoid recomputing on resume
- **HITL**: any randomness in a HITL workflow MUST be in tasks for correct index matching
- **Parallel execution**: I/O-bound tasks run concurrently without blocking
- **Observability**: task execution is tracked in LangSmith with start/finish events
- **Retryable work**: tasks encapsulate retry logic for failed operations
