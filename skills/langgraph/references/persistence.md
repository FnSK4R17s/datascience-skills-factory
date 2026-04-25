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

For a sequential graph `START → A → B → END`, a run creates exactly 4 checkpoints:
empty checkpoint (START scheduled), after input, after A, after B.

## Threads

A thread is identified by `thread_id` inside `config["configurable"]`. Without it,
the checkpointer cannot save state or resume after an interrupt.

```python
config = {"configurable": {"thread_id": "user-123"}}
graph.invoke(inputs, config)
```

Reusing the same `thread_id` resumes the conversation. A new `thread_id` starts fresh.

## Checkpointer setup

### Development / testing

```python
from langgraph.checkpoint.memory import InMemorySaver   # or MemorySaver (alias)

checkpointer = InMemorySaver()
graph = builder.compile(checkpointer=checkpointer)
```

`InMemorySaver` is lost on process restart. Use only for development and testing.

### SQLite (single-process, durable)

```python
pip install langgraph-checkpoint-sqlite

from langgraph.checkpoint.sqlite import SqliteSaver
import sqlite3

conn = sqlite3.connect("checkpoints.db", check_same_thread=False)
checkpointer = SqliteSaver(conn)

# Async variant
from langgraph.checkpoint.sqlite.aio import AsyncSqliteSaver
```

### PostgreSQL (production, multi-process)

```python
pip install "psycopg[binary,pool]" langgraph-checkpoint-postgres

from langgraph.checkpoint.postgres import PostgresSaver

DB_URI = "postgresql://user:password@host:5432/dbname"
with PostgresSaver.from_conn_string(DB_URI) as cp:
    cp.setup()   # run once to create tables; idempotent
    graph = builder.compile(checkpointer=cp)
    result = graph.invoke(inputs, config)

# Async variant
from langgraph.checkpoint.postgres.aio import AsyncPostgresSaver

async with AsyncPostgresSaver.from_conn_string(DB_URI) as cp:
    await cp.setup()
    graph = builder.compile(checkpointer=cp)
    result = await graph.ainvoke(inputs, config)
```

For async graphs, use the async variant. Do not share sync/async checkpointers
across sync/async graph invocations.

### Azure Cosmos DB

```python
pip install langgraph-checkpoint-cosmosdb
from langgraph.checkpoint.cosmosdb import CosmosDBSaver
```

## Full multi-turn conversation example

Source: `docs/add-memory.md`

```python
from langchain.chat_models import init_chat_model
from langgraph.graph import StateGraph, MessagesState, START
from langgraph.checkpoint.postgres import PostgresSaver

model = init_chat_model(model="claude-haiku-4-5-20251001")

DB_URI = "postgresql://postgres:postgres@localhost:5442/postgres?sslmode=disable"
with PostgresSaver.from_conn_string(DB_URI) as checkpointer:
    def call_model(state: MessagesState):
        response = model.invoke(state["messages"])
        return {"messages": response}

    builder = StateGraph(MessagesState)
    builder.add_node(call_model)
    builder.add_edge(START, "call_model")
    graph = builder.compile(checkpointer=checkpointer)

    config = {"configurable": {"thread_id": "1"}}

    # First turn
    for chunk in graph.stream(
        {"messages": [{"role": "user", "content": "hi! I'm bob"}]},
        config, stream_mode="values"
    ):
        chunk["messages"][-1].pretty_print()

    # Second turn — graph remembers "I'm bob"
    for chunk in graph.stream(
        {"messages": [{"role": "user", "content": "what's my name?"}]},
        config, stream_mode="values"
    ):
        chunk["messages"][-1].pretty_print()
    # AI: "Your name is Bob."
```

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

Example `StateSnapshot` from the docs:

```
StateSnapshot(
    values={'foo': 'b', 'bar': ['a', 'b']},
    next=(),
    config={'configurable': {
        'thread_id': '1',
        'checkpoint_ns': '',
        'checkpoint_id': '1ef663ba-28fe-6528-8002-5a559208592c'
    }},
    metadata={'source': 'loop', 'writes': {'node_b': {'foo': 'b', 'bar': ['b']}}, 'step': 2},
    created_at='2024-08-29T19:19:38.821749+00:00',
    parent_config={'configurable': {
        'thread_id': '1',
        'checkpoint_ns': '',
        'checkpoint_id': '1ef663ba-28f9-6ec4-8001-31981c2c39f8'
    }},
    tasks=()
)
```

## Memory store (cross-thread long-term memory)

Checkpointers are per-thread. For data that should persist *across* threads, use a `Store`.

```python
from langgraph.store.memory import InMemoryStore   # dev only

store = InMemoryStore()
graph = builder.compile(checkpointer=checkpointer, store=store)
```

Store operations use namespaced keys (tuples of strings):

```python
namespace = (user_id, "memories")
store.put(namespace, memory_id, {"text": "user prefers dark mode"})

# Retrieve all items in namespace
memories = store.search(namespace)

# Semantic search (requires embedding config)
memories = store.search(namespace, query="dark", limit=3)
```

Each item is a `langgraph.store.base.Item` with `.value`, `.key`, `.namespace`,
`.created_at`, `.updated_at`.

### Semantic search in store

```python
from langchain.embeddings import init_embeddings

store = InMemoryStore(index={
    "embed": init_embeddings("openai:text-embedding-3-small"),
    "dims": 1536,
    "fields": ["$"],     # fields to embed; "$" = whole value, or list specific fields
})
```

### Accessing store in nodes

```python
from langgraph.runtime import Runtime
from dataclasses import dataclass

@dataclass
class Context:
    user_id: str

async def call_model(state, runtime: Runtime[Context]):
    ns = (runtime.context.user_id, "mem")
    memories = await runtime.store.asearch(
        ns,
        query=state["messages"][-1].content,
        limit=3,
    )
    await runtime.store.aput(ns, str(uuid.uuid4()), {"data": "new memory"})
```

### Production store backends

```python
# PostgreSQL — run setup() once
from langgraph.store.postgres import PostgresStore

with PostgresStore.from_conn_string(db_uri) as store:
    store.setup()   # create tables; run as deployment step, not on every start
    graph = builder.compile(checkpointer=checkpointer, store=store)
```

## Checkpoint serialization

Default serializer: `JsonPlusSerializer` (msgpack + JSON fallback). For Pandas
DataFrames or other non-serializable types:

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
