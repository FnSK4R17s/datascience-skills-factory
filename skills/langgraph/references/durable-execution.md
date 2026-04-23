# Durable Execution Reference

Source: `docs/durable-execution.md`, `docs/functional-api.md`

## What it is

Durable execution means a workflow saves its progress at key points so it can
resume exactly where it left off after a failure, a long pause, or a human review.
LangGraph provides this via checkpointers — any graph compiled with a checkpointer
gets durable execution for free.

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

```python
from langgraph.func import task, entrypoint

@task
def call_api(url: str) -> str:          # safe to replay — result cached
    return requests.get(url).text

@entrypoint(checkpointer=checkpointer)
def workflow(inputs: dict) -> dict:
    # call_api result is retrieved from checkpoint on resume, not re-fetched
    data = call_api(inputs["url"]).result()
    human_ok = interrupt("Approve?")
    return {"data": data, "approved": human_ok}
```

## Using tasks inside Graph API nodes

Tasks work inside graph nodes too — useful when a node has multiple side effects:

```python
from langgraph.func import task
from langgraph.graph import StateGraph

@task
def fetch(url: str) -> str:
    return requests.get(url).text

def multi_fetch_node(state):
    futures = [fetch(url) for url in state["urls"]]
    return {"results": [f.result() for f in futures]}  # parallel + durable
```

## Durability modes

Control when checkpoints are written:

```python
graph.stream(inputs, durability="sync")   # write before next step starts (most durable)
graph.stream(inputs, durability="async")  # write in background (good balance)
graph.stream(inputs, durability="exit")   # write only on graph exit (best performance)
```

| Mode | When checkpoint is written | Recovery guarantee |
|------|--------------------------|-------------------|
| `sync` | Before each step | Every step; most overhead |
| `async` | Async while next step runs | Small window of loss on crash |
| `exit` | On complete / error / interrupt | Only at graph boundaries |

## Recovering from failures

After a transient failure (LLM timeout, network error), resume with the same thread ID
and pass `None` as input:

```python
# After fixing the underlying issue
graph.invoke(None, config)
```

The graph restarts from the last successful checkpoint and skips already-completed steps.

## Idempotency

If a `@task` starts but crashes before returning, it is re-run on resume. Design tasks
to tolerate re-execution:
- Upsert (not insert) database records.
- Use idempotency keys on external API calls.
- Check for existing results before creating new ones.
