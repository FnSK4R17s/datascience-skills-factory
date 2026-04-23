---
name: langgraph
description: >
  Build stateful, long-running agent workflows with LangGraph v1 (Python).
  Use when constructing a StateGraph with nodes and edges, wiring up checkpointers
  for persistence or human-in-the-loop, calling interrupt() for approval workflows,
  streaming graph output token-by-token or step-by-step, or choosing between the
  Graph API and Functional API (@entrypoint / @task).
  Triggers: "StateGraph", "langgraph graph", "checkpointer", "interrupt approve",
  "stream_mode langgraph", "create_react_agent".
  SKIP: pure LangChain chains without graph structure; generic Python async; LangSmith
  tracing setup (use langfuse-tracing skill); non-LangGraph orchestrators.
---

# LangGraph v1 Skill

LangGraph is a low-level orchestration framework for stateful, long-running,
agent workflows. It models execution as a directed graph: **nodes** are Python
functions that do work and **edges** route between them based on state.
Source: `docs/overview.md`, `docs/graph-api.md`.

## When to invoke

- Building or debugging a `StateGraph` (nodes, edges, state schema, reducers).
- Adding persistence / conversation memory via a checkpointer.
- Implementing human-in-the-loop with `interrupt()` / `Command(resume=...)`.
- Choosing or converting between the Graph API and Functional API.
- Streaming graph output (`stream_mode="updates"`, `"messages"`, `"custom"`, etc.).
- Using `create_react_agent` or other prebuilt agent factories.

## Skip rules

- LangChain LCEL chains or runnables with no `StateGraph` — no graph needed.
- Pure Python `asyncio` pipelines with no LangGraph imports.
- LangSmith / Langfuse observability setup — use the `langfuse-tracing` skill.
- Simple sequential scripts where `invoke` on a single model is sufficient.

## API choice

Two APIs share the same runtime; pick one and mix freely.

| Need | API |
|------|-----|
| Visual graph, explicit shared state, parallel fan-out | Graph API (`StateGraph`) |
| Minimal boilerplate, standard Python control flow, function-scoped state | Functional API (`@entrypoint` / `@task`) |

Full comparison: `references/functional-api.md`. Source: `docs/choosing-apis.md`.

## References map

Open the relevant file for detail; each is under `references/`.

| File | Covers |
|------|--------|
| `graph-api.md` | StateGraph, nodes, edges, `Command`, `Send`, recursion limit |
| `state.md` | TypedDict / Pydantic state, reducers, `MessagesState`, `add_messages` |
| `persistence.md` | Checkpointers, threads, `get_state`, `update_state`, Store (cross-thread memory) |
| `interrupts.md` | `interrupt()`, `Command(resume=...)`, rules, common patterns |
| `streaming.md` | Stream modes (`values`, `updates`, `messages`, `custom`, `debug`), v2 format |
| `functional-api.md` | `@entrypoint`, `@task`, determinism, short-term memory |
| `agents-prebuilt.md` | `create_react_agent`, tool binding, prebuilt patterns |

## Anti-recommendations

- Do not wrap `interrupt()` in a bare `try/except` — it pauses by raising an
  exception that must propagate. Source: `docs/interrupts.md`.
- Do not use `Command(update=...)` as input to `invoke()` for multi-turn
  conversations — pass a plain dict instead. `Command(resume=...)` is the only
  `Command` pattern valid as `invoke()` input. Source: `docs/graph-api.md`.
- Do not call a `@task` directly from application code — tasks must be called
  from within an `@entrypoint`, another `@task`, or a graph node.
  Source: `docs/functional-api.md`.
- Do not reorder `interrupt()` calls within a node across executions — matching
  is strictly index-based, so changing order mis-routes resume values.
  Source: `docs/interrupts.md`.
- `interrupt()` payloads must be JSON-serializable — no functions, class
  instances, or non-serializable objects. Source: `docs/interrupts.md`.
- `recursion_limit` is a top-level config key, not under `configurable`.
  Source: `docs/graph-api.md`.
