# Persistence Reference

Source: `docs/persistence.md`, `docs/add-memory.md`

## Why persistence

A checkpointer saves a snapshot of graph state after every super-step. This enables:
- **Human-in-the-loop**: pause indefinitely, resume with human input.
- **Conversation memory**: same thread retains prior messages across invocations.
- **Time travel**: replay or fork from any past checkpoint.
- **Fault tolerance**: resume from last successful step after a crash.
- **Pending writes**: if a node fails, completed sibling nodes in the same step are
  not re-run on resume.

## Threads

A thread is identified by `thread_id` inside `config["configurable"]`:

```python
config = {"configurable": {"thread_id": "user-123"}}
graph.invoke(inputs, config)
```

Reusing the same `thread_id` resumes the conversation. A new `thread_id` starts fresh.

## Checkpointer setup

```python
from langgraph.checkpoint.memory import InMemorySaver       # dev/test only

checkpointer = InMemorySaver()
graph = builder.compile(checkpointer=checkpointer)
```

Production options (install separately):
- `langgraph-checkpoint-sqlite` — `SqliteSaver` / `AsyncSqliteSaver`
- `langgraph-checkpoint-postgres` — `PostgresSaver` / `AsyncPostgresSaver`
- `langgraph-checkpoint-cosmosdb` — Azure Cosmos DB

```python
from langgraph.checkpoint.postgres import PostgresSaver

with PostgresSaver.from_conn_string("postgresql://...") as cp:
    cp.setup()   # run once on first use
    graph = builder.compile(checkpointer=cp)
```

For async graphs, use the async variant (`AsyncPostgresSaver`, etc.).

## Reading and writing state

```python
# Latest state snapshot
snap = graph.get_state(config)

# Specific checkpoint
snap = graph.get_state({"configurable": {"thread_id": "1", "checkpoint_id": "abc"}})

# Full history (newest first)
history = list(graph.get_state_history(config))

# Edit state (creates new checkpoint, does NOT roll back)
graph.update_state(config, values={"foo": "new"}, as_node="node_a")
```

### StateSnapshot fields

| Field | Description |
|-------|-------------|
| `values` | State channel values at this checkpoint |
| `next` | Node names scheduled next; `()` means complete |
| `config` | Contains `thread_id`, `checkpoint_ns`, `checkpoint_id` |
| `metadata` | `source` ("input"/"loop"/"update"), `writes`, `step` counter |
| `created_at` | ISO 8601 timestamp |
| `parent_config` | Previous checkpoint config; `None` for first |
| `tasks` | `PregelTask` list; includes `interrupts` field |

## Memory store (cross-thread long-term memory)

Checkpointers are per-thread. For data that should persist *across* threads, use a `Store`:

```python
from langgraph.store.memory import InMemoryStore  # dev/test

store = InMemoryStore()
graph = builder.compile(checkpointer=checkpointer, store=store)
```

Store operations use namespaced keys:

```python
namespace = (user_id, "memories")
store.put(namespace, memory_id, {"text": "user prefers dark mode"})
memories = store.search(namespace)                        # all items
memories = store.search(namespace, query="dark", limit=3) # semantic search
```

Each item is a `langgraph.store.base.Item` with `.value`, `.key`, `.namespace`,
`.created_at`, `.updated_at`. Access as dict via `.dict()`.

### Semantic search

```python
from langchain.embeddings import init_embeddings

store = InMemoryStore(index={
    "embed": init_embeddings("openai:text-embedding-3-small"),
    "dims": 1536,
    "fields": ["$"],     # fields to embed; "$" = whole value
})
```

Production store: `PostgresStore` / `AsyncPostgresStore` or `RedisStore`.

### Accessing store in nodes

```python
from langgraph.runtime import Runtime

async def call_model(state, runtime: Runtime[Context]):
    memories = await runtime.store.asearch(
        (runtime.context.user_id, "mem"),
        query=state["messages"][-1].content,
        limit=3,
    )
    await runtime.store.aput(namespace, str(uuid.uuid4()), {"data": "..."})
```

## Checkpoint serialization

Default serializer: `JsonPlusSerializer` (msgpack + JSON). For Pandas DataFrames or
other non-serializable types:

```python
from langgraph.checkpoint.serde.jsonplus import JsonPlusSerializer
graph.compile(checkpointer=InMemorySaver(serde=JsonPlusSerializer(pickle_fallback=True)))
```

### Encryption

```python
from langgraph.checkpoint.serde.encrypted import EncryptedSerializer

serde = EncryptedSerializer.from_pycryptodome_aes()  # reads LANGGRAPH_AES_KEY env var
checkpointer = SqliteSaver(conn, serde=serde)
```

On LangSmith, encryption is automatic when `LANGGRAPH_AES_KEY` is present.
Custom schemes: implement `CipherProtocol` and pass to `EncryptedSerializer`.

## Delete a thread

```python
checkpointer.delete_thread(thread_id)
```

## Super-steps and checkpointing frequency

A super-step is one "tick" of the graph: all nodes scheduled for that step run
(potentially in parallel), then state is saved. Sequential graph `A → B → C`
produces checkpoints after input, A, B, and C — four checkpoints total.
