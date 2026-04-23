<p align="center">
  <img src="logo.png" alt="langgraph" height="88">
</p>

<h1 align="center">langgraph</h1>

<p align="center">
  <strong>Build stateful, long-running agent workflows with LangGraph v1 (Python).</strong><br>
  <sub>Part of <a href="../../">Data Science Skills Factory</a></sub>
</p>

---

LangGraph models agent execution as a directed graph: **nodes** are Python
functions that do work, **edges** route between them, and **state** is a
shared data structure every node reads from and writes to. The underlying
runtime is Pregel — bulk-synchronous parallel — which schedules nodes in
discrete super-steps.

This skill covers the v1 API surface end to end: the Graph API, state +
reducers, checkpoint-based persistence, human-in-the-loop interrupts,
streaming (with the v2 event format), durable execution, subgraphs, time
travel, cross-thread memory, the Functional API, Pregel internals,
observability, deployment, and testing.

## Install

```bash
npx skills add FnSK4R17s/datascience-skills-factory --skill langgraph
```

## File structure

```
langgraph/
├── SKILL.md                    # Entry point, triggers, decision tree
├── README.md                   # This file
├── logo.png                    # Brand mark
└── references/
    ├── graph-api.md            # StateGraph, nodes, edges, Command, Send
    ├── state.md                # TypedDict / Pydantic, reducers, add_messages
    ├── persistence.md          # checkpointers, threads, get/update state
    ├── interrupts.md           # interrupt(), Command(resume=), HITL rules
    ├── streaming.md            # modes (values/updates/messages/debug/custom)
    ├── agents-prebuilt.md      # create_react_agent, ToolNode
    ├── functional-api.md       # @entrypoint, @task, Graph vs Functional
    ├── durable-execution.md    # durability modes, determinism, retries
    ├── subgraphs.md            # composition, parent-child state, namespaces
    ├── time-travel.md          # replay, fork, as_node
    ├── memory.md               # short-term management, long-term Store
    ├── pregel.md               # super-step model, channels, direct API
    ├── observability.md        # LangSmith tracing, anonymizers
    ├── deployment.md           # local server, langgraph.json, Cloud
    └── testing.md              # graph factory, node isolation, interrupt tests
```

## When the skill fires

- Code imports `langgraph`, constructs a `StateGraph`, or references nodes
  and edges.
- User asks about checkpointers, persistence, `interrupt()` / resume,
  stream modes, subgraphs, time travel, or the Functional API.
- User is choosing between Graph API and Functional API, or between raw
  LangGraph and prebuilt agents.

## When it should NOT fire

- Pure LangChain agent work going through `create_agent` without custom
  graph structure — use the `langchain` skill.
- Generic Python async orchestration with no graph model.
- LangSmith evaluation setup in isolation — use `langfuse-tracing` or the
  vendor docs.
