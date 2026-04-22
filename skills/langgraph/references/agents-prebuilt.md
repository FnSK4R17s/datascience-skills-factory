# Prebuilt Agents

LangGraph ships `create_react_agent` as the canonical prebuilt agent.
It wraps the standard ReAct (reason + act) loop into a compiled graph.

## create_react_agent

```python
from langgraph.prebuilt import create_react_agent
from langchain_anthropic import ChatAnthropic
from langchain.tools import tool

@tool
def search(query: str) -> str:
    """Search the web."""
    return f"Results for: {query}"

model = ChatAnthropic(model="claude-sonnet-4-6")
agent = create_react_agent(model, tools=[search])

result = agent.invoke({"messages": [{"role": "user", "content": "What is LangGraph?"}]})
```

The returned agent is a compiled `StateGraph` with `MessagesState`. It is
a graph — you can stream it, add a checkpointer, use interrupts, inspect
state, everything the raw graph API provides.

## With persistence and human-in-the-loop

```python
from langgraph.checkpoint.memory import InMemorySaver

checkpointer = InMemorySaver()
agent = create_react_agent(model, tools=[search], checkpointer=checkpointer)

config = {"configurable": {"thread_id": "session-1"}}
agent.invoke({"messages": [...]}, config)  # thread remembers history
```

For human approval of tool calls, use `interrupt_before`:

```python
agent = create_react_agent(
    model,
    tools=[search],
    checkpointer=checkpointer,
    interrupt_before=["tools"],  # pause before any tool execution
)
```

Alternatively, place `interrupt()` inside a tool function (see
`references/interrupts.md`).

## Streaming from create_react_agent

```python
for chunk in agent.stream(
    {"messages": [{"role": "user", "content": "..."}]},
    stream_mode="messages",
    version="v2",
):
    if chunk["type"] == "messages":
        msg, meta = chunk["data"]
        if msg.content:
            print(msg.content, end="")
```

## Customising the prebuilt agent

`create_react_agent` accepts several hooks for common customisation needs:

- `state_schema` — replace `MessagesState` with a custom schema
- `prompt` — system message string, or a function `(state) -> messages`
- `response_format` — Pydantic model for structured final response
- `pre_model_hook` / `post_model_hook` — callables run before/after LLM call
- `tools` — list of LangChain tools or functions decorated with `@tool`

Example with a custom system prompt:

```python
agent = create_react_agent(
    model,
    tools=[search],
    prompt="You are a helpful assistant. Be concise.",
)
```

Example with custom state:

```python
from langgraph.graph import MessagesState

class AgentState(MessagesState):
    user_id: str
    session_context: dict

agent = create_react_agent(model, tools=[search], state_schema=AgentState)
```

## When to drop to a raw StateGraph

Use `create_react_agent` when the ReAct loop is the right architecture.
Drop to a raw `StateGraph` when:

- You need more than one agent / subgraph with explicit handoffs
- Your control flow is a fixed pipeline, not a tool-calling loop
- You need custom branching logic that doesn't fit pre/post hooks
- You need parallel node execution
- You need to customise the LLM node itself (not just wrap it)

The prebuilt agent is a starting point, not a ceiling. When it feels like
you are fighting the abstraction, replace it with the equivalent raw graph:

```python
from langgraph.graph import StateGraph, MessagesState, START, END

def call_llm(state: MessagesState):
    response = model_with_tools.invoke(state["messages"])
    return {"messages": [response]}

def route_tools(state: MessagesState):
    last = state["messages"][-1]
    if last.tool_calls:
        return "tools"
    return END

from langgraph.prebuilt import ToolNode

graph = (
    StateGraph(MessagesState)
    .add_node("llm", call_llm)
    .add_node("tools", ToolNode(tools=[search]))
    .add_edge(START, "llm")
    .add_conditional_edges("llm", route_tools)
    .add_edge("tools", "llm")
    .compile(checkpointer=checkpointer)
)
```

`ToolNode` is a prebuilt node that executes tool calls from the last
`AIMessage` and returns `ToolMessage` results.
