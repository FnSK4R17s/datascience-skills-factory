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
graph.invoke({"messages": [{"role": "user", "content": "hi, I'm Bob"}]}, config)
# Second call on same thread_id retains prior messages
graph.invoke({"messages": [{"role": "user", "content": "what did I say?"}]}, config)
```

### Managing context window size

Long conversations exceed LLM context limits. Three strategies:

**1. Trim messages (before calling LLM)**

Keeps messages in state but only passes a subset to the model. Non-destructive.

```python
from langchain_core.messages.utils import trim_messages, count_tokens_approximately
from langgraph.graph import MessagesState

def call_model(state: MessagesState):
    trimmed = trim_messages(
        state["messages"],
        strategy="last",                              # keep most recent messages
        token_counter=count_tokens_approximately,
        max_tokens=4096,
        start_on="human",                             # ensure context starts with human
        end_on=("human", "tool"),                     # valid end types
        include_system=True,                          # preserve system message
    )
    return {"messages": [model.invoke(trimmed)]}
```

**2. Delete messages permanently from state**

Removes messages from the checkpoint. Destructive — they're gone from history.

```python
from langchain.messages import RemoveMessage
from langgraph.graph.message import REMOVE_ALL_MESSAGES

def prune_old_messages(state: MessagesState):
    # Remove the two oldest messages
    return {"messages": [RemoveMessage(id=m.id) for m in state["messages"][:2]]}

def clear_all_messages(state: MessagesState):
    # Clear entire history
    return {"messages": [RemoveMessage(id=REMOVE_ALL_MESSAGES)]}
```

When deleting, ensure the remaining message list is valid:
- Most LLM providers require history to start with a user/human message.
- Tool call messages must always be followed by their corresponding tool result.
- Deleting a `ToolCall` message without its `ToolMessage` result causes provider errors.

**3. Summarize messages**

Keep a rolling summary + recent messages. Preserves context without unbounded growth.

```python
from langgraph.graph import MessagesState
from langchain.messages import RemoveMessage

class State(MessagesState):
    summary: str

def summarize_conversation(state: State):
    existing = state.get("summary", "")
    messages_text = "\n".join([f"{m.role}: {m.content}" for m in state["messages"][:-2]])
    prompt = f"Prior summary: {existing}\n\nNew messages:\n{messages_text}\n\nCreate updated summary:"
    new_summary = model.invoke([{"role": "user", "content": prompt}]).content

    # Delete all but the last 2 messages
    to_delete = [RemoveMessage(id=m.id) for m in state["messages"][:-2]]
    return {"summary": new_summary, "messages": to_delete}

def should_summarize(state: State) -> str:
    return "summarize" if len(state["messages"]) > 10 else "chat"

def call_model(state: State):
    # Inject summary as context
    system_msg = f"Prior conversation summary: {state.get('summary', '')}"
    messages = [{"role": "system", "content": system_msg}] + state["messages"]
    return {"messages": [model.invoke(messages)]}
```

### Viewing and deleting thread state

```python
# View current thread state
snap = graph.get_state(config)
print(snap.values["messages"])

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

# Read all in namespace
items = store.search(namespace)

# Read with semantic search (requires embedding config)
items = store.search(namespace, query="user preferences", limit=5)

# Access item fields
item = items[0]
item.value       # dict payload
item.key         # unique ID within namespace
item.namespace   # tuple
item.created_at  # ISO 8601
item.updated_at  # ISO 8601

# Delete a specific item
store.delete(namespace, memory_id)
```

### Semantic search

```python
from langchain.embeddings import init_embeddings

store = InMemoryStore(index={
    "embed": init_embeddings("openai:text-embedding-3-small"),
    "dims": 1536,
    "fields": ["$"],            # embed entire value; or list specific fields like ["text"]
})

# Selective indexing
store.put(namespace, "1", {"text": "user likes pizza"}, index=["text"])
store.put(namespace, "2", {"notes": "internal"}, index=False)  # not searchable

results = store.search(namespace, query="what food does user like?", limit=3)
for r in results:
    print(r.value["text"], r.score)  # score is similarity
```

### Accessing store in nodes

```python
from langgraph.runtime import Runtime
from dataclasses import dataclass
import uuid

@dataclass
class Context:
    user_id: str

async def call_model(state: MessagesState, runtime: Runtime[Context]):
    ns = (runtime.context.user_id, "memories")

    # Retrieve relevant memories
    memories = await runtime.store.asearch(
        ns,
        query=state["messages"][-1].content,
        limit=3,
    )
    info = "\n".join(m.value["text"] for m in memories if "text" in m.value)

    # Store a new memory about this interaction
    await runtime.store.aput(
        ns,
        str(uuid.uuid4()),
        {"text": f"User asked: {state['messages'][-1].content}"}
    )

    response = await model.ainvoke([
        {"role": "system", "content": f"Relevant context:\n{info}"},
        *state["messages"]
    ])
    return {"messages": [response]}

builder = StateGraph(MessagesState, context_schema=Context)
builder.add_node(call_model)
graph = builder.compile(checkpointer=checkpointer, store=store)

graph.invoke(inputs, config, context=Context(user_id="u1"))
```

## Subgraphs and memory

Provide the checkpointer only on the parent graph — LangGraph propagates it to
subgraphs automatically. For subgraph-specific persistence, see `references/subgraphs.md`.

## Database setup for production

For production Postgres-backed persistence, run migrations as a dedicated deployment
step — not on every app start.

```python
from langgraph.checkpoint.postgres import PostgresSaver
from langgraph.store.postgres import PostgresStore

DB_URI = "postgresql://user:password@host:5432/dbname"

# Run once during deployment
with PostgresSaver.from_conn_string(DB_URI) as cp:
    cp.setup()   # creates checkpoints schema/tables; idempotent

with PostgresStore.from_conn_string(DB_URI) as st:
    st.setup()   # creates store schema/tables; idempotent

# Runtime usage
with PostgresSaver.from_conn_string(DB_URI) as checkpointer:
    with PostgresStore.from_conn_string(DB_URI) as store:
        graph = builder.compile(checkpointer=checkpointer, store=store)
        result = graph.invoke(inputs, config)
```

### Store config in `langgraph.json` for deployment

```json
{
  "dependencies": ["."],
  "graphs": {
    "agent": "./src/agent.py:graph"
  },
  "env": ".env",
  "store": {
    "index": {
      "embed": "openai:text-embeddings-3-small",
      "dims": 1536,
      "fields": ["$"]
    }
  }
}
```
