# Observability and Testing

Source: `docs/observability.md`, `docs/test__unit-testing.md`,
`docs/test__integration-testing.md`, `docs/test__evals.md`

## LangSmith tracing

All `create_agent` agents emit LangSmith traces automatically — no code changes needed.
Traces capture every model call, tool execution, and decision point.

```bash
export LANGSMITH_TRACING=true
export LANGSMITH_API_KEY=<your-api-key>
export LANGSMITH_PROJECT=my-agent-project  # optional; defaults to "default"
```

### Quickstart

```python
from langchain.agents import create_agent

def search_web(query: str) -> str:
    """Search the web for information."""
    return f"Results for: {query}"

def send_email(to: str, subject: str, body: str) -> str:
    """Send an email."""
    return f"Email sent to {to}"

agent = create_agent(
    model="openai:gpt-5.4",
    tools=[search_web, send_email],
    system_prompt="You can search the web and send emails.",
)

# Every step is traced automatically — no extra code
result = agent.invoke({
    "messages": [{"role": "user", "content": "Search for AI news and email a summary to alice@example.com"}]
})
```

View traces at `smith.langchain.com`.

### Selective tracing

Trace specific invocations without enabling global tracing:

```python
import langsmith as ls

# Trace only this block
with ls.tracing_context(enabled=True, project_name="my-experiment"):
    result = agent.invoke({"messages": [{"role": "user", "content": "Hello"}]})

# This won't be traced (when LANGSMITH_TRACING is not set)
result = agent.invoke({"messages": [{"role": "user", "content": "Hello again"}]})
```

### Metadata and tags

Annotate traces for filtering in the LangSmith UI:

```python
result = agent.invoke(
    {"messages": [{"role": "user", "content": "Search for Python tutorials"}]},
    config={
        "tags": ["production", "search-agent", "v2.1"],
        "metadata": {
            "user_id": "user-123",
            "session_id": "session-456",
            "environment": "production",
            "experiment": "new-prompt-v3",
        },
    },
)

# Or via tracing_context for fine-grained control
with ls.tracing_context(
    project_name="ab-test-new-prompt",
    tags=["variant-b"],
    metadata={"experiment_id": "exp-042"},
):
    result = agent.invoke({"messages": [{"role": "user", "content": "..."}]})
```

### LangSmith Studio (local dev)

Studio provides a visual graph debugger for local development:

```bash
pip install "langgraph-cli[inmem]"
langgraph dev   # starts local agent server + connects to Studio UI
```

Requires a `langgraph.json` config pointing at your agent module. Studio shows
the graph structure, step-by-step execution, and supports interactive testing.
With `LANGSMITH_TRACING=false` no data leaves your machine.

### Deployment (LangGraph Cloud)

Deploy to LangSmith managed hosting from a GitHub repository:
1. Push agent code to GitHub.
2. In LangSmith UI: Deployments → New Deployment → link the repo → Submit.
3. Use the deployment API URL to query your agent from any client.

---

## Unit testing (no API calls)

Use `GenericFakeChatModel` to script exact LLM responses — deterministic, free, fast.
No API keys needed.

### Scripting tool calls and text responses

```python
from langchain_core.language_models.fake_chat_models import GenericFakeChatModel
from langchain.messages import AIMessage, HumanMessage, ToolMessage
from langchain_core.messages.tool import ToolCall
from langchain.agents import create_agent
from langchain.tools import tool

@tool
def get_weather(city: str) -> str:
    """Get the weather for a city."""
    return f"Sunny, 72°F in {city}"

# Script exact model responses: first call makes a tool call, second gives the answer
model = GenericFakeChatModel(messages=iter([
    AIMessage(
        content="",
        tool_calls=[
            ToolCall(name="get_weather", args={"city": "San Francisco"}, id="call_1")
        ],
    ),
    AIMessage(content="The weather in San Francisco is sunny and 72°F."),
]))

agent = create_agent(model, tools=[get_weather])
result = agent.invoke({"messages": [HumanMessage(content="Weather in SF?")]})

assert "sunny" in result["messages"][-1].text.lower()
assert any(
    tc["name"] == "get_weather"
    for msg in result["messages"]
    if hasattr(msg, "tool_calls")
    for tc in (msg.tool_calls or [])
)
```

The fake model returns one item per `invoke()` call in iterator order.

### Multi-turn unit tests with InMemorySaver

Test state-dependent behavior across multiple conversation turns:

```python
from langgraph.checkpoint.memory import InMemorySaver
from langchain_core.language_models.fake_chat_models import GenericFakeChatModel
from langchain.messages import AIMessage, HumanMessage
from langchain.agents import create_agent

model = GenericFakeChatModel(messages=iter([
    AIMessage(content="Nice to meet you, Alice! I'll remember that."),
    AIMessage(content="Your name is Alice."),
]))

agent = create_agent(model, tools=[], checkpointer=InMemorySaver())
config = {"configurable": {"thread_id": "test-session-1"}}

# Turn 1: tell the agent the user's name
agent.invoke(
    {"messages": [HumanMessage(content="My name is Alice.")]},
    config=config,
)

# Turn 2: agent should recall it (state persisted by checkpointer)
result = agent.invoke(
    {"messages": [HumanMessage(content="What is my name?")]},
    config=config,
)
assert "Alice" in result["messages"][-1].text
```

### Testing custom state and middleware

```python
from langchain_core.language_models.fake_chat_models import GenericFakeChatModel
from langchain.messages import AIMessage
from langchain.agents import AgentState, create_agent
from langchain.agents.middleware import AgentMiddleware
from typing import Any
from typing_extensions import NotRequired

class CountingState(AgentState):
    call_count: NotRequired[int]

class CountingMiddleware(AgentMiddleware):
    state_schema = CountingState

    def before_model(self, state: CountingState, runtime) -> dict[str, Any] | None:
        return {"call_count": state.get("call_count", 0) + 1}

model = GenericFakeChatModel(messages=iter([
    AIMessage(content="Hello!"),
    AIMessage(content="Hello again!"),
]))

agent = create_agent(model, tools=[], middleware=[CountingMiddleware()])

r1 = agent.invoke({"messages": [{"role": "user", "content": "Hi"}]})
assert r1.get("call_count") == 1

r2 = agent.invoke({"messages": [{"role": "user", "content": "Hi again"}]})
assert r2.get("call_count") == 1  # new invocation resets to 0, then increments
```

---

## Integration testing (real API calls)

Integration tests make real network calls to confirm credentials, model behavior,
and latency. Keep them separate from unit tests.

### Separate unit and integration tests

```python
# tests/integration/test_weather_agent.py
import pytest
from langchain.agents import create_agent
from langchain.messages import AIMessage, HumanMessage
from langchain.tools import tool

@tool
def get_weather(city: str) -> str:
    """Get weather for a city."""
    return "Sunny, 72°F"

@pytest.mark.integration
def test_agent_calls_weather_tool():
    """Requires OPENAI_API_KEY; run with: pytest -m integration"""
    agent = create_agent(
        "openai:gpt-5.4",
        tools=[get_weather],
        model_kwargs={"max_tokens": 256},  # cap to reduce cost
    )
    result = agent.invoke({"messages": [HumanMessage(content="Weather in SF?")]})

    messages = result["messages"]
    tool_calls = [
        tc
        for msg in messages
        if hasattr(msg, "tool_calls")
        for tc in (msg.tool_calls or [])
    ]

    assert any(tc["name"] == "get_weather" for tc in tool_calls)
    assert isinstance(messages[-1], AIMessage)
    assert len(messages[-1].text) > 0
```

Register the marker and exclude by default in `pyproject.toml`:

```toml
[tool.pytest.ini_options]
markers = ["integration: tests that call real LLM APIs"]
addopts = "-m 'not integration'"
```

Run integration tests explicitly:

```bash
pytest -m integration
```

### Manage API keys

```python
# tests/conftest.py
import os
import pytest
from dotenv import load_dotenv

load_dotenv()  # load from .env

@pytest.fixture(autouse=True)
def require_openai_key():
    if not os.environ.get("OPENAI_API_KEY"):
        pytest.skip("OPENAI_API_KEY not set")
```

### Assert on structure, not content

LLM responses are nondeterministic. Assert on structural properties:

```python
def test_agent_response_structure():
    agent = create_agent("openai:gpt-5.4", tools=[get_weather])
    result = agent.invoke({"messages": [{"role": "user", "content": "Weather in Paris?"}]})

    messages = result["messages"]
    assert len(messages) > 1                           # at least user + response
    assert isinstance(messages[-1], AIMessage)         # ends with AI message
    assert len(messages[-1].text) > 0                  # non-empty response
    # Don't assert exact text — it varies between runs
```

### Record and replay HTTP calls

For CI pipelines, use `vcrpy` to record real API calls once and replay them:

```bash
pip install vcrpy pytest-recording
```

```python
# conftest.py — filter credentials from cassettes
@pytest.fixture(scope="session")
def vcr_config():
    return {
        "filter_headers": [("authorization", "REDACTED"), ("x-api-key", "REDACTED")],
        "filter_query_parameters": [("api_key", "REDACTED")],
    }
```

```toml
# pyproject.toml
[tool.pytest.ini_options]
addopts = "--record-mode=once"   # record on first run, replay after
```

```python
@pytest.mark.vcr()
def test_agent_trajectory_recorded():
    agent = create_agent("claude-sonnet-4-6", tools=[get_weather])
    result = agent.invoke({"messages": [{"role": "user", "content": "Weather in SF?"}]})
    assert any(
        tc["name"] == "get_weather"
        for msg in result["messages"]
        if hasattr(msg, "tool_calls")
        for tc in (msg.tool_calls or [])
    )
# On first run: makes real API call, saves cassette to tests/cassettes/
# On subsequent runs: replays cassette — no API cost or latency
```

When you change a prompt or tool, delete the cassette file and re-record.

---

## Trajectory evals (agentevals)

Evals measure agent quality by assessing the trajectory (sequence of messages and
tool calls). Unlike integration tests that verify basic correctness, evals score
behavior against a reference or rubric for regression tracking.

```bash
pip install agentevals
```

### Trajectory match evaluator

Deterministic, fast, free — checks that specific tool calls appear.

| Mode | Description | Use case |
|------|-------------|----------|
| `strict` | Exact match: same message structure and tool calls in the same order | Enforce required sequences |
| `unordered` | Same tool calls, any order | Verify retrieval without ordering assumptions |
| `subset` | Agent only calls tools from the reference | Ensure agent doesn't exceed scope |
| `superset` | Agent calls at least the reference tools (extras allowed) | Verify minimum required actions |

```python
from langchain.agents import create_agent
from langchain.tools import tool
from langchain.messages import HumanMessage, AIMessage, ToolMessage
from agentevals.trajectory.match import create_trajectory_match_evaluator

@tool
def get_weather(city: str) -> str:
    """Get weather for a city."""
    return f"75°F and sunny in {city}"

agent = create_agent("claude-sonnet-4-6", tools=[get_weather])

# Strict match: exact sequence required
strict_evaluator = create_trajectory_match_evaluator(trajectory_match_mode="strict")

def test_weather_strict():
    result = agent.invoke({"messages": [HumanMessage(content="Weather in SF?")]})

    reference = [
        HumanMessage(content="Weather in SF?"),
        AIMessage(content="", tool_calls=[
            {"id": "call_1", "name": "get_weather", "args": {"city": "San Francisco"}}
        ]),
        ToolMessage(content="75°F and sunny in San Francisco.", tool_call_id="call_1"),
        AIMessage(content="The weather in SF is 75°F and sunny."),
    ]

    evaluation = strict_evaluator(
        outputs=result["messages"],
        reference_outputs=reference,
    )
    # {"key": "trajectory_strict_match", "score": True, "comment": None}
    assert evaluation["score"] is True


# Superset match: reference tool calls must appear; extras allowed
superset_evaluator = create_trajectory_match_evaluator(trajectory_match_mode="superset")

def test_weather_superset():
    result = agent.invoke({"messages": [HumanMessage(content="Tell me about SF weather")]})

    reference = [
        HumanMessage(content="Tell me about SF weather"),
        AIMessage(content="", tool_calls=[
            {"id": "call_1", "name": "get_weather", "args": {"city": "San Francisco"}}
        ]),
    ]
    evaluation = superset_evaluator(
        outputs=result["messages"],
        reference_outputs=reference,
    )
    assert evaluation["score"] is True  # passes even if agent also called other tools
```

### Unordered match for parallel tool calls

```python
@tool
def get_events(city: str) -> str:
    """Get events happening in a city."""
    return f"Concert at the park in {city} tonight."

agent = create_agent("claude-sonnet-4-6", tools=[get_weather, get_events])

unordered_evaluator = create_trajectory_match_evaluator(trajectory_match_mode="unordered")

def test_parallel_tools_any_order():
    result = agent.invoke({"messages": [HumanMessage(content="What's happening in SF today?")]})

    reference = [
        HumanMessage(content="What's happening in SF today?"),
        AIMessage(content="", tool_calls=[
            {"id": "call_1", "name": "get_events", "args": {"city": "SF"}},
            {"id": "call_2", "name": "get_weather", "args": {"city": "SF"}},
        ]),
        ToolMessage(content="Concert at the park in SF tonight.", tool_call_id="call_1"),
        ToolMessage(content="75°F and sunny in SF.", tool_call_id="call_2"),
        AIMessage(content="75°F and sunny. Concert at the park tonight."),
    ]
    evaluation = unordered_evaluator(
        outputs=result["messages"],
        reference_outputs=reference,
    )
    assert evaluation["score"] is True  # passes regardless of which tool was called first
```

### LLM-as-judge evaluator

Qualitative assessment — no reference trajectory required.

```python
from agentevals.trajectory.llm import (
    create_trajectory_llm_as_judge,
    TRAJECTORY_ACCURACY_PROMPT,
    TRAJECTORY_ACCURACY_PROMPT_WITH_REFERENCE,
)

# Without reference — judge evaluates based on task completion
judge = create_trajectory_llm_as_judge(
    model="openai:o3-mini",
    prompt=TRAJECTORY_ACCURACY_PROMPT,
)

def test_trajectory_quality():
    result = agent.invoke({"messages": [HumanMessage(content="Weather in Seattle?")]})
    evaluation = judge(outputs=result["messages"])
    # {"key": "trajectory_accuracy", "score": True, "comment": "Agent correctly used get_weather..."}
    assert evaluation["score"] is True


# With reference — judge compares against expected trajectory
judge_with_ref = create_trajectory_llm_as_judge(
    model="openai:o3-mini",
    prompt=TRAJECTORY_ACCURACY_PROMPT_WITH_REFERENCE,
)

evaluation = judge_with_ref(
    outputs=result["messages"],
    reference_outputs=reference,
)
```

### Async evals

```python
from agentevals.trajectory.llm import create_async_trajectory_llm_as_judge, TRAJECTORY_ACCURACY_PROMPT
from agentevals.trajectory.match import create_async_trajectory_match_evaluator

async_judge = create_async_trajectory_llm_as_judge(
    model="openai:o3-mini",
    prompt=TRAJECTORY_ACCURACY_PROMPT,
)
async_match = create_async_trajectory_match_evaluator(trajectory_match_mode="strict")

async def test_async_trajectory():
    result = await agent.ainvoke({"messages": [HumanMessage(content="Weather?")]})
    evaluation = await async_judge(outputs=result["messages"])
    assert evaluation["score"] is True
```

### Run evals in LangSmith with pytest integration

Log evaluation results for experiment tracking over time:

```bash
export LANGSMITH_API_KEY="your-key"
export LANGSMITH_TRACING=true
```

```python
import pytest
from langsmith import testing as t
from agentevals.trajectory.llm import create_trajectory_llm_as_judge, TRAJECTORY_ACCURACY_PROMPT

trajectory_judge = create_trajectory_llm_as_judge(
    model="openai:o3-mini",
    prompt=TRAJECTORY_ACCURACY_PROMPT,
)

@pytest.mark.langsmith
def test_trajectory_logged_to_langsmith():
    result = agent.invoke({"messages": [HumanMessage(content="Weather in SF?")]})

    t.log_inputs({"question": "Weather in SF?"})
    t.log_outputs({"messages": result["messages"]})

    evaluation = trajectory_judge(outputs=result["messages"])
    assert evaluation["score"] is True

# Run: pytest test_evals.py --langsmith-output
```

### Run evals over a LangSmith dataset

```python
from langsmith import Client
from agentevals.trajectory.llm import create_trajectory_llm_as_judge, TRAJECTORY_ACCURACY_PROMPT

client = Client()

judge = create_trajectory_llm_as_judge(
    model="openai:o3-mini",
    prompt=TRAJECTORY_ACCURACY_PROMPT,
)

def run_agent(inputs: dict) -> list:
    result = agent.invoke(inputs)
    return result["messages"]

# Dataset must have input: {"messages": [...]} and output: {"messages": [...]}
experiment_results = client.evaluate(
    run_agent,
    data="my-weather-agent-dataset",
    evaluators=[judge],
)
```

---

## When to use each approach

| Approach | Speed | Cost | Deterministic | When to use |
|----------|-------|------|---------------|-------------|
| Unit test with `GenericFakeChatModel` | Very fast | Free | Yes | Logic, state, middleware, tools |
| Integration test with real model | Slow | Low | No | Credential validation, smoke tests |
| Integration test with `vcrpy` | Fast (after recording) | Free (after recording) | Yes | CI regression tests |
| Trajectory match eval | Fast | Free | Yes | Regression: verify required tool calls |
| LLM-as-judge eval | Slow | Low-medium | No | Quality assessment, prompt comparison |
