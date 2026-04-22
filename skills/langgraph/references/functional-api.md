# Functional API

The Functional API adds LangGraph's persistence, streaming, interrupts, and
memory to ordinary Python functions with minimal restructuring. Use it when
your workflow is naturally procedural and you do not need an explicit graph.

## Core primitives

```python
from langgraph.func import entrypoint, task
from langgraph.types import interrupt
from langgraph.checkpoint.memory import InMemorySaver

@task
def fetch_data(query: str) -> dict:
    # Discrete unit of work. Result is saved to a checkpoint.
    # Calling this returns a future; call .result() to get the value.
    return {"data": f"results for {query}"}

@entrypoint(checkpointer=InMemorySaver())
def workflow(query: str) -> dict:
    data = fetch_data(query).result()   # tasks called inside entrypoint
    approved = interrupt({"data": data, "action": "Approve?"})
    return {"data": data, "approved": approved}
```

- `@task` makes a function cacheable and checkpointable. Its result is
  persisted so it is not re-executed when the entrypoint resumes after
  an interrupt.
- `@entrypoint` is the outer workflow boundary. It behaves like a compiled
  graph — you call `.invoke()`, `.stream()`, `.astream()` on it.

## Invocation and config

```python
config = {"configurable": {"thread_id": "run-1"}}
result = workflow.invoke("my query", config=config)

# Resume after interrupt
from langgraph.types import Command
result = workflow.invoke(Command(resume=True), config=config)
```

Same config contract as StateGraph: `thread_id` inside `configurable`.

## State management differences vs. Graph API

| Concern | Graph API | Functional API |
|---------|-----------|----------------|
| State schema | Explicit `TypedDict` / Pydantic | None required |
| State sharing | All nodes see shared state dict | Values passed as function args |
| Checkpointing | New checkpoint per superstep | Task results saved to current checkpoint |
| Visualisation | `.get_graph().draw_*()` | Not available (dynamic) |

The Functional API scopes state to function return values. There is no shared
state dict. Tasks and entrypoints communicate by passing values explicitly.

## When to choose Functional API

- You have existing procedural code and want to add checkpointing with minimal
  refactoring.
- Your workflow is primarily sequential with simple `if/else` branching.
- You want rapid prototyping without declaring a state schema.
- You do not need graph visualisation.

## When to stay on Graph API

- Your workflow has complex conditional branching with many decision points.
- You need parallel execution paths that merge (fan-out / fan-in).
- You need the graph to be visualisable for documentation or debugging.
- Multiple parts of your graph need to read/write shared state keys.
- You are building a multi-agent system with explicit subgraph handoffs.

## Mixing both APIs

The two APIs share the same runtime and can compose:

```python
@entrypoint()
def data_processor(raw: dict) -> dict:
    cleaned = clean(raw).result()
    return transform(cleaned).result()

# Use as a node in a StateGraph
def orchestrator_node(state: State):
    return {"output": data_processor.invoke(state["raw"])}
```

## Async tasks

```python
@task
async def fetch_async(url: str) -> str:
    async with httpx.AsyncClient() as client:
        r = await client.get(url)
        return r.text

@entrypoint(checkpointer=checkpointer)
async def async_workflow(url: str) -> dict:
    content = await fetch_async(url)   # await task future directly
    return {"content": content}
```

## Streaming

The entrypoint supports the same streaming interface as StateGraph:

```python
for chunk in workflow.stream("my query", config=config, stream_mode="custom", version="v2"):
    if chunk["type"] == "custom":
        print(chunk["data"])
```
