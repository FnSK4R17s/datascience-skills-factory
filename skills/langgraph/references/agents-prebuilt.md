# Prebuilt Agents Reference

Source: `docs/overview.md`, `docs/workflows-agents.md`, `docs/quickstart.md`

## `create_react_agent` / `create_agent`

The fastest way to build a tool-calling agent. Returns a compiled LangGraph graph.
In LangChain v1, this is exposed as both `create_agent` and `create_react_agent`.

```python
from langchain.agents import create_agent   # or create_react_agent
from langchain.chat_models import init_chat_model
from langchain.tools import tool

model = init_chat_model("claude-sonnet-4-6")

@tool
def search(query: str) -> str:
    """Search the web for information."""
    return f"Search results for: {query}"

@tool
def calculator(expression: str) -> str:
    """Evaluate a math expression."""
    return str(eval(expression))

agent = create_agent(model, tools=[search, calculator])
result = agent.invoke({"messages": [{"role": "user", "content": "What is 25 * 48?"}]})
print(result["messages"][-1].content)
```

`create_agent` implements a standard ReAct loop: LLM call → if tool call, run tool →
append result → loop. It returns a `Pregel` instance compatible with all LangGraph
streaming and persistence features.

### With persistent memory

```python
from langgraph.checkpoint.memory import InMemorySaver
from langgraph.checkpoint.postgres import PostgresSaver  # for production

checkpointer = InMemorySaver()   # use PostgresSaver in production
agent = create_agent(model, tools=[search], checkpointer=checkpointer)
config = {"configurable": {"thread_id": "user-session-1"}}

# First message
agent.invoke(
    {"messages": [{"role": "user", "content": "hi, I'm Alice"}]},
    config
)
# Second message — agent remembers "I'm Alice"
result = agent.invoke(
    {"messages": [{"role": "user", "content": "what's my name?"}]},
    config
)
print(result["messages"][-1].content)   # "Your name is Alice."
```

### With system prompt

```python
agent = create_agent(
    model,
    tools=[search, calculator],
    prompt="You are a helpful research assistant. Always cite sources.",
)
```

### Streaming with prebuilt agent

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

### Token streaming from prebuilt agent

```python
for chunk in agent.stream(
    {"messages": [{"role": "user", "content": "Tell me about AI"}]},
    config,
    stream_mode="messages",
    version="v2",
):
    if chunk["type"] == "messages":
        msg, meta = chunk["data"]
        if msg.content:
            print(msg.content, end="", flush=True)
```

## Custom ReAct agent with Graph API

When `create_agent` is not flexible enough (custom routing, special state, extra
nodes), build a ReAct loop directly.

```python
from langchain.chat_models import init_chat_model
from langchain.tools import tool
from langchain.messages import ToolMessage
from langgraph.graph import StateGraph, MessagesState, START, END
from typing import Literal

model = init_chat_model("claude-sonnet-4-6")

@tool
def search(query: str) -> str:
    """Search for information."""
    return f"Results for: {query}"

@tool
def get_weather(city: str) -> str:
    """Get weather for a city."""
    return f"Sunny, 72F in {city}"

tools = [search, get_weather]
tools_by_name = {t.name: t for t in tools}
model_with_tools = model.bind_tools(tools)

def call_llm(state: MessagesState):
    response = model_with_tools.invoke(state["messages"])
    return {"messages": [response]}

def call_tools(state: MessagesState):
    tool_calls = state["messages"][-1].tool_calls
    results = []
    for tc in tool_calls:
        result = tools_by_name[tc["name"]].invoke(tc["args"])
        results.append(ToolMessage(content=str(result), tool_call_id=tc["id"]))
    return {"messages": results}

def should_continue(state: MessagesState) -> Literal["tools", "__end__"]:
    last = state["messages"][-1]
    return "tools" if last.tool_calls else END

builder = StateGraph(MessagesState)
builder.add_node("agent", call_llm)
builder.add_node("tools", call_tools)
builder.add_edge(START, "agent")
builder.add_conditional_edges("agent", should_continue)
builder.add_edge("tools", "agent")
graph = builder.compile()

result = graph.invoke({"messages": [{"role": "user", "content": "What's the weather in Paris?"}]})
for m in result["messages"]:
    m.pretty_print()
```

## Custom ReAct agent with Functional API

Same pattern using `@entrypoint` and `@task`:

```python
from langchain.chat_models import init_chat_model
from langchain.messages import SystemMessage, HumanMessage, ToolCall
from langchain_core.messages import BaseMessage
from langgraph.func import entrypoint, task
from langgraph.graph import add_messages

model = init_chat_model("claude-sonnet-4-6")
tools = [search, get_weather]
tools_by_name = {t.name: t for t in tools}
model_with_tools = model.bind_tools(tools)

@task
def call_llm(messages: list[BaseMessage]):
    return model_with_tools.invoke(
        [SystemMessage(content="You are a helpful assistant.")] + messages
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
        # Execute all tool calls in parallel
        tool_futures = [call_tool(tc) for tc in model_response.tool_calls]
        tool_results = [f.result() for f in tool_futures]
        messages = add_messages(messages, [model_response, *tool_results])
        model_response = call_llm(messages).result()

    return add_messages(messages, model_response)
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
builder.add_node("branch_a", branch_a_fn)
builder.add_node("branch_b", branch_b_fn)
builder.add_edge("branch_a", END)
builder.add_edge("branch_b", END)
```

### Parallel fan-out

```python
# Both run in the same super-step (same checkpoint boundary)
builder.add_edge(START, "node_a")
builder.add_edge(START, "node_b")
```

### Map-reduce

```python
from langgraph.types import Send
from typing import Annotated
from operator import add

class OverallState(TypedDict):
    subjects: list[str]
    results: Annotated[list[str], add]   # reducer collects from all workers

def dispatch(state):
    return [Send("process", {"item": x}) for x in state["subjects"]]

builder.add_conditional_edges("collect", dispatch)
builder.add_edge("process", "aggregate")
```

### Loop with exit condition (ReAct-style)

```python
def should_retry(state) -> Literal["retry", "__end__"]:
    return "retry" if state["needs_retry"] else END

builder.add_conditional_edges("act", should_retry)
builder.add_edge("retry", "act")
```

## Tool binding

```python
from langchain.tools import tool
from langchain.chat_models import init_chat_model

@tool
def multiply(a: int, b: int) -> int:
    """Multiply two numbers together.

    Args:
        a: First number
        b: Second number
    """
    return a * b

@tool
def search_web(query: str, max_results: int = 5) -> list[str]:
    """Search the web for information.

    Args:
        query: The search query
        max_results: Maximum number of results to return
    """
    # ... implementation
    return [f"Result {i} for {query}" for i in range(max_results)]

model = init_chat_model("claude-sonnet-4-6")
model_with_tools = model.bind_tools([multiply, search_web])

# Use StructuredTool for class-based tools
from langchain.tools import StructuredTool
from pydantic import BaseModel

class DatabaseQueryInput(BaseModel):
    table: str
    limit: int = 10

def run_query(table: str, limit: int = 10) -> list[dict]:
    return []   # implementation

db_tool = StructuredTool.from_function(
    func=run_query,
    name="database_query",
    description="Query a database table",
    args_schema=DatabaseQueryInput,
)
```

## Accessing agent state between runs

```python
from langgraph.checkpoint.memory import InMemorySaver

checkpointer = InMemorySaver()
agent = create_agent(model, tools=[search], checkpointer=checkpointer)
config = {"configurable": {"thread_id": "session-1"}}

agent.invoke({"messages": [{"role": "user", "content": "Remember that my name is Alice"}]}, config)

# Inspect state
state = agent.get_state(config)
print(state.values["messages"][-1].content)

# View full history
for snap in agent.get_state_history(config):
    print(snap.metadata["step"], snap.next)
```
