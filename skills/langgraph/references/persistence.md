# Persistence

LangGraph saves graph state as checkpoints at each superstep. A checkpointer
unlocks: human-in-the-loop, conversational memory, time travel, and
fault-tolerant re-execution from the last successful step.

## The three-line minimum

```python
from langgraph.checkpoint.memory import InMemorySaver

checkpointer = InMemorySaver()   # dev only — lost on restart
graph = builder.compile(checkpointer=checkpointer)

config = {"configurable": {"thread_id": "my-thread"}}
graph.invoke({"messages": [...]}, config)
```

Without `thread_id` in config the checkpointer cannot save or load state.
The key must be inside `configurable`, not at the top of config.

## Checkpointer libraries

| Library | Class | Use case |
|---------|-------|----------|
| Built-in | `InMemorySaver` | Dev / tests — vanishes on restart |
| `langgraph-checkpoint-sqlite` | `SqliteSaver` / `AsyncSqliteSaver` | Local single-process workflows |
| `langgraph-checkpoint-postgres` | `PostgresSaver` / `AsyncPostgresSaver` | Production |
| `langgraph-checkpoint-cosmosdb` | `CosmosDBSaver` / `AsyncCosmosDBSaver` | Azure production |

For async graph execution use async variants (`AsyncSqliteSaver`,
`AsyncPostgresSaver`, etc.). `InMemorySaver` supports both sync and async.

### Async setup (Postgres example)

```python
from langgraph.checkpoint.postgres.aio import AsyncPostgresSaver

async with AsyncPostgresSaver.from_conn_string("postgresql://...") as checkpointer:
    await checkpointer.setup()   # creates tables on first use
    graph = builder.compile(checkpointer=checkpointer)
    result = await graph.ainvoke(inputs, config)
```

## Serialization

The default serialiser (`JsonPlusSerializer`) handles LangChain primitives,
datetimes, enums, and most standard types. For Pandas DataFrames or other
non-JSON types:

```python
from langgraph.checkpoint.serde.jsonplus import JsonPlusSerializer
from langgraph.checkpoint.memory import InMemorySaver

graph.compile(
    checkpointer=InMemorySaver(serde=JsonPlusSerializer(pickle_fallback=True))
)
```

### Encryption

```python
from langgraph.checkpoint.serde.encrypted import EncryptedSerializer
from langgraph.checkpoint.postgres import PostgresSaver

# Reads key from LANGGRAPH_AES_KEY env var
serde = EncryptedSerializer.from_pycryptodome_aes()
checkpointer = PostgresSaver.from_conn_string("postgresql://...", serde=serde)
checkpointer.setup()
```

## Threads and checkpoints

A **thread** is a stable `thread_id` that groups all checkpoints from one
conversation or workflow run.

A **checkpoint** (StateSnapshot) is saved after every superstep. For a
linear graph `START -> A -> B -> END` you get four checkpoints: empty,
input+A_next, A_output+B_next, B_output+done.

### Get latest state

```python
snapshot = graph.get_state({"configurable": {"thread_id": "1"}})
```

### Get state at a specific checkpoint

```python
config = {"configurable": {"thread_id": "1", "checkpoint_id": "<id>"}}
snapshot = graph.get_state(config)
```

### Get full history (most-recent first)

```python
history = list(graph.get_state_history({"configurable": {"thread_id": "1"}}))
```

### Find specific checkpoints

```python
# Checkpoint just before node_b ran
before_b = next(s for s in history if s.next == ("node_b",))

# Checkpoint at a specific step number
step2 = next(s for s in history if s.metadata["step"] == 2)

# Checkpoints created by update_state
forks = [s for s in history if s.metadata["source"] == "update"]
```

## Time travel

Replay from a prior checkpoint by passing its `checkpoint_id` in config.
Nodes before that checkpoint are skipped; nodes after re-execute (including
LLM calls and any interrupts).

```python
old_config = {"configurable": {"thread_id": "1", "checkpoint_id": "<id>"}}
graph.invoke(None, old_config)  # or invoke with new input to fork
```

Fork a thread by using a new `thread_id` with a prior `checkpoint_id`:

```python
fork_config = {"configurable": {"thread_id": "new-thread", "checkpoint_id": "<id>"}}
graph.invoke({"new_key": "value"}, fork_config)
```

## Cross-thread memory (Store)

Checkpoints are per-thread. For information that must persist across threads
(user preferences, long-term memories), use a `Store`:

```python
from langgraph.store.memory import InMemoryStore  # dev only

store = InMemoryStore()
graph = builder.compile(checkpointer=checkpointer, store=store)
```

### Store operations

```python
# Write
store.put(("user_id", "memories"), memory_id, {"content": "likes pizza"})

# Read all in namespace
memories = store.search(("user_id", "memories"))

# Semantic search (requires embedding config on InMemoryStore)
memories = store.search(namespace, query="food preferences", limit=5)
```

Access the store inside nodes via `Runtime`:

```python
from langgraph.runtime import Runtime

async def update_memory(state: State, runtime: Runtime[Context]):
    await runtime.store.aput(
        (runtime.context.user_id, "memories"),
        str(uuid.uuid4()),
        {"content": "..."}
    )
```

### Semantic search setup

```python
from langchain.embeddings import init_embeddings

store = InMemoryStore(
    index={
        "embed": init_embeddings("openai:text-embedding-3-small"),
        "dims": 1536,
        "fields": ["$"]  # which fields to embed
    }
)
```

For production use `PostgresStore` or `RedisStore`. In the LangSmith Agent
Server, the store is available automatically without manual configuration.

## Pending writes

When a node fails mid-superstep, LangGraph saves outputs from nodes that
completed successfully in that superstep. On resume those nodes are not
re-run — only the failed node restarts.

## Checkpoint namespace

`checkpoint_ns` in config identifies which graph/subgraph a checkpoint
belongs to: `""` for the root graph, `"node_name:uuid"` for a subgraph.
For nested subgraphs: `"outer:uuid|inner:uuid"`.
