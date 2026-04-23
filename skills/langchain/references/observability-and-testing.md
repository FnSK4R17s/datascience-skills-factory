# Observability and Testing

Source: `docs/observability.md`, `docs/deploy.md`, `docs/studio.md`, `docs/test__index.md`,
`docs/test__unit-testing.md`, `docs/test__integration-testing.md`, `docs/test__evals.md`

## LangSmith tracing

All `create_agent` agents automatically emit LangSmith traces. Enable with env vars:

```bash
export LANGSMITH_TRACING=true
export LANGSMITH_API_KEY=<your-key>
# Optional: custom project name
export LANGSMITH_PROJECT=my-project
```

No code changes needed. Traces capture every model call, tool execution, and decision.
View at `smith.langchain.com`.

## LangSmith Studio (local dev)

Studio provides a visual UI for inspecting and interacting with local agents:

```bash
pip install "langgraph-cli[inmem]"
langgraph dev  # starts local agent server + connects to Studio
```

Requires a `langgraph.json` config pointing at your agent module. Studio shows
graph structure, step-by-step execution, and allows interactive testing. With
`LANGSMITH_TRACING=false` no data leaves your local machine.

## Deployment

Deploy to LangSmith managed hosting (LangGraph Cloud) from a GitHub repository:
1. Push agent code to GitHub
2. LangSmith Deployments → New Deployment → link repo → Submit
3. Use the deployment API URL to query your agent from any client

## Unit testing (no API calls)

Use `GenericFakeChatModel` to script exact LLM responses:

```python
from langchain_core.language_models.fake_chat_models import GenericFakeChatModel
from langchain.messages import AIMessage, ToolCall
from langchain.agents import create_agent
from langgraph.checkpoint.memory import InMemorySaver

model = GenericFakeChatModel(messages=iter([
    # First call: model requests tool use
    AIMessage(content="", tool_calls=[
        ToolCall(name="get_weather", args={"city": "SF"}, id="call_1")
    ]),
    # Second call: model gives final answer
    AIMessage(content="It's sunny in San Francisco."),
]))

agent = create_agent(model, tools=[get_weather])
result = agent.invoke({"messages": [{"role": "user", "content": "Weather in SF?"}]})
assert "sunny" in result["messages"][-1].text
```

For multi-turn tests, pass a `checkpointer=InMemorySaver()` and use the same `thread_id`.

## Integration testing

```python
import pytest

@pytest.mark.integration
def test_agent_with_real_llm():
    """Requires API key; run with: pytest -m integration"""
    from langchain.agents import create_agent
    agent = create_agent("claude-sonnet-4-6", tools=[get_weather])
    result = agent.invoke({"messages": [{"role": "user", "content": "Weather in Paris?"}]})
    assert len(result["messages"]) > 1
    assert result["messages"][-1].text
```

Keep integration tests in a separate directory and mark them so they don't run in fast
unit test suites.

## Trajectory evals (agentevals)

```bash
pip install agentevals
```

```python
from agentevals import create_trajectory_match_evaluator

# Deterministic match — checks that specific tool calls appear
evaluator = create_trajectory_match_evaluator(mode="superset")
score = evaluator(
    outputs={"messages": agent_result["messages"]},
    reference_outputs={"messages": expected_messages},
)
print(score)  # {"key": "trajectory_match", "score": True/False}
```

Modes:
- `"exact"` — trajectory must match reference exactly
- `"superset"` — reference tool calls must all appear (extras allowed)
- `"subset"` — agent calls must all be in reference
- `"unordered"` — same calls, any order

### LLM-as-judge eval

```python
from agentevals import create_llm_as_judge_evaluator

judge = create_llm_as_judge_evaluator(
    model="openai:gpt-5.4",
    rubric="Did the agent complete the task correctly and concisely?",
)
score = judge(outputs={"messages": result["messages"]})
print(score)  # {"key": "llm_judge", "score": 0.0–1.0}
```

Use trajectory match for fast regression checks; LLM-as-judge for qualitative assessment.
