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

LangChain v1 shipped 2025-10-20. It is a significant API break from earlier releases.
The primary entry point is `create_agent` (not `create_react_agent`, which is a
LangGraph primitive). Agents are built on LangGraph internally; the middleware system
replaces the old chain/callback-hook model. The `content_blocks` property normalises
provider-specific formats (Anthropic `thinking`, OpenAI `reasoning_summary`) into a
single representation.

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
- User asks about testing agents (unit tests, integration tests, trajectory evals).
- User asks about LangSmith tracing / observability.

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
  keys instead of mode-specific tuple unpacking. Requires `langgraph>=1.1`.
- `ToolRuntime` replaces direct `config` injection; reserved argument names `config` and
  `runtime` cannot be used as tool parameters.
- Middleware replaces callbacks for cross-cutting concerns (logging, retries, guardrails,
  dynamic prompts, dynamic tool selection).
- Custom state via middleware (`state_schema` on `AgentMiddleware`) is preferred over
  `state_schema` on `create_agent` for state logically scoped to a middleware.

## Installation

```bash
pip install -U langchain          # Python 3.10+
pip install -U langchain-openai   # per-provider packages
pip install -U langchain-anthropic
pip install -U "langchain[google-genai]"
pip install langchain-mcp-adapters  # MCP tool integration
pip install langgraph-checkpoint-postgres  # production checkpointer
```

Model identifier strings use the `"provider:model"` format:
- `"openai:gpt-5.4"` or just `"gpt-5.4"` (auto-inferred)
- `"anthropic:claude-sonnet-4-6"` or just `"claude-sonnet-4-6"`
- `"google_genai:gemini-2.5-flash-lite"`
- `"bedrock_converse:anthropic.claude-3-5-sonnet-20240620-v1:0"` (pass
  `model_provider="bedrock_converse"` explicitly)

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

## Production agent example

```python
from langchain.agents import create_agent, AgentState
from langchain.agents.middleware import (
    SummarizationMiddleware,
    HumanInTheLoopMiddleware,
    ModelFallbackMiddleware,
    PIIMiddleware,
)
from langgraph.checkpoint.postgres import PostgresSaver
from langgraph.store.postgres import PostgresStore
from dataclasses import dataclass

@dataclass
class UserContext:
    user_id: str
    role: str

DB_URI = "postgresql://user:pass@host:5432/dbname"

with PostgresSaver.from_conn_string(DB_URI) as checkpointer:
    checkpointer.setup()
    with PostgresStore.from_conn_string(DB_URI) as store:
        store.setup()

        agent = create_agent(
            model="anthropic:claude-sonnet-4-6",
            tools=[get_weather, search_database],
            system_prompt="You are a helpful assistant.",
            context_schema=UserContext,
            checkpointer=checkpointer,
            store=store,
            middleware=[
                SummarizationMiddleware(
                    model="openai:gpt-5.4-mini",
                    trigger=("tokens", 80000),
                    keep=("messages", 20),
                ),
                ModelFallbackMiddleware("openai:gpt-5.4"),
                PIIMiddleware("email", strategy="redact", apply_to_input=True),
            ],
        )
```

## Reference files

| File | Contents |
|------|----------|
| [`references/agents.md`](references/agents.md) | `create_agent` full signature, invocation, `AgentState`, custom state, structured output (`response_format`), dynamic model, multi-agent embedding, context patterns |
| [`references/tools.md`](references/tools.md) | `@tool` decorator, `ToolRuntime` (state/context/store/stream_writer/execution_info/server_info), `ToolNode`, return types, error handling, prebuilt tools |
| [`references/middleware.md`](references/middleware.md) | Hook decorators, `AgentMiddleware` class, `ExtendedModelResponse`, state updates, agent jumps, execution order, all built-in middleware with full config, custom patterns |
| [`references/messages.md`](references/messages.md) | Message types, `content_blocks`, multimodal content blocks, `AIMessage` attributes, streaming chunks, standard content block reference |
| [`references/streaming.md`](references/streaming.md) | Stream modes (`updates`, `messages`, `custom`), `version="v2"` format, reasoning token streaming, custom updates from tools, multi-agent streaming, HITL during streaming |
| [`references/structured-output.md`](references/structured-output.md) | `ToolStrategy`, `ProviderStrategy`, schema types (Pydantic/dataclass/TypedDict/JSON Schema/Union), error handling with full conversation traces |
| [`references/models.md`](references/models.md) | `init_chat_model`, provider config, standalone invocation, tool calling, structured output, token usage, model profiles, `output_version` |
| [`references/memory.md`](references/memory.md) | Short-term memory (checkpointer, `AgentState`), long-term memory (store), filesystem middleware, summarization, production backends |
| [`references/multi-agent.md`](references/multi-agent.md) | Pattern comparison table, subagents (supervisor), handoffs, skills, router (fan-out), custom workflow, performance characteristics |
| [`references/context-engineering.md`](references/context-engineering.md) | Model context, tool context, life-cycle context, `ToolRuntime` data sources, middleware hooks for context control, dynamic tool selection |
| [`references/rag-and-retrieval.md`](references/rag-and-retrieval.md) | Full indexing pipeline with all vector store options, agentic RAG tool pattern, two-step RAG chain, indirect prompt injection defenses, SQL agent |
| [`references/human-in-the-loop.md`](references/human-in-the-loop.md) | `HumanInTheLoopMiddleware` config, interrupt/resume flow, approve/edit/reject decisions, multiple simultaneous interrupts, streaming with HITL |
| [`references/mcp.md`](references/mcp.md) | `MultiServerMCPClient`, transport types (stdio/http), custom MCP servers with FastMCP, stateful sessions, tool interceptors, resources, prompts, progress notifications, elicitation |
| [`references/observability-and-testing.md`](references/observability-and-testing.md) | LangSmith tracing, metadata/tags, Studio local dev, deployment, unit testing with `GenericFakeChatModel`, integration tests, trajectory evals (agentevals) |

## Short pointers (no dedicated reference)

- **Guardrails** — implemented via middleware (`@before_model`, `@after_model`,
  `@after_agent`); built-in `PIIMiddleware` covers email/credit card/IP/MAC/URL
  redaction/masking/hashing/blocking. Custom guardrails use deterministic regex or
  LLM-as-judge patterns in `after_agent` hooks. Use `get_stream_writer()` to stream
  guardrail evaluation results. See `docs/guardrails.md`.
- **Voice agents** — STT > `create_agent` > TTS pipeline; or native multimodal model APIs
  (audio content blocks in messages). See `docs/voice-agent.md`.
- **Context window management** — `SummarizationMiddleware` compresses history;
  `ContextEditingMiddleware` clears old tool outputs; `LLMToolSelectorMiddleware` for
  large tool sets. All documented in `references/middleware.md`.
- **Progressive disclosure / skills pattern** — load specialised prompts on-demand via
  tool calls (the `llms.txt` / Agent Skills pattern). See `references/multi-agent.md`.
- **Frontend integration** — `useStream` hook (JS/React); providers: AI Elements,
  assistant-ui, CopilotKit, OpenUI. Out of scope for this skill — see
  `docs/frontend__overview.md`.
- **LangSmith Studio** — local visual debugger; requires `langgraph-cli[inmem]` and a
  `langgraph.json` config. `langgraph dev` starts the local server. See
  `references/observability-and-testing.md`.
- **Deployment** — LangSmith managed hosting (LangGraph Cloud); push to GitHub, link repo
  in LangSmith Deployments. See `references/observability-and-testing.md`.
- **Integration catalogue** — 700+ integrations; see
  `/oss/python/integrations/providers/overview`. Provider-specific middleware
  (Anthropic prompt caching, OpenAI moderation, AWS Bedrock caching) at
  `/oss/python/integrations/middleware/`.
- **Philosophy / history** — LangChain v1.0 shipped 2025-10-20; replaces all
  chains/agents with a single `create_agent` abstraction. `langchain-classic` for legacy
  code. See `docs/philosophy.md`.
- **academy.md / changelog-py.md** — scraped as HTML from Thinkific/changelog page;
  use the live changelog at `docs.langchain.com/oss/python/releases/changelog`.

## Anti-recommendations

- Do NOT call `model.bind_tools(...)` before passing the model to `create_agent` when
  using `response_format` — this conflicts with structured output injection.
- Do NOT use `Pydantic` models or dataclasses as `state_schema` — TypedDict only in v1+.
- Do NOT hardcode `message.content` as plain text — use `message.text` or iterate
  `message.content_blocks` to handle reasoning blocks, tool calls, etc.
- Do NOT use `create_react_agent` (LangGraph primitive) when you want the high-level
  LangChain agent factory — use `create_agent` instead.
- Do NOT name tool parameters `config` or `runtime` — these are reserved by `ToolRuntime`.
- Do NOT skip `version="v2"` when streaming with multiple modes — without it you must
  unpack `(mode, data)` tuples which is less ergonomic.
- Do NOT use `InMemorySaver`/`InMemoryStore` in production — use Postgres equivalents.
- Do NOT add tools to a model with `bind_tools` then pass it to `create_agent` alongside
  `response_format` — let `create_agent` manage tool binding.
