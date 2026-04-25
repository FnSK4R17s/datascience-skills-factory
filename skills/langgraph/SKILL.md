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

## Minimal working example

```python
from langgraph.graph import StateGraph, MessagesState, START, END

def call_model(state: MessagesState):
    # MessagesState has a single 'messages' key with add_messages reducer
    return {"messages": [{"role": "ai", "content": "hello world"}]}

graph = StateGraph(MessagesState)
graph.add_node(call_model)          # name defaults to function name
graph.add_edge(START, "call_model")
graph.add_edge("call_model", END)
graph = graph.compile()

result = graph.invoke({"messages": [{"role": "user", "content": "hi!"}]})
print(result["messages"][-1].content)   # "hello world"
```

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

## Full calculator agent example (Graph API)

This is a complete working agent from the official quickstart. Source: `docs/quickstart.md`.

```python
from langchain.tools import tool
from langchain.chat_models import init_chat_model
from langchain.messages import AnyMessage, SystemMessage, ToolMessage
from typing_extensions import TypedDict, Annotated
from typing import Literal
from langgraph.graph import StateGraph, START, END
import operator

model = init_chat_model("claude-sonnet-4-6", temperature=0)

@tool
def multiply(a: int, b: int) -> int:
    """Multiply `a` and `b`."""
    return a * b

@tool
def add(a: int, b: int) -> int:
    """Add `a` and `b`."""
    return a + b

@tool
def divide(a: int, b: int) -> float:
    """Divide `a` by `b`."""
    return a / b

tools = [add, multiply, divide]
tools_by_name = {t.name: t for t in tools}
model_with_tools = model.bind_tools(tools)

class MessagesState(TypedDict):
    messages: Annotated[list[AnyMessage], operator.add]
    llm_calls: int

def llm_call(state: MessagesState):
    return {
        "messages": [
            model_with_tools.invoke(
                [SystemMessage(content="You are a helpful math assistant.")] + state["messages"]
            )
        ],
        "llm_calls": state.get("llm_calls", 0) + 1
    }

def tool_node(state: MessagesState):
    results = []
    for tc in state["messages"][-1].tool_calls:
        observation = tools_by_name[tc["name"]].invoke(tc["args"])
        results.append(ToolMessage(content=observation, tool_call_id=tc["id"]))
    return {"messages": results}

def should_continue(state: MessagesState) -> Literal["tool_node", "__end__"]:
    last = state["messages"][-1]
    return "tool_node" if last.tool_calls else END

builder = StateGraph(MessagesState)
builder.add_node("llm_call", llm_call)
builder.add_node("tool_node", tool_node)
builder.add_edge(START, "llm_call")
builder.add_conditional_edges("llm_call", should_continue, ["tool_node", END])
builder.add_edge("tool_node", "llm_call")
agent = builder.compile()

from langchain.messages import HumanMessage
result = agent.invoke({"messages": [HumanMessage(content="Add 3 and 4, then multiply by 2")]})
for m in result["messages"]:
    m.pretty_print()
```

## Full calculator agent example (Functional API)

Same calculator agent using `@entrypoint` / `@task`. Source: `docs/quickstart.md`.

```python
from langchain.tools import tool
from langchain.chat_models import init_chat_model
from langchain.messages import SystemMessage, HumanMessage, ToolCall
from langchain_core.messages import BaseMessage
from langgraph.func import entrypoint, task
from langgraph.graph import add_messages

model = init_chat_model("claude-sonnet-4-6", temperature=0)
tools = [add, multiply, divide]   # same tools as above
tools_by_name = {t.name: t for t in tools}
model_with_tools = model.bind_tools(tools)

@task
def call_llm(messages: list[BaseMessage]):
    return model_with_tools.invoke(
        [SystemMessage(content="You are a helpful math assistant.")] + messages
    )

@task
def call_tool(tool_call: ToolCall):
    return tools_by_name[tool_call["name"]].invoke(tool_call)

@entrypoint()
def agent(messages: list[BaseMessage]):
    model_response = call_llm(messages).result()
    while True:
        if not model_response.tool_calls:
            break
        tool_futures = [call_tool(tc) for tc in model_response.tool_calls]
        tool_results = [f.result() for f in tool_futures]
        messages = add_messages(messages, [model_response, *tool_results])
        model_response = call_llm(messages).result()
    return add_messages(messages, model_response)

# Stream with updates mode
for chunk in agent.stream(
    [HumanMessage(content="Add 3 and 4, then multiply by 2")],
    stream_mode="updates"
):
    print(chunk)
```

## References map

Open the relevant file for detail; each is under `references/`.

| File | Covers |
|------|--------|
| `graph-api.md` | StateGraph, nodes, edges, `Command`, `Send`, node caching, recursion limit, `RemainingSteps` |
| `state.md` | TypedDict / Pydantic state, reducers, `MessagesState`, `add_messages`, `Overwrite`, private channels |
| `persistence.md` | Checkpointers, threads, `get_state`, `update_state`, history, encryption, `StateSnapshot` fields |
| `interrupts.md` | `interrupt()`, `Command(resume=...)`, rules, full pattern examples, static breakpoints |
| `streaming.md` | Stream modes (`values`, `updates`, `messages`, `custom`, `debug`), v2 format, subgraph streaming |
| `functional-api.md` | `@entrypoint`, `@task`, determinism, short-term memory, serialization, `entrypoint.final` |
| `agents-prebuilt.md` | `create_react_agent`, tool binding, custom ReAct agent, workflow patterns |
| `durable-execution.md` | Retries, failure recovery, idempotency, durability modes, tasks in nodes |
| `subgraphs.md` | Composition patterns, parent-child state flow, persistence modes, namespace conflicts |
| `time-travel.md` | Checkpoint replay, forking, `as_node`, subgraph time travel |
| `memory.md` | Short-term (checkpointer), long-term (`Store`), trim/delete/summarize messages, semantic search |
| `pregel.md` | The Pregel execution model, channels, direct `Pregel` API |
| `observability.md` | LangSmith tracing, selective tracing, anonymizers |
| `deployment.md` | Local server (`langgraph dev`), LangSmith Cloud, `langgraph.json` structure |
| `testing.md` | Unit testing graphs, node testing, interrupt testing, partial execution, mocking |

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
- Do not conditionally skip `interrupt()` calls between executions — matching is
  index-based so skipping changes the index of subsequent calls.
  Source: `docs/interrupts.md`.
- Do not put non-deterministic operations (random, `time.time()`) directly in an
  `@entrypoint` body — wrap them in `@task` so results replay on resume.
  Source: `docs/functional-api.md`.
