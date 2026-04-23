# Observability Reference

Source: `docs/observability.md`

## LangSmith tracing

LangGraph integrates with LangSmith for distributed tracing. Set two environment
variables to enable:

```bash
export LANGSMITH_TRACING=true
export LANGSMITH_API_KEY=<your-key>
```

All `invoke`, `stream`, and `astream` calls are traced automatically. No code changes
needed. Traces capture every node execution, LLM call, tool call, state snapshot, and
token/latency metrics.

## Project routing

```bash
export LANGSMITH_PROJECT=my-agent-project   # static default project
```

Or set dynamically per-call:

```python
import langsmith as ls

with ls.tracing_context(project_name="test-run", enabled=True):
    agent.invoke(inputs)
```

## Selective tracing

Opt in specific invocations when `LANGSMITH_TRACING` is not set globally:

```python
with ls.tracing_context(enabled=True):
    agent.invoke(inputs)   # traced

agent.invoke(inputs)        # not traced
```

## Metadata and tags

```python
agent.invoke(
    inputs,
    config={
        "tags": ["production", "v1"],
        "metadata": {"user_id": "u123", "session_id": "s456"},
    },
)
```

Or via `tracing_context`:

```python
with ls.tracing_context(
    project_name="prod",
    enabled=True,
    tags=["v2"],
    metadata={"env": "production"},
):
    agent.invoke(inputs)
```

## Masking sensitive data

Use `create_anonymizer` to redact PII before it reaches LangSmith:

```python
from langchain_core.tracers.langchain import LangChainTracer
from langsmith import Client
from langsmith.anonymizer import create_anonymizer

anonymizer = create_anonymizer([
    {"pattern": r"\b\d{3}-?\d{2}-?\d{4}\b", "replace": "<ssn>"},
    {"pattern": r"\b[\w.+-]+@[\w-]+\.[a-z]{2,}\b", "replace": "<email>"},
])

tracer = LangChainTracer(client=Client(anonymizer=anonymizer))

graph = (
    StateGraph(MessagesState)
    ...
    .compile()
    .with_config({"callbacks": [tracer]})
)
```

## Studio (local debugging)

LangSmith Studio connects to a locally running `langgraph dev` server and provides:
- Visual graph execution trace (per-node status, state at each step)
- Interactive test runs
- Static breakpoint inspection
- Hot-reload: code changes reflected immediately without restart

Access: `https://smith.langchain.com/studio/?baseUrl=http://127.0.0.1:2024`

## Relationship to langfuse-tracing skill

LangSmith is LangChain's native observability platform, tightly integrated with
LangGraph. For Langfuse (alternative open-source tracing), use the `langfuse-tracing`
skill instead. The two are not interchangeable in this skill — LangSmith-specific
features (Studio, deployment, evaluations) require LangSmith.
