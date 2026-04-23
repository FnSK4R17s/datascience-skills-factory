# Persistence

Source: `docs/persistence.md`

## Why persistence

A **checkpointer** saves a snapshot of graph state at every super-step. This
enables:
- **Human-in-the-loop** — inspect/modify state, resume after interrupt.
- **Conversation memory** — state accumulates across calls on the same thread.
- **Time travel** — replay or fork from any checkpoint.
- **Fault tolerance** — resume from the last successful step after a node failure.
  Pending writes from other nodes that completed in the same super-step are preserved
  so those nodes do not re-run on resume.

## Threads

A thread is identified by a `thread_id`. Every invocation with a checkpointer
**must** include it:

```python
config = {"configurable": {"thread_id": "my-thread-1"}}
graph.invoke(inputs, config)
```

The checkpointer uses `thread_id` as the primary key. Without it, `interrupt()`
cannot be resumed and state cannot be loaded. Source: `docs/persistence.md`.

## Compiling with a checkpointer

```python
from langgraph.checkpoint.memory import InMemorySaver

checkpointer = InMemorySaver()
graph = builder.compile(checkpointer=checkpointer)
```

`InMemorySaver` is for development/testing only. Use a persistent backend for
production. Source: `docs/persistence.md`.

## Checkpointer libraries

| Package | Class | Use case |
|---------|-------|----------|
| `langgraph` (built-in) | `InMemorySaver` | Dev / testing |
| `langgraph-checkpoint-sqlite` | `SqliteSaver` / `AsyncSqliteSaver` | Local / lightweight prod |
| `langgraph-checkpoint-postgres` | `PostgresSaver` / `AsyncPostgresSaver` | Production (used by LangSmith) |
| `langgraph-checkpoint-cosmosdb` | `CosmosDBSaver` / `AsyncCosmosDBSaver` | Azure production |

For async graph execution (`ainvoke`, `astream`) use an async-capable checkpointer.
Source: `docs/persistence.md`.

## Reading state

```python
# Latest snapshot for a thread
snapshot = graph.get_state({"configurable": {"thread_id": "1"}})
# snapshot.values  — state dict
# snapshot.next    — tuple of node names to execute next; () means done
# snapshot.metadata["step"]  — super-step counter

# Full history (newest first)
history = list(graph.get_state_history({"configurable": {"thread_id": "1"}}))
```

Filter history to find specific checkpoints:
```python
# Checkpoint just before node_b ran
before_b = next(s for s in history if s.next == ("node_b",))

# Checkpoint created by an interrupt
interrupted = next(
    s for s in history
    if s.tasks and any(t.interrupts for t in s.tasks)
)
```
Source: `docs/persistence.md`.

## Updating state externally

`update_state` creates a new checkpoint with edited values. Updates go through
reducers (channels with `operator.add` reducers **accumulate**, not overwrite).
Use `as_node` to control which node the update is attributed to, which affects
which node runs next:

```python
graph.update_state(config, {"foo": "new_value"}, as_node="node_a")
```

Source: `docs/persistence.md`.

## Checkpoint namespace

The `checkpoint_ns` field in config identifies which graph a checkpoint belongs to:
- `""` — root/parent graph.
- `"node_name:uuid"` — subgraph. Nested: `"outer:uuid|inner:uuid"`.

Source: `docs/persistence.md`.

## Serialization

The default serializer (`JsonPlusSerializer`) handles LangChain/LangGraph
primitives, datetimes, and enums. For types not supported (e.g. Pandas
DataFrames), enable pickle fallback:

```python
from langgraph.checkpoint.serde.jsonplus import JsonPlusSerializer

graph.compile(checkpointer=InMemorySaver(serde=JsonPlusSerializer(pickle_fallback=True)))
```

For at-rest encryption, use `EncryptedSerializer` with `LANGGRAPH_AES_KEY`.
Source: `docs/persistence.md`.

## Cross-thread memory (Store)

Checkpointers save state **per thread**. To share data across threads (e.g.
user preferences across conversations), use a `Store`:

```python
from langgraph.store.memory import InMemoryStore
store = InMemoryStore()

# Compile with both checkpointer and store
graph = builder.compile(checkpointer=checkpointer, store=store)
```

Inside a node, access via `runtime.store`:

```python
async def my_node(state: State, runtime: Runtime[Ctx]):
    namespace = (runtime.context.user_id, "memories")
    await runtime.store.aput(namespace, memory_id, {"memory": "likes pizza"})
    results = await runtime.store.asearch(namespace, query="food", limit=3)
```

`InMemoryStore` supports semantic search when configured with an embedding model.
For production, use `PostgresStore` or `RedisStore`. Source: `docs/persistence.md`.
