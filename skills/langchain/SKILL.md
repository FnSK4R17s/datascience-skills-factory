---
name: langchain
description: >
  Build agents and LLM applications with LangChain v1+ (Python).
  Use when creating agents with tools, writing middleware, handling structured
  output, streaming agent steps or tokens, or composing multi-agent systems.
  Triggers on: create_agent, langchain agent, LangChain tool calling,
  LangChain middleware, LangChain structured output.
  SKIP if the user is working with LangGraph directly (graph nodes/edges, StateGraph)
  without going through create_agent — that is a LangGraph concern. SKIP if they ask
  about LangSmith evaluation, LangSmith observability, or LangGraph Studio.
---

# LangChain v1+ (Python)

LangChain v1 is a significant API break from earlier releases. The primary entry
point is `create_agent` (not `create_react_agent`, which is a LangGraph primitive).
Agents are built on LangGraph internally; the middleware system replaces the old
chain/callback-hook model. The `content_blocks` property is new and normalises
provider-specific formats (Anthropic `thinking`, OpenAI `reasoning_summary`) into
a single representation.

## When to invoke

- User is creating or modifying an agent (`create_agent`, tools, `system_prompt`).
- User is writing or debugging middleware (`@before_model`, `@after_model`,
  `@wrap_model_call`, `@wrap_tool_call`, `@dynamic_prompt`, `AgentMiddleware`).
- User asks about structured output from an agent (`response_format`, `ToolStrategy`,
  `ProviderStrategy`).
- User is streaming agent progress or LLM tokens (`stream_mode`, `version="v2"`).
- User is defining tools (`@tool`, `ToolRuntime`, state/context/store access).
- User asks about MCP integration with LangChain agents.

## When NOT to invoke

- Pure LangGraph work (StateGraph, custom nodes, edges) — LangGraph skill applies.
- LangSmith tracing, evaluation, or experiment management — Langfuse or LangSmith docs.
- Frontend / React streaming UI — covered by LangChain's frontend docs, not this skill.
- Deep Agents (`deepagents` package) specific features.

## Reference files

| File | Contents |
|------|----------|
| [`references/agents.md`](references/agents.md) | `create_agent` signature, model strings, invocation, `AgentState`, structured output via `response_format` |
| [`references/tools.md`](references/tools.md) | `@tool` decorator, `ToolRuntime` (state/context/store/stream_writer), `ToolNode`, return types |
| [`references/middleware.md`](references/middleware.md) | Hook decorators, `AgentMiddleware`, built-in middleware catalogue, dynamic model/tool patterns |
| [`references/messages.md`](references/messages.md) | Message types, `content_blocks`, multimodal content blocks, `AIMessage` attributes |
| [`references/streaming.md`](references/streaming.md) | Stream modes (`updates`, `messages`, `custom`), `version="v2"` format, reasoning token streaming |
| [`references/structured-output.md`](references/structured-output.md) | `ToolStrategy`, `ProviderStrategy`, schema types, error handling |

## Key v1 API breaks (training data is likely wrong)

- `create_agent` replaces `create_react_agent` as the high-level agent factory.
- Response text is in `message.content_blocks` (list of typed dicts), not `message.content`.
  `message.text` is a convenience property for the plain-text portion.
- State schemas passed to `create_agent` must be `TypedDict` — Pydantic models and
  dataclasses are no longer accepted for state (they still work for tool schemas and
  structured output).
- Streaming: pass `version="v2"` for a unified `StreamPart` dict with `type`/`ns`/`data`
  keys instead of mode-specific tuple unpacking.
- `ToolRuntime` replaces direct `config` injection; reserved argument names `config` and
  `runtime` cannot be used as tool parameters.
- Middleware replaces callbacks for cross-cutting concerns (logging, retries, guardrails,
  dynamic prompts, dynamic tool selection).

## Installation

```bash
pip install -U langchain          # Python 3.10+
pip install -U langchain-openai   # per-provider packages
pip install -U langchain-anthropic
```

Model identifier strings use the `"provider:model"` format (e.g. `"openai:gpt-4o"`,
`"anthropic:claude-sonnet-4-6"`, `"google_genai:gemini-2.5-flash"`). The provider
prefix can often be omitted when the model name is unambiguous.

## Minimal agent example

```python
from langchain.agents import create_agent

def get_weather(city: str) -> str:
    """Get weather for a city."""
    return f"Sunny in {city}."

agent = create_agent(
    model="openai:gpt-4o",
    tools=[get_weather],
    system_prompt="You are a helpful assistant.",
)
result = agent.invoke(
    {"messages": [{"role": "user", "content": "Weather in Paris?"}]}
)
# Access text: result["messages"][-1].text
# Access all content: result["messages"][-1].content_blocks
```

See `references/agents.md` for structured output, custom state, and streaming.
