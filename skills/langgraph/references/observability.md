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

# Multiple calls in same project
with ls.tracing_context(project_name="production"):
    result1 = agent.invoke(inputs1)
    result2 = agent.invoke(inputs2)
```

## Selective tracing

Opt in specific invocations when `LANGSMITH_TRACING` is not set globally:

```python
import langsmith as ls

with ls.tracing_context(enabled=True):
    agent.invoke(inputs)   # traced

agent.invoke(inputs)        # not traced

# Or disable for a specific call even when global tracing is on
with ls.tracing_context(enabled=False):
    agent.invoke(inputs)    # not traced
```

## Metadata and tags

Tags and metadata help filter and organize traces in the LangSmith UI.

```python
agent.invoke(
    inputs,
    config={
        "tags": ["production", "v2", "experiment-a"],
        "metadata": {
            "user_id": "u123",
            "session_id": "s456",
            "feature_flag": "new_router",
        },
    },
)

# Or via tracing_context
with ls.tracing_context(
    project_name="prod",
    enabled=True,
    tags=["v2"],
    metadata={"env": "production"},
):
    agent.invoke(inputs)
```

Tags appear in the LangSmith filter sidebar. Metadata is searchable. Both can be
used to group traces by deployment, experiment, or user segment.

## Masking sensitive data

Use `create_anonymizer` to redact PII before it reaches LangSmith.

```python
from langchain_core.tracers.langchain import LangChainTracer
from langsmith import Client
from langsmith.anonymizer import create_anonymizer

anonymizer = create_anonymizer([
    {"pattern": r"\b\d{3}-?\d{2}-?\d{4}\b", "replace": "<ssn>"},
    {"pattern": r"\b[\w.+-]+@[\w-]+\.[a-z]{2,}\b", "replace": "<email>"},
    {"pattern": r"\b\d{16}\b", "replace": "<credit_card>"},
])

tracer = LangChainTracer(client=Client(anonymizer=anonymizer))

graph = (
    StateGraph(MessagesState)
    .add_node("agent", agent_fn)
    .add_edge(START, "agent")
    .compile()
    .with_config({"callbacks": [tracer]})
)

# All traces from this graph will have PII redacted
graph.invoke({"messages": [{"role": "user", "content": "My SSN is 123-45-6789"}]})
```

## Studio (local debugging)

LangSmith Studio connects to a locally running `langgraph dev` server and provides:
- Visual graph execution trace (per-node status, state at each step)
- Interactive test runs
- Static breakpoint inspection
- Hot-reload: code changes reflected immediately without restart

Access: `https://smith.langchain.com/studio/?baseUrl=http://127.0.0.1:2024`

### Safari compatibility

Safari blocks `localhost` connections. Use `langgraph dev --tunnel` to create a
secure tunnel, then add the tunnel URL in Studio's "Connect to local server" dialog.

## LangSmith evaluations

After tracing, run evaluations to measure agent quality:

```python
from langsmith import evaluate

def is_helpful(run, example):
    """Check if the agent response is helpful."""
    response = run.outputs["messages"][-1].content
    # ... scoring logic
    return {"score": 0.8, "reasoning": "response was helpful"}

results = evaluate(
    target=agent.invoke,
    data="my-eval-dataset",
    evaluators=[is_helpful],
    experiment_prefix="v2-experiment",
)
```

## Relationship to langfuse-tracing skill

LangSmith is LangChain's native observability platform, tightly integrated with
LangGraph. For Langfuse (alternative open-source tracing), use the `langfuse-tracing`
skill instead. The two are not interchangeable in this skill — LangSmith-specific
features (Studio, deployment, evaluations) require LangSmith.
