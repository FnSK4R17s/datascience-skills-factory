---
name: langchain
description: >
  Build agents and LLM applications with LangChain v1+ (Python).
  Use when creating agents with tools, writing middleware, handling structured
  output, streaming agent steps or tokens, or composing multi-agent systems.
  Triggers on: create_agent, LangChain tool calling, LangChain middleware,
  LangChain streaming, LangChain memory.
  SKIP if the user is working with LangGraph directly (StateGraph, nodes/edges)
  without going through create_agent — that is a LangGraph concern. SKIP if they
  ask about LangSmith evaluation or LangGraph Cloud in isolation from agent code.
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
- User asks about RAG, retrieval, vector stores, or embeddings in a LangChain context.
- User asks about multi-agent patterns (subagents, handoffs, routers, skills).
- User asks about short-term or long-term memory (`checkpointer`, `store`).
- User asks about human-in-the-loop approval flows for agents.

## When NOT to invoke

- Pure LangGraph work (StateGraph, custom nodes, edges) — LangGraph skill applies.
- LangSmith tracing/evaluation in isolation from agent code — see langfuse-tracing skill.
- Frontend / React streaming UI (`useStream`, Next.js components) — JS/React concern.
- Deep Agents (`deepagents` package) specific features beyond LangChain middleware.

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
pip install langchain-mcp-adapters  # MCP tool integration
```

Model identifier strings use the `"provider:model"` format (e.g. `"openai:gpt-5.4"`,
`"anthropic:claude-sonnet-4-6"`, `"google_genai:gemini-2.5-flash"`). The provider
prefix can often be omitted when the model name is unambiguous.

## Minimal agent example

```python
from langchain.agents import create_agent

def get_weather(city: str) -> str:
    """Get weather for a city."""
    return f"Sunny in {city}."

agent = create_agent(
    model="openai:gpt-5.4",
    tools=[get_weather],
    system_prompt="You are a helpful assistant.",
)
result = agent.invoke(
    {"messages": [{"role": "user", "content": "Weather in Paris?"}]}
)
# Access text: result["messages"][-1].text
# Access all content: result["messages"][-1].content_blocks
```

## Reference files

| File | Contents |
|------|----------|
| [`references/agents.md`](references/agents.md) | `create_agent` signature, model strings, invocation, `AgentState`, structured output via `response_format`, dynamic model, multi-agent embedding |
| [`references/tools.md`](references/tools.md) | `@tool` decorator, `ToolRuntime` (state/context/store/stream_writer/execution_info), `ToolNode`, return types |
| [`references/middleware.md`](references/middleware.md) | Hook decorators, `AgentMiddleware` class, built-in middleware catalogue, dynamic model/tool patterns |
| [`references/messages.md`](references/messages.md) | Message types, `content_blocks`, multimodal content blocks, `AIMessage` attributes, standard content block reference |
| [`references/streaming.md`](references/streaming.md) | Stream modes (`updates`, `messages`, `custom`), `version="v2"` format, reasoning token streaming, custom updates from tools |
| [`references/structured-output.md`](references/structured-output.md) | `ToolStrategy`, `ProviderStrategy`, schema types, error handling, standalone model structured output |
| [`references/models.md`](references/models.md) | `init_chat_model`, provider config, standalone invocation, tool calling on raw models, token usage, `output_version` |
| [`references/memory.md`](references/memory.md) | Short-term memory (checkpointer, `AgentState`), long-term memory (store), filesystem middleware, summarization |
| [`references/multi-agent.md`](references/multi-agent.md) | Subagents (supervisor), handoffs (state machine), skills (progressive disclosure), router (fan-out), custom workflow |
| [`references/context-engineering.md`](references/context-engineering.md) | Model context, tool context, life-cycle context, `ToolRuntime` data sources, middleware hooks for context control |
| [`references/rag-and-retrieval.md`](references/rag-and-retrieval.md) | Indexing pipeline, agentic RAG tool pattern, two-step RAG chain, building blocks, SQL agent pattern |
| [`references/human-in-the-loop.md`](references/human-in-the-loop.md) | `HumanInTheLoopMiddleware`, interrupt/resume flow, decision types (approve/edit/reject), production patterns |
| [`references/mcp.md`](references/mcp.md) | `MultiServerMCPClient`, transport types (stdio/http/sse), custom MCP servers with FastMCP, stateful sessions |
| [`references/observability-and-testing.md`](references/observability-and-testing.md) | LangSmith tracing, Studio local dev, deployment, unit testing with `GenericFakeChatModel`, integration tests, trajectory evals |

## Short pointers (no dedicated reference)

- **Guardrails** — implemented via middleware (`@before_model`, `@after_model`); built-in
  `PIIMiddleware` covers email/credit card/IP redaction/masking/blocking. Custom guardrails
  use deterministic regex or LLM-as-judge patterns (see `docs/guardrails.md`).
- **Voice agents** — STT > `create_agent` > TTS pipeline; or native multimodal model APIs
  (audio content blocks in messages). See `docs/voice-agent.md`.
- **Context window management** — `SummarizationMiddleware`, `ContextEditingMiddleware`,
  `LLMToolSelectorMiddleware` for large tool sets. All in `references/middleware.md`.
- **Progressive disclosure / skills pattern** — load specialised prompts on-demand via tool
  calls (the `llms.txt` / Agent Skills pattern). See `references/multi-agent.md` and
  `docs/multi-agent__skills-sql-assistant.md`.
- **Frontend integration** — `useStream` hook (JS/React); providers: AI Elements, assistant-ui,
  CopilotKit, OpenUI. Out of scope for this skill — see `docs/frontend__overview.md`.
- **LangSmith Studio** — local visual debugger; requires `langgraph-cli` and a
  `langgraph.json` config. See `references/observability-and-testing.md`.
- **Deployment** — LangSmith managed hosting (LangGraph Cloud); push to GitHub, link repo
  in LangSmith Deployments. See `references/observability-and-testing.md`.
- **Integration catalogue** — 700+ integrations; see `/oss/python/integrations/providers/overview`.
  Provider-specific middleware (Anthropic prompt caching, OpenAI moderation, AWS Bedrock
  caching) at `/oss/python/integrations/middleware/`.
- **Philosophy / history** — LangChain v1.0 shipped 2025-10-20; replaces all chains/agents
  with a single `create_agent` abstraction. `langchain-classic` for legacy code. See
  `docs/philosophy.md`.
- **academy.md** — scraped as an HTML page from a Thinkific LMS; no usable content.
- **changelog-py.md** — scraped as raw HTML; use the live changelog at
  `docs.langchain.com/oss/python/releases/changelog`.

## Anti-recommendations

- Do NOT call `model.bind_tools(...)` before passing the model to `create_agent` when
  using `response_format` — this conflicts with structured output injection.
- Do NOT use `Pydantic` models or dataclasses as `state_schema` — TypedDict only in v1+.
- Do NOT hardcode `message.content` as plain text — use `message.text` or iterate
  `message.content_blocks` to handle reasoning blocks, tool calls, etc.
- Do NOT use `create_react_agent` (LangGraph primitive) when you want the high-level
  LangChain agent factory — use `create_agent` instead.
- Do NOT name tool parameters `config` or `runtime` — these are reserved by `ToolRuntime`.
