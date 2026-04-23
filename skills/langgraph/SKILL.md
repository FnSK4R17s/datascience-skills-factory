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

LangGraph is a low-level orchestration framework for stateful, long-running, agent
workflows. It models execution as a directed graph: **nodes** are Python functions that
do work, **edges** route between them, and **state** is a shared data structure every
node reads from and writes to. The underlying runtime is Pregel (bulk-synchronous
parallel), which schedules nodes in discrete super-steps.
Source: `docs/overview.md`, `docs/graph-api.md`, `docs/pregel.md`.

Install: `pip install -U langgraph`

## When to invoke

- Building or debugging a `StateGraph` (nodes, edges, state schema, reducers).
- Adding persistence / conversation memory via a checkpointer.
- Implementing human-in-the-loop with `interrupt()` / `Command(resume=...)`.
- Choosing or converting between the Graph API and Functional API.
- Streaming graph output (`stream_mode="updates"`, `"messages"`, `"custom"`, etc.).
- Using `create_react_agent` or other prebuilt agent factories.
- Composing graphs as subgraphs, map-reduce with `Send`, or time-travel debugging.
- Durable execution: retries, failure recovery, idempotency patterns.
- Cross-thread long-term memory via the `Store` interface.

## Skip rules

- LangChain LCEL chains or runnables with no `StateGraph` — no graph needed.
- Pure Python `asyncio` pipelines with no LangGraph imports.
- LangSmith / Langfuse observability setup alone — use the `langfuse-tracing` skill.
- Simple sequential scripts where `invoke` on a single model is sufficient.
- Frontend/JavaScript streaming (the `useStream` hook) — not graph-authoring.
- Agent Chat UI setup (Next.js app) — not graph-authoring Python.

## API choice

Two APIs share the same runtime; pick one and mix freely.

| Need | API |
|------|-----|
| Visual graph, explicit shared state, parallel fan-out, conditional routing | Graph API (`StateGraph`) |
| Minimal boilerplate, standard Python control flow, function-scoped state | Functional API (`@entrypoint` / `@task`) |

Full comparison: `references/functional-api.md`. Source: `docs/choosing-apis.md`.

## Conceptual framing

- **Workflow** = predetermined code path (nodes always run in a fixed order).
- **Agent** = dynamic; the LLM decides which node/tool to call next.
- LangGraph supports both. Source: `docs/workflows-agents.md`.

Design approach: map your process to discrete steps (nodes), sketch transitions
(edges), identify shared data (state keys), then add persistence and interrupts where
needed. Source: `docs/thinking-in-langgraph.md`.

## References map

Open the relevant file for detail; each is under `references/`.

| File | Covers |
|------|--------|
| `graph-api.md` | StateGraph, nodes, edges, `Command`, `Send`, node caching, recursion limit |
| `state.md` | TypedDict / Pydantic state, reducers, `MessagesState`, `add_messages`, `Overwrite` |
| `persistence.md` | Checkpointers, threads, `get_state`, `update_state`, history, encryption |
| `interrupts.md` | `interrupt()`, `Command(resume=...)`, rules, common patterns, static breakpoints |
| `streaming.md` | Stream modes (`values`, `updates`, `messages`, `custom`, `debug`), v2 format |
| `functional-api.md` | `@entrypoint`, `@task`, determinism, short-term memory, serialization |
| `agents-prebuilt.md` | `create_react_agent`, tool binding, prebuilt patterns |
| `durable-execution.md` | Retries, failure recovery, idempotency, durability modes |
| `subgraphs.md` | Composition patterns, parent-child state flow, persistence modes |
| `time-travel.md` | Checkpoint replay, forking, `as_node`, subgraph time travel |
| `memory.md` | Short-term (checkpointer), long-term (`Store`), trim/delete/summarize messages |
| `pregel.md` | The Pregel execution model, channels, direct `Pregel` API |
| `observability.md` | LangSmith tracing, selective tracing, anonymizers |
| `deployment.md` | Local server (`langgraph dev`), LangSmith Cloud, `langgraph.json` structure |
| `testing.md` | Unit testing graphs, node testing, interrupt testing patterns |

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
- Do not place non-idempotent side effects before `interrupt()` inside a node —
  the node re-runs from the start on resume, duplicating the side effect.
  Source: `docs/interrupts.md`, `docs/durable-execution.md`.
- Do not compile a per-thread subgraph (`checkpointer=True`) and call it in
  parallel — same-namespace checkpoint writes conflict.
  Source: `docs/use-subgraphs.md`.
