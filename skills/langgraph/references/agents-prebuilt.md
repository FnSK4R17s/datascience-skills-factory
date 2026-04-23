# Prebuilt Agents Reference

Source: `docs/overview.md`, `docs/workflows-agents.md`, `docs/quickstart.md`

## `create_react_agent` (LangChain)

The fastest way to build a tool-calling agent. Returns a compiled LangGraph graph.

```python
from langchain.agents import create_agent
from langchain.chat_models import init_chat_model

model = init_chat_model("claude-sonnet-4-6")

@tool
def search(query: str) -> str:
    """Search the web."""
    return f"Results for {query}"

agent = create_agent(model, tools=[search])
result = agent.invoke({"messages": [{"role": "user", "content": "Find latest news"}]})
```

`create_agent` (also exposed as `create_react_agent` in LangChain) implements a
standard ReAct loop: LLM call → if tool call, run tool → append result → loop.
It returns a `Pregel` instance (compiled graph) compatible with all LangGraph
streaming and persistence features.

### With memory

```python
from langgraph.checkpoint.memory import InMemorySaver

agent = create_agent(model, tools=[search], checkpointer=InMemorySaver())
config = {"configurable": {"thread_id": "user-session-1"}}

agent.invoke({"messages": [{"role": "user", "content": "hi, I'm Alice"}]}, config)
agent.invoke({"messages": [{"role": "user", "content": "what's my name?"}]}, config)
```

### With system prompt

```python
agent = create_agent(
    model,
    tools=[search],
    prompt="You are a helpful research assistant. Always cite sources.",
)
```

### Streaming

```python
for chunk in agent.stream(
    {"messages": [{"role": "user", "content": "Search for LangGraph"}]},
    config,
    stream_mode="updates",
    version="v2",
):
    if chunk["type"] == "updates":
        print(chunk["data"])
```

## Custom agent with Graph API

When `create_agent` is not flexible enough, build a custom ReAct agent:

```python
from langgraph.graph import StateGraph, MessagesState, START, END

def call_llm(state: MessagesState):
    response = model.invoke(state["messages"])
    return {"messages": [response]}

def call_tools(state: MessagesState):
    tool_calls = state["messages"][-1].tool_calls
    results = [tools_by_name[tc["name"]].invoke(tc) for tc in tool_calls]
    return {"messages": results}

def should_continue(state: MessagesState) -> Literal["tools", "__end__"]:
    last = state["messages"][-1]
    return "tools" if last.tool_calls else "__end__"

builder = StateGraph(MessagesState)
builder.add_node("agent", call_llm)
builder.add_node("tools", call_tools)
builder.add_edge(START, "agent")
builder.add_conditional_edges("agent", should_continue)
builder.add_edge("tools", "agent")
graph = builder.compile()
```

## Workflow patterns

### Sequential pipeline

```python
builder.add_edge(START, "step_a")
builder.add_edge("step_a", "step_b")
builder.add_edge("step_b", END)
```

### Conditional branching

```python
def route(state) -> Literal["branch_a", "branch_b"]:
    return "branch_a" if state["flag"] else "branch_b"

builder.add_conditional_edges("router", route)
```

### Parallel fan-out

```python
# Both run in the same super-step
builder.add_edge(START, "node_a")
builder.add_edge(START, "node_b")
```

### Map-reduce

```python
from langgraph.types import Send

def dispatch(state):
    return [Send("process", {"item": x}) for x in state["items"]]

builder.add_conditional_edges("collect", dispatch)
builder.add_edge("process", "aggregate")
```

### Loop with exit condition

```python
def should_retry(state) -> Literal["retry", "__end__"]:
    return "retry" if state["needs_retry"] else "__end__"

builder.add_conditional_edges("act", should_retry)
builder.add_edge("retry", "act")
```

## Tool binding

```python
from langchain.tools import tool
from langchain.chat_models import init_chat_model

@tool
def multiply(a: int, b: int) -> int:
    """Multiply two numbers."""
    return a * b

model = init_chat_model("claude-sonnet-4-6")
model_with_tools = model.bind_tools([multiply])
```

`bind_tools` registers tool schemas with the model so it can generate tool call
requests. Use `@tool` decorator for functions or `StructuredTool` for class-based tools.
