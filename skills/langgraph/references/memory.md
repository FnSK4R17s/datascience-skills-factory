# Memory Reference

Source: `docs/add-memory.md`, `docs/persistence.md`

## Two memory types

| Type | Scope | Mechanism | API |
|------|-------|-----------|-----|
| Short-term (thread) | One conversation thread | Checkpointer | `graph.get_state()`, `graph.update_state()` |
| Long-term (cross-thread) | All threads for a user/app | `Store` | `store.put()`, `store.search()` |

## Short-term memory

Compile with a checkpointer + pass `thread_id`:

```python
from langgraph.checkpoint.memory import InMemorySaver   # dev only
from langgraph.checkpoint.postgres import PostgresSaver  # production

graph = builder.compile(checkpointer=PostgresSaver.from_conn_string("postgresql://..."))

config = {"configurable": {"thread_id": "user-123"}}
graph.invoke({"messages": [{"role": "user", "content": "hi"}]}, config)
# Second call on same thread_id retains prior messages
graph.invoke({"messages": [{"role": "user", "content": "what did I say?"}]}, config)
```

### Managing context window size

Long conversations exceed LLM context limits. Solutions:

**Trim messages** (before calling LLM):

```python
from langchain_core.messages.utils import trim_messages, count_tokens_approximately

def call_model(state):
    trimmed = trim_messages(
        state["messages"],
        strategy="last",
        token_counter=count_tokens_approximately,
        max_tokens=4096,
        start_on="human",
        end_on=("human", "tool"),
    )
    return {"messages": [model.invoke(trimmed)]}
```

**Delete messages** (permanently from state):

```python
from langchain.messages import RemoveMessage
from langgraph.graph.message import REMOVE_ALL_MESSAGES

# Remove oldest two
return {"messages": [RemoveMessage(id=m.id) for m in state["messages"][:2]]}

# Clear everything
return {"messages": [RemoveMessage(id=REMOVE_ALL_MESSAGES)]}
```

When deleting, ensure the resulting message list is valid for your LLM provider
(e.g. most require history to start with a user message; tool call messages must be
followed by their tool result).

**Summarize messages**:

```python
class State(MessagesState):
    summary: str

def summarize(state):
    existing = state.get("summary", "")
    prompt = f"Summarize: {existing}\n\nNew messages: ..."
    new_summary = model.invoke([...]).content
    to_delete = [RemoveMessage(id=m.id) for m in state["messages"][:-2]]
    return {"summary": new_summary, "messages": to_delete}
```

### Viewing and deleting thread state

```python
# View current thread state
graph.get_state(config)

# Delete all checkpoints for a thread
checkpointer.delete_thread("user-123")
```

## Long-term memory (`Store`)

The `Store` interface persists data across threads. Access via `runtime.store` inside nodes.

```python
from langgraph.store.memory import InMemoryStore   # dev only
from langgraph.store.postgres import PostgresStore  # production

store = InMemoryStore()
graph = builder.compile(checkpointer=checkpointer, store=store)
```

### CRUD operations

```python
namespace = (user_id, "memories")   # tuple of strings; any length/meaning

# Write
store.put(namespace, memory_id, {"text": "user prefers concise answers"})

# Read all
items = store.search(namespace)
# Read with semantic search
items = store.search(namespace, query="user preferences", limit=5)

# Access item
item = items[0]
item.value       # dict payload
item.key         # unique ID within namespace
item.namespace   # tuple, may be serialized as list in JSON
item.created_at  # ISO 8601
item.updated_at  # ISO 8601
```

### Semantic search

```python
from langchain.embeddings import init_embeddings

store = InMemoryStore(index={
    "embed": init_embeddings("openai:text-embedding-3-small"),
    "dims": 1536,
    "fields": ["$"],            # embed entire value; or list specific fields
})

store.put(namespace, "1", {"text": "user likes pizza"}, index=["text"])
store.put(namespace, "2", {"notes": "internal"}, index=False)  # not searchable

results = store.search(namespace, query="what food does user like?", limit=3)
```

### Accessing store in nodes

```python
from langgraph.runtime import Runtime
from dataclasses import dataclass

@dataclass
class Context:
    user_id: str

async def call_model(state: MessagesState, runtime: Runtime[Context]):
    ns = (runtime.context.user_id, "memories")

    # Retrieve relevant memories
    memories = await runtime.store.asearch(ns, query=state["messages"][-1].content, limit=3)
    info = "\n".join(m.value["text"] for m in memories)

    # Store a new memory
    await runtime.store.aput(ns, str(uuid.uuid4()), {"text": "user is named Alice"})

    response = await model.ainvoke([{"role": "system", "content": info}, *state["messages"]])
    return {"messages": [response]}

builder = StateGraph(MessagesState, context_schema=Context)
builder.add_node(call_model)
graph = builder.compile(checkpointer=checkpointer, store=store)

graph.invoke(inputs, config, context=Context(user_id="u1"))
```

## Subgraphs and memory

Provide the checkpointer only on the parent graph — LangGraph propagates it to
subgraphs automatically. For subgraph-specific persistence, see `references/subgraphs.md`.

## Database setup

For production Postgres-backed persistence:

```python
from langgraph.checkpoint.postgres import PostgresSaver
from langgraph.store.postgres import PostgresStore

with PostgresSaver.from_conn_string(db_uri) as cp:
    cp.setup()   # run migrations once

with PostgresStore.from_conn_string(db_uri) as store:
    store.setup()  # run migrations once
```

Run migrations as a dedicated deployment step, not on every app start.
