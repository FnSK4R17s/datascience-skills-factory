# Memory

Source: `docs/short-term-memory.md`, `docs/long-term-memory.md`, `docs/agents.md`, `docs/tools.md`

LangChain distinguishes two memory scopes: short-term (within a thread/conversation) and
long-term (across threads/sessions).

## Short-term memory (checkpointer)

Short-term memory persists the agent's state within a conversation thread. Enable it by
passing a `checkpointer` to `create_agent`.

```python
from langchain.agents import create_agent
from langgraph.checkpoint.memory import InMemorySaver

agent = create_agent(
    "openai:gpt-5.4",
    tools=[...],
    checkpointer=InMemorySaver(),  # dev only — lost on restart
)

# Each invoke call with the same thread_id shares memory
result = agent.invoke(
    {"messages": [{"role": "user", "content": "My name is Alice."}]},
    {"configurable": {"thread_id": "session-1"}},
)
result2 = agent.invoke(
    {"messages": [{"role": "user", "content": "What is my name?"}]},
    {"configurable": {"thread_id": "session-1"}},
)
# agent recalls "Alice"
```

### Production checkpointers

```bash
pip install langgraph-checkpoint-postgres
```

```python
from langgraph.checkpoint.postgres import PostgresSaver

DB_URI = "postgresql://user:pass@host:5432/dbname"
with PostgresSaver.from_conn_string(DB_URI) as checkpointer:
    checkpointer.setup()  # auto-creates tables
    agent = create_agent("openai:gpt-5.4", tools=[...], checkpointer=checkpointer)
```

Also available: SQLite, Azure Cosmos DB, Redis — see langgraph persistence docs.

## Custom short-term state

Extend `AgentState` (TypedDict only in v1+) to add fields:

```python
from langchain.agents import AgentState, create_agent

class MyState(AgentState):
    user_name: str
    call_count: int

agent = create_agent(
    "openai:gpt-5.4",
    tools=[...],
    state_schema=MyState,
)

result = agent.invoke({
    "messages": [{"role": "user", "content": "Hello"}],
    "user_name": "Bob",
    "call_count": 0,
})
```

Pydantic models and dataclasses are NOT valid state schemas in v1+ (see `docs/agents.md`).
They remain valid for tool input schemas and structured output.

## Long-term memory (store)

Long-term memory persists across different threads via a `BaseStore`. Data is organized as
JSON documents under `namespace` (tuple) + `key`.

```python
from langchain.agents import create_agent
from langgraph.store.memory import InMemoryStore  # dev only

store = InMemoryStore()
agent = create_agent("openai:gpt-5.4", tools=[...], store=store)
```

### Production store

```python
from langgraph.store.postgres import PostgresStore

DB_URI = "postgresql://user:pass@host:5432/dbname"
with PostgresStore.from_conn_string(DB_URI) as store:
    store.setup()
    agent = create_agent("openai:gpt-5.4", tools=[...], store=store)
```

### Reading and writing from tools

```python
from langchain.tools import tool, ToolRuntime

@tool
def save_preference(key: str, value: str, runtime: ToolRuntime) -> str:
    """Save a user preference."""
    runtime.store.put(("prefs", runtime.context.user_id), key, {"value": value})
    return f"Saved {key}={value}"

@tool
def get_preference(key: str, runtime: ToolRuntime) -> str:
    """Get a user preference."""
    item = runtime.store.get(("prefs", runtime.context.user_id), key)
    return str(item.value) if item else "Not set"
```

Namespaces are tuples like `("users", user_id)`, `("prefs", org_id)`. Use keys to
distinguish individual records within a namespace.

## Filesystem middleware (deep agents)

`FilesystemMiddleware` (from `deepagents`) provides tools (`ls`, `read_file`, `write_file`,
`edit_file`) that let the agent manage context as files. By default writes to in-memory state;
configure a `StoreBackend` for a path prefix to make certain paths persistent across threads.

```python
from deepagents.middleware.filesystem import FilesystemMiddleware
from deepagents.backends import CompositeBackend, StateBackend, StoreBackend
from langgraph.store.memory import InMemoryStore

store = InMemoryStore()
agent = create_agent(
    "claude-sonnet-4-6",
    store=store,
    middleware=[
        FilesystemMiddleware(
            backend=CompositeBackend(
                default=StateBackend(),
                routes={"/memories/": StoreBackend()}
            )
        )
    ]
)
```

Files under `/memories/` survive across threads; all other paths are ephemeral.

## Summarization middleware

Automatically compress old messages when approaching token limits (see `docs/middleware__built-in.md`):

```python
from langchain.agents.middleware import SummarizationMiddleware

agent = create_agent(
    "openai:gpt-5.4",
    tools=[...],
    middleware=[
        SummarizationMiddleware(
            model="openai:gpt-5.4-mini",
            trigger=("tokens", 4000),
            keep=("messages", 20),
        )
    ]
)
```

`trigger` can be a `(type, value)` tuple or a list for OR logic. Types: `fraction`, `tokens`, `messages`.
