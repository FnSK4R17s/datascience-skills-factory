<p align="center">
  <img src="logo.png" alt="langchain" height="88">
</p>

<h1 align="center">langchain</h1>

<p align="center">
  <strong>Build agents and LLM applications with LangChain v1+ (Python).</strong><br>
  <sub>Part of <a href="../../">Data Science Skills Factory</a></sub>
</p>

---

LangChain v1 is a significant API break. The primary entry point is
`create_agent` (not `create_react_agent`, which is a LangGraph primitive).
Agents run on LangGraph internally; the middleware system replaces the old
chain/callback-hook model. The `content_blocks` property normalises
provider-specific formats (Anthropic `thinking`, OpenAI `reasoning_summary`)
into a single representation.

This skill guides an agent through the v1 surface: `create_agent`, `@tool` +
`ToolRuntime`, middleware hooks, messages + content blocks, structured output,
streaming, memory, multi-agent patterns, RAG, MCP integration,
human-in-the-loop, and observability.

## Install

```bash
npx skills add FnSK4R17s/datascience-skills-factory --skill langchain
```

## File structure

```
langchain/
├── SKILL.md                              # Entry point, triggers, decision tree
├── README.md                             # This file
├── logo.png                              # Brand mark
└── references/
    ├── agents.md                         # create_agent, system_prompt, tools
    ├── tools.md                          # @tool, ToolRuntime, state/context/store
    ├── middleware.md                     # @before_model, @after_model, @wrap_*
    ├── messages.md                       # HumanMessage, AIMessage, content_blocks
    ├── models.md                         # init_chat_model, provider wiring
    ├── structured-output.md              # response_format, ToolStrategy
    ├── streaming.md                      # stream_mode, version="v2"
    ├── memory.md                         # checkpointer (short-term), Store (long-term)
    ├── multi-agent.md                    # subagents, handoffs, routers
    ├── rag-and-retrieval.md              # vector stores, embeddings, retrievers
    ├── mcp.md                            # MultiServerMCPClient integration
    ├── human-in-the-loop.md              # HumanInTheLoopMiddleware, interrupts
    ├── context-engineering.md            # prompt design for agents
    └── observability-and-testing.md      # LangSmith, agentevals
```

## When the skill fires

- Code imports `langchain`, `langchain-core`, or `langchain-classic`.
- The user asks about `create_agent`, tool calling, middleware, structured
  output, streaming agent steps, memory, or multi-agent composition.
- An agent is being debugged — wrong messages, missing tool calls, stuck
  streams, middleware ordering issues.

## When it should NOT fire

- Pure LangGraph work (StateGraph, custom nodes, edges) — use the
  `langgraph` skill.
- LangSmith tracing setup alone — use `langfuse-tracing` (or the vendor
  docs).
- File imports only the raw OpenAI / Anthropic SDK with no LangChain
  wrapper.
