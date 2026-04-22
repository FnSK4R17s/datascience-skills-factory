---
name: langgraph
description: >
  Build, debug, and extend stateful agent graphs with LangGraph v1+.
  Use when code imports langgraph, mentions StateGraph, checkpointer,
  interrupt, streaming modes, or prebuilt agents. Covers graph API,
  state/reducers, persistence, human-in-the-loop interrupts, streaming,
  and when to prefer the Functional API instead.
---

# LangGraph Skill

LangGraph models agent workflows as graphs where nodes do work and edges
control routing. State is persisted as checkpoints, which enables
human-in-the-loop, memory, time travel, and fault tolerance.

## Problem

LangGraph v1 reorganised its API surface significantly. Common failures:

- Wrong state update semantics (overwrite vs. accumulate via reducers)
- Missing checkpointer — persistence and interrupts silently do nothing
- Forgetting `thread_id` in config when using a checkpointer
- Wrapping `interrupt()` in bare `try/except`, swallowing the exception
- Non-idempotent side effects before `interrupt()` double-executing on resume
- Using `Command(update=...)` as invoke input instead of plain dict for
  multi-turn conversations (graph appears stuck)
- Skipping `version="v2"` on stream — format changes unpredictably with
  multiple modes or subgraphs

## Trigger keywords

`StateGraph`, `langgraph`, `checkpointer`, `interrupt`, `create_react_agent`,
`stream_mode`

## When to invoke

- Code imports `langgraph` or `from langgraph.*`
- User asks about StateGraph, nodes, edges, conditional routing
- User asks about checkpointing, thread-level memory, or cross-thread memory
- User asks about human-in-the-loop, approval flows, or pausing graphs
- User asks about streaming from an agent graph (token streaming, updates)
- User asks about `create_react_agent` or prebuilt agents

## When NOT to invoke

- Simple LangChain chain with no graph state (`chain.invoke(...)` only)
- Non-graph agent pipelines (raw LLM + tool loop with no StateGraph)
- LangSmith tracing questions with no graph involvement — use
  langfuse-tracing or LangSmith docs instead

## References map

Load each file only when the user's question touches that area:

| File | Load when |
|------|-----------|
| `references/graph-api.md` | StateGraph, nodes, edges, Command, Send, compile |
| `references/state.md` | TypedDict / Pydantic state, reducers, MessagesState, channels |
| `references/persistence.md` | Checkpointers, threads, get_state, update_state, time travel |
| `references/interrupts.md` | interrupt(), resume, human-in-the-loop, approval workflows |
| `references/streaming.md` | stream_mode, version="v2", get_stream_writer, custom events |
| `references/agents-prebuilt.md` | create_react_agent, when to drop to raw graphs |
| `references/functional-api.md` | @entrypoint / @task, when Functional API beats Graph API |

## Quick orientation

```
StateGraph(State)          # declare schema + reducers
  .add_node("name", fn)   # fn(state) -> partial state dict
  .add_edge("a", "b")     # unconditional
  .add_conditional_edges("a", router_fn)  # fn(state) -> node name
  .compile(checkpointer=..., store=...)   # required before invoke
```

Always pass `{"configurable": {"thread_id": "..."}}` as `config` when
using a checkpointer. Without it the checkpointer cannot save or load state.

## Anti-recommendations

- Do not snapshot pinned API paths. Defer to the official docs via the
  `claude-docs` skill for anything not covered in these references.
- Do not recommend LangSmith as required — it is optional observability.
- Do not conflate `InMemorySaver` (dev only) with production checkpointers
  (`PostgresSaver`, `SqliteSaver`). `InMemorySaver` loses state on restart.
