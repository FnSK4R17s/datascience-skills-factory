# Deployment Reference

Source: `docs/local-server.md`, `docs/deploy.md`, `docs/studio.md`, `docs/application-structure.md`, `docs/frontend__overview.md`

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

The in-memory server is for development only. It does not persist state between
restarts. Hot-reloading: code changes reflect immediately.

### Safari compatibility

Safari blocks `localhost` connections. Use `langgraph dev --tunnel` to create a
secure tunnel, then add the tunnel URL in Studio's "Connect to local server" dialog.

### Testing the API

```python
from langgraph_sdk import get_sync_client   # pip install langgraph-sdk

client = get_sync_client(url="http://localhost:2024")

for chunk in client.runs.stream(
    None,       # threadless run
    "agent",    # name from langgraph.json
    input={"messages": [{"role": "human", "content": "Hello"}]},
    stream_mode="updates",
):
    print(chunk.event, chunk.data)
```

## Project structure

Recommended layout:

```
my-app/
├── my_agent/
│   ├── __init__.py
│   ├── agent.py        # graph construction
│   ├── nodes.py        # node functions
│   ├── tools.py        # tool definitions
│   └── state.py        # state TypedDict
├── .env
├── requirements.txt    # or pyproject.toml
└── langgraph.json
```

## LangSmith Cloud deployment

Requires: GitHub account, LangSmith account, code passing local `langgraph dev`.

1. Push code to a GitHub repository.
2. In LangSmith, go to **Deployments → + New Deployment**.
3. Connect GitHub account and select repository.
4. Click **Submit** (deployment takes ~15 minutes).
5. Access Studio from the deployment details view.
6. Copy the API URL and use `langgraph-sdk` with the deployment URL + LangSmith API key.

```python
client = get_sync_client(url="https://your-deployment.langsmith.com",
                          api_key="lsv2_...")
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

Store config example for semantic search:

```json
{
  "store": {
    "index": {
      "embed": "openai:text-embeddings-3-small",
      "dims": 1536,
      "fields": ["$"]
    }
  }
}
```

## Frontend integration (pointer)

LangGraph exposes a streaming API consumed by frontend `useStream` hooks
(`@langchain/react`). Frontend patterns (visualizing graph pipelines, HITL UI) are
outside the scope of this Python skill. See `docs/frontend__overview.md` and the
LangChain frontend docs for JavaScript/React usage of `useStream`.

The **Agent Chat UI** (`github.com/langchain-ai/agent-chat-ui`) is an open-source
Next.js app that wraps any LangGraph agent with a chat interface, tool visualization,
and time-travel debugging. Start it with `npx create-agent-chat-app`.
