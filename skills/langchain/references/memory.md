# Memory

Source: `docs/short-term-memory.md`, `docs/long-term-memory.md`, `docs/agents.md`, `docs/tools.md`

LangChain distinguishes two memory scopes:
- **Short-term memory** — within a thread/conversation (checkpointer)
- **Long-term memory** — across threads/sessions (store)

## Short-term memory (checkpointer)

Short-term memory persists the agent's state within a conversation thread. Enable it by
passing a `checkpointer` to `create_agent`. Each `invoke`/`stream` call with the same
`thread_id` shares and accumulates memory.

```python
from langchain.agents import create_agent
from langgraph.checkpoint.memory import InMemorySaver

agent = create_agent(
    "openai:gpt-5.4",
    tools=[...],
    checkpointer=InMemorySaver(),  # dev only — lost on restart
)

# Turn 1 — agent learns user name
result1 = agent.invoke(
    {"messages": [{"role": "user", "content": "My name is Alice."}]},
    {"configurable": {"thread_id": "session-1"}},
)

# Turn 2 — agent recalls it
result2 = agent.invoke(
    {"messages": [{"role": "user", "content": "What is my name?"}]},
    {"configurable": {"thread_id": "session-1"}},
)
print(result2["messages"][-1].text)  # "Your name is Alice."

# Different thread — no memory of Alice
result3 = agent.invoke(
    {"messages": [{"role": "user", "content": "What is my name?"}]},
    {"configurable": {"thread_id": "session-2"}},
)
# "I don't know your name — you haven't told me."
```

### Production checkpointers

```bash
pip install langgraph-checkpoint-postgres
```

```python
from langgraph.checkpoint.postgres import PostgresSaver
from langgraph.checkpoint.postgres.aio import AsyncPostgresSaver

DB_URI = "postgresql://user:pass@host:5432/dbname"

# Sync (use with synchronous agent.invoke)
with PostgresSaver.from_conn_string(DB_URI) as checkpointer:
    checkpointer.setup()  # auto-creates tables on first run
    agent = create_agent("openai:gpt-5.4", tools=[...], checkpointer=checkpointer)
    result = agent.invoke(
        {"messages": [{"role": "user", "content": "Hello"}]},
        {"configurable": {"thread_id": "t1"}},
    )

# Async (use with async agent.ainvoke)
import asyncio

async def run():
    async with AsyncPostgresSaver.from_conn_string(DB_URI) as checkpointer:
        await checkpointer.setup()
        agent = create_agent("openai:gpt-5.4", tools=[...], checkpointer=checkpointer)
        result = await agent.ainvoke(
            {"messages": [{"role": "user", "content": "Hello"}]},
            {"configurable": {"thread_id": "t1"}},
        )

asyncio.run(run())
```

Also available: SQLite, Azure Cosmos DB, Redis, MongoDB — see langgraph persistence docs.

```python
# SQLite (dev, persists to disk)
from langgraph.checkpoint.sqlite import SqliteSaver
with SqliteSaver.from_conn_string("./my_agent.db") as checkpointer:
    agent = create_agent(model, tools, checkpointer=checkpointer)
```

## Custom short-term state

Extend `AgentState` (TypedDict only in v1+) to add fields. Two ways:

### Via state_schema on create_agent (shortcut for tools-only state)

```python
from langchain.agents import AgentState, create_agent
from typing_extensions import NotRequired

class MyState(AgentState):
    user_name: NotRequired[str]
    call_count: NotRequired[int]
    active_task: NotRequired[str]

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

# Access custom state fields
print(result.get("user_name"))   # "Bob"
print(result.get("call_count"))  # may be updated by middleware
```

### Via middleware state_schema (preferred — scopes state to middleware)

```python
from langchain.agents import AgentState, create_agent
from langchain.agents.middleware import AgentMiddleware
from typing import Any
from typing_extensions import NotRequired

class CustomState(AgentState):
    model_call_count: NotRequired[int]
    user_preferences: NotRequired[dict]

class TrackingMiddleware(AgentMiddleware):
    state_schema = CustomState  # extends agent's state

    def before_model(self, state: CustomState, runtime) -> dict[str, Any] | None:
        return {"model_call_count": state.get("model_call_count", 0) + 1}

    def after_agent(self, state: CustomState, runtime) -> dict[str, Any] | None:
        print(f"Total model calls: {state.get('model_call_count', 0)}")
        return None

agent = create_agent(
    "openai:gpt-5.4",
    tools=[...],
    middleware=[TrackingMiddleware()],
)
```

**Pydantic models and dataclasses are NOT valid state schemas.** They remain valid for:
- Tool input schemas (`@tool(args_schema=MyPydanticModel)`)
- Structured output (`response_format=MyPydanticModel`)
- Runtime context (`context_schema=MyDataclass`)

## Updating state from tools

Tools can update state fields using `Command`. Always include a `ToolMessage` so the
model sees confirmation:

```python
from langchain.agents import AgentState
from langchain.messages import ToolMessage
from langchain.tools import ToolRuntime, tool
from langgraph.types import Command
from typing_extensions import NotRequired

class ConversationState(AgentState):
    user_name: NotRequired[str]
    conversation_topic: NotRequired[str]
    action_count: NotRequired[int]

@tool
def set_topic(topic: str, runtime: ToolRuntime[None, ConversationState]) -> Command:
    """Set the current conversation topic."""
    current_count = runtime.state.get("action_count", 0)
    return Command(
        update={
            "conversation_topic": topic,
            "action_count": current_count + 1,
            "messages": [
                ToolMessage(
                    content=f"Conversation topic set to: {topic}",
                    tool_call_id=runtime.tool_call_id,
                )
            ],
        }
    )
```

When multiple tools update the same state field in parallel tool calls, define a reducer:

```python
from typing import Annotated

def append_list(a: list, b: list) -> list:
    return a + b

class AggregatingState(AgentState):
    # This field accumulates values across parallel tool calls
    found_results: Annotated[list[str], append_list]
```

## Long-term memory (store)

Long-term memory persists across different threads via a `BaseStore`. Data is organized
as JSON documents under `namespace` (tuple) + `key`.

```python
from langchain.agents import create_agent
from langgraph.store.memory import InMemoryStore  # dev only

store = InMemoryStore()
agent = create_agent("openai:gpt-5.4", tools=[...], store=store)
```

### Production store

```python
from langgraph.store.postgres import PostgresStore
from langgraph.store.postgres.aio import AsyncPostgresStore

DB_URI = "postgresql://user:pass@host:5432/dbname"

# Sync
with PostgresStore.from_conn_string(DB_URI) as store:
    store.setup()  # auto-creates tables
    agent = create_agent("openai:gpt-5.4", tools=[...], store=store)

# Async
async with AsyncPostgresStore.from_conn_string(DB_URI) as store:
    await store.setup()
    agent = create_agent("openai:gpt-5.4", tools=[...], store=store)
```

### Reading and writing from tools

```python
from langchain.tools import tool, ToolRuntime
from typing import Any

@tool
def save_user_preference(key: str, value: str, runtime: ToolRuntime) -> str:
    """Save a persistent user preference."""
    # Namespace by user ID for isolation
    user_id = runtime.context.user_id if runtime.context else "global"
    runtime.store.put(
        namespace=("prefs", user_id),  # hierarchical namespace tuple
        key=key,
        value={"value": value, "updated_at": "2026-04-25"},
    )
    return f"Saved preference: {key}={value}"

@tool
def get_user_preference(key: str, runtime: ToolRuntime) -> str:
    """Get a stored user preference."""
    user_id = runtime.context.user_id if runtime.context else "global"
    item = runtime.store.get(("prefs", user_id), key)
    if item:
        return f"{key} = {item.value['value']}"
    return f"No preference set for '{key}'"

@tool
def list_user_preferences(runtime: ToolRuntime) -> str:
    """List all stored preferences for this user."""
    user_id = runtime.context.user_id if runtime.context else "global"
    items = runtime.store.list(("prefs", user_id))
    if not items:
        return "No preferences stored."
    return "\n".join(f"{item.key}: {item.value['value']}" for item in items)

@tool
def delete_user_preference(key: str, runtime: ToolRuntime) -> str:
    """Delete a stored preference."""
    user_id = runtime.context.user_id if runtime.context else "global"
    runtime.store.delete(("prefs", user_id), key)
    return f"Deleted preference: {key}"
```

### Store namespace patterns

Use hierarchical tuples for clean data organisation:

```python
# User-scoped preferences
runtime.store.put(("users", user_id, "prefs"), key, value)

# Org-scoped knowledge base
runtime.store.put(("orgs", org_id, "kb"), article_id, {"content": "..."})

# Session-scoped scratch space
runtime.store.put(("sessions", session_id), key, value)

# Global shared data
runtime.store.put(("global", "config"), "settings", {"version": "1.0"})
```

### Cross-session memory example

```python
from dataclasses import dataclass
from langchain.agents import create_agent
from langchain.tools import tool, ToolRuntime
from langgraph.store.memory import InMemoryStore

@dataclass
class UserCtx:
    user_id: str

@tool
def remember(fact: str, runtime: ToolRuntime[UserCtx]) -> str:
    """Remember a fact about the user across conversations."""
    uid = runtime.context.user_id
    existing = runtime.store.get(("memories", uid), "facts")
    facts = existing.value.get("facts", []) if existing else []
    facts.append(fact)
    runtime.store.put(("memories", uid), "facts", {"facts": facts})
    return f"Remembered: {fact}"

@tool
def recall(runtime: ToolRuntime[UserCtx]) -> str:
    """Recall all facts remembered about the user."""
    uid = runtime.context.user_id
    item = runtime.store.get(("memories", uid), "facts")
    if item:
        return "Facts I know about you:\n" + "\n".join(f"- {f}" for f in item.value["facts"])
    return "I don't have any stored memories about you yet."

store = InMemoryStore()

agent = create_agent(
    model="openai:gpt-5.4",
    tools=[remember, recall],
    context_schema=UserCtx,
    store=store,
    system_prompt="You are a personal assistant with persistent memory. Use 'remember' to store important facts, 'recall' to retrieve them.",
)

# Session 1 — establish facts
agent.invoke(
    {"messages": [{"role": "user", "content": "I'm allergic to peanuts and prefer vegetarian food."}]},
    context=UserCtx(user_id="alice"),
)

# Session 2 — facts persist
result = agent.invoke(
    {"messages": [{"role": "user", "content": "What do you know about my dietary preferences?"}]},
    context=UserCtx(user_id="alice"),
)
print(result["messages"][-1].text)
# "You are allergic to peanuts and prefer vegetarian food."
```

## Summarization middleware (context window management)

Automatically compress old messages when approaching token limits:

```python
from langchain.agents.middleware import SummarizationMiddleware

agent = create_agent(
    "openai:gpt-5.4",
    tools=[...],
    checkpointer=InMemorySaver(),  # required for multi-turn memory
    middleware=[
        SummarizationMiddleware(
            model="openai:gpt-5.4-mini",     # cheap model for summarization
            trigger=("tokens", 4000),         # summarize when context > 4000 tokens
            keep=("messages", 20),            # retain last 20 messages
        )
    ]
)
```

`trigger` accepts: `("fraction", 0.8)`, `("tokens", N)`, `("messages", N)`.
Multiple triggers use OR logic: `trigger=[("tokens", 3000), ("messages", 6)]`.

## Filesystem middleware for context management (deepagents)

`FilesystemMiddleware` gives agents an abstract filesystem for managing context. Useful
for coding agents, research agents, or any task with variable-length tool outputs.

```python
from deepagents.middleware.filesystem import FilesystemMiddleware
from deepagents.backends import CompositeBackend, StateBackend, StoreBackend
from langgraph.store.memory import InMemoryStore

store = InMemoryStore()

agent = create_agent(
    "anthropic:claude-sonnet-4-6",
    store=store,
    middleware=[
        FilesystemMiddleware(
            backend=CompositeBackend(
                default=StateBackend(),                    # ephemeral (lost between threads)
                routes={"/memories/": StoreBackend()}      # persistent (survives threads)
            ),
            custom_tool_descriptions={
                "write_file": "Write research notes, analysis results, or scraped content to files.",
                "read_file": "Read previously written notes or results.",
            },
        ),
    ],
)

# Agent has: ls, read_file, write_file, edit_file tools
# /memories/user_prefs.md  → persists across threads (via store)
# /tmp/research.md         → ephemeral (lost when thread ends)
```

## Complete memory example: customer service agent

```python
from dataclasses import dataclass
from typing_extensions import NotRequired
from langchain.agents import AgentState, create_agent
from langchain.agents.middleware import SummarizationMiddleware
from langchain.tools import tool, ToolRuntime
from langchain.messages import ToolMessage
from langgraph.checkpoint.postgres import PostgresSaver
from langgraph.store.postgres import PostgresStore
from langgraph.types import Command

@dataclass
class CustomerCtx:
    customer_id: str

class SupportState(AgentState):
    active_ticket_id: NotRequired[str]

DB_URI = "postgresql://user:pass@host/db"

@tool
def log_interaction(summary: str, runtime: ToolRuntime[CustomerCtx]) -> str:
    """Log this interaction to the customer's history."""
    cid = runtime.context.customer_id
    history = runtime.store.get(("history", cid), "interactions")
    interactions = history.value.get("interactions", []) if history else []
    interactions.append({"summary": summary, "date": "2026-04-25"})
    runtime.store.put(("history", cid), "interactions", {"interactions": interactions})
    return f"Logged interaction for customer {cid}"

@tool
def get_interaction_history(runtime: ToolRuntime[CustomerCtx]) -> str:
    """Get the customer's interaction history."""
    cid = runtime.context.customer_id
    history = runtime.store.get(("history", cid), "interactions")
    if not history:
        return "No previous interactions found."
    items = history.value.get("interactions", [])
    return "\n".join(f"- {i['date']}: {i['summary']}" for i in items[-5:])  # last 5

@tool
def open_ticket(category: str, runtime: ToolRuntime[CustomerCtx, SupportState]) -> Command:
    """Open a new support ticket."""
    import uuid
    ticket_id = str(uuid.uuid4())[:8].upper()
    return Command(
        update={
            "active_ticket_id": ticket_id,
            "messages": [ToolMessage(
                content=f"Ticket #{ticket_id} opened for {category} issue.",
                tool_call_id=runtime.tool_call_id,
            )],
        }
    )

with PostgresSaver.from_conn_string(DB_URI) as checkpointer:
    checkpointer.setup()
    with PostgresStore.from_conn_string(DB_URI) as store:
        store.setup()

        agent = create_agent(
            model="anthropic:claude-sonnet-4-6",
            tools=[log_interaction, get_interaction_history, open_ticket],
            context_schema=CustomerCtx,
            state_schema=SupportState,
            checkpointer=checkpointer,
            store=store,
            system_prompt=(
                "You are a customer support agent. "
                "Check interaction history before responding. "
                "Log important interactions. Open tickets for complex issues."
            ),
            middleware=[
                SummarizationMiddleware(
                    model="openai:gpt-5.4-mini",
                    trigger=("tokens", 8000),
                    keep=("messages", 10),
                ),
            ],
        )
```
