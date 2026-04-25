# Deployment Reference

Source: `docs/local-server.md`, `docs/deploy.md`, `docs/studio.md`, `docs/application-structure.md`

## Local development server

Install the CLI:

```bash
pip install -U "langgraph-cli[inmem]"   # Python >= 3.11 required
```

Create a config file `langgraph.json` in your project root:

```json
{
  "dependencies": ["."],
  "graphs": {
    "agent": "./src/agent.py:agent"
  },
  "env": ".env"
}
```

The `graphs` key maps assistant names to `file:variable` paths. The variable must be
a compiled `Pregel` instance (returned by `StateGraph.compile()` or `@entrypoint`).

Start the dev server:

```bash
langgraph dev
# API at http://127.0.0.1:2024
# Studio at https://smith.langchain.com/studio/?baseUrl=http://127.0.0.1:2024
```

The in-memory server is for development only — state is lost on restart.
Hot-reloading: code changes reflect immediately.

### Multiple graphs in one config

```json
{
  "dependencies": ["."],
  "graphs": {
    "chat_agent": "./src/agents/chat.py:graph",
    "research_agent": "./src/agents/research.py:graph",
    "writer_agent": "./src/agents/writer.py:graph"
  },
  "env": ".env"
}
```

Each graph is accessible as a separate "assistant" via the API.

### Safari compatibility

Safari blocks `localhost` connections. Use `langgraph dev --tunnel` to create a
secure tunnel, then add the tunnel URL in Studio's "Connect to local server" dialog.

## Testing the local API

```python
from langgraph_sdk import get_sync_client   # pip install langgraph-sdk

client = get_sync_client(url="http://localhost:2024")

# List available assistants
assistants = client.assistants.list()
print([a["graph_id"] for a in assistants])

# Threadless run (no persistence)
for chunk in client.runs.stream(
    None,           # threadless run
    "agent",        # name from langgraph.json
    input={"messages": [{"role": "human", "content": "Hello"}]},
    stream_mode="updates",
):
    print(chunk.event, chunk.data)

# With thread (persistent)
thread = client.threads.create()
for chunk in client.runs.stream(
    thread["thread_id"],
    "agent",
    input={"messages": [{"role": "human", "content": "Hello, I'm Alice"}]},
    stream_mode="updates",
):
    print(chunk.event, chunk.data)
```

## Project structure

Recommended layout:

```
my-app/
├── src/
│   └── agent/
│       ├── __init__.py
│       ├── agent.py        # graph construction — exports compiled graph
│       ├── nodes.py        # node functions
│       ├── tools.py        # tool definitions
│       └── state.py        # state TypedDict schemas
├── tests/
│   └── test_agent.py
├── .env
├── pyproject.toml          # or requirements.txt
└── langgraph.json
```

### `agent.py` example

```python
# src/agent/agent.py
from langgraph.graph import StateGraph, MessagesState, START, END
from .nodes import call_model, call_tools
from .state import State

builder = StateGraph(State)
builder.add_node("model", call_model)
builder.add_node("tools", call_tools)
builder.add_edge(START, "model")
# ... edges ...

# This is the variable referenced in langgraph.json
graph = builder.compile()
```

## LangSmith Cloud deployment

Requires: GitHub account, LangSmith account, code passing local `langgraph dev`.

1. Push code to a GitHub repository.
2. In LangSmith, go to **Deployments → + New Deployment**.
3. Connect GitHub account and select repository.
4. Click **Submit** (deployment takes ~15 minutes for initial build).
5. Access Studio from the deployment details view.
6. Copy the API URL and use `langgraph-sdk` with the deployment URL + LangSmith API key.

```python
from langgraph_sdk import get_sync_client

client = get_sync_client(
    url="https://your-deployment.langsmith.com",
    api_key="lsv2_..."   # LangSmith API key
)

# Same API as local client
for chunk in client.runs.stream(
    thread_id,
    "agent",
    input={"messages": [{"role": "human", "content": "Hello"}]},
    stream_mode="updates",
):
    print(chunk.event, chunk.data)
```

LangSmith Cloud is purpose-built for stateful, long-running agents — handles
infrastructure, scaling, checkpointing, and persistent storage automatically.

## `langgraph.json` reference

| Key | Required | Description |
|-----|----------|-------------|
| `dependencies` | Yes | Package source paths (usually `["."]`) |
| `graphs` | Yes | `{"name": "path:var"}` for each graph |
| `env` | No | Path to `.env` file |
| `store` | No | Store configuration (e.g. semantic search settings) |

### Store config example for semantic search

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

## Environment variables for deployment

```bash
# LangSmith observability (optional but recommended)
LANGSMITH_TRACING=true
LANGSMITH_API_KEY=lsv2_...
LANGSMITH_PROJECT=my-project

# LLM providers
ANTHROPIC_API_KEY=sk-ant-...
OPENAI_API_KEY=sk-...

# Database (if using PostgreSQL checkpointer)
DATABASE_URL=postgresql://user:password@host:5432/dbname

# Checkpoint encryption (optional)
LANGGRAPH_AES_KEY=...    # enables automatic encryption at rest
```

## Frontend integration

LangGraph exposes a streaming HTTP API consumed by frontend `useStream` hooks
(`@langchain/react`). Frontend patterns (visualizing graph pipelines, HITL UI) are
outside the scope of this Python skill.

The **Agent Chat UI** (`github.com/langchain-ai/agent-chat-ui`) is an open-source
Next.js app that wraps any LangGraph agent with a chat interface, tool visualization,
and time-travel debugging:

```bash
npx create-agent-chat-app
# Prompts for your LangGraph server URL (local or cloud)
```

Features:
- Real-time streaming chat interface
- Tool call visualization
- Message history browsing
- Time-travel debugging via the UI
- Human-in-the-loop interrupt handling
