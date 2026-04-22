# Agents

LangChain v1 agents are built on LangGraph. The primary entry point for
simple tool-calling agents is `create_react_agent` from `langgraph.prebuilt`.
For complex control flow, use the LangGraph state machine API directly.

## The tool-calling loop

A LangChain agent runs a loop:
1. LLM receives the conversation (system + messages + tool schemas).
2. LLM either returns a final answer or emits one or more tool calls.
3. For each tool call, the runtime invokes the tool and appends a
   `ToolMessage` with the result.
4. Loop back to step 1 until the LLM returns a final answer (no tool calls).

The `create_react_agent` prebuilt encodes this loop as a LangGraph graph.

## Defining tools

```python
from langchain_core.tools import tool

@tool
def search_web(query: str) -> str:
    """Search the web and return a snippet of results."""
    # Implementation here
    return f"Results for: {query}"

@tool
def calculator(expression: str) -> float:
    """Evaluate a mathematical expression. Input must be a valid Python expression."""
    return eval(expression, {"__builtins__": {}})
```

The docstring becomes the tool description in the model's context. Keep it
accurate and specific — vague descriptions lead to incorrect tool selection.

Pydantic-typed tools (for complex inputs):

```python
from langchain_core.tools import BaseTool
from pydantic import BaseModel, Field

class SearchInput(BaseModel):
    query: str = Field(description="The search query")
    max_results: int = Field(default=5, description="Number of results to return")

@tool(args_schema=SearchInput)
def search(query: str, max_results: int = 5) -> list[str]:
    """Search for information."""
    ...
```

## create_react_agent

```python
from langgraph.prebuilt import create_react_agent
from langchain_openai import ChatOpenAI
from langchain_core.messages import HumanMessage

llm = ChatOpenAI(model="gpt-4o-mini")
tools = [search_web, calculator]

agent = create_react_agent(llm, tools)

result = agent.invoke({
    "messages": [HumanMessage("What is 2^10 plus the population of France?")]
})
# result["messages"][-1].content is the final answer
```

For async:

```python
result = await agent.ainvoke({"messages": [HumanMessage("...")]})
```

## System prompt

```python
from langchain_core.messages import SystemMessage

agent = create_react_agent(
    llm,
    tools,
    prompt=SystemMessage("You are a concise research assistant. Use tools when needed."),
)
```

Or use a `ChatPromptTemplate` with a `MessagesPlaceholder("messages")` for
dynamic system prompts that include user context.

## Middleware

LangChain v1 supports middleware via the `langgraph` runtime. Middleware
intercepts messages before and after each LLM call in the agent loop.

```python
from langgraph.prebuilt import create_react_agent
from langchain_core.messages import BaseMessage

def log_middleware(messages: list[BaseMessage], **kwargs):
    print(f"[Agent loop] {len(messages)} messages in context")
    return messages

# Middleware is passed via state_modifier or as a pre-processing step
```

For complex middleware needs, build the agent graph manually using LangGraph
nodes and edges rather than the prebuilt.

## Human-in-the-loop (interrupt)

LangGraph supports pausing the agent loop before a tool call and resuming
after human approval:

```python
from langgraph.prebuilt import create_react_agent
from langgraph.checkpoint.memory import MemorySaver

checkpointer = MemorySaver()
agent = create_react_agent(
    llm,
    tools,
    interrupt_before=["tools"],   # pause before executing any tool
    checkpointer=checkpointer,
)

config = {"configurable": {"thread_id": "session-1"}}

# First run — will pause
result = agent.invoke({"messages": [HumanMessage("Book a flight.")]}, config=config)
# result["__interrupt__"] contains the pending tool call for review

# After human reviews and approves
result = agent.invoke(None, config=config)  # resume from checkpoint
```

Requires a persistent checkpointer (e.g. `langgraph-checkpoint-postgres`
for production; `MemorySaver` for dev/test).

## Streaming agent output

```python
async for event in agent.astream_events(
    {"messages": [HumanMessage("...")]},
    version="v2",
):
    if event["event"] == "on_chat_model_stream":
        print(event["data"]["chunk"].content, end="", flush=True)
    elif event["event"] == "on_tool_start":
        print(f"\n[Tool: {event['name']}({event['data']['input']})]")
```

## Common traps

- **`ToolMessage.tool_call_id` mismatch** — if the ID in `ToolMessage` does
  not match the ID from `AIMessage.tool_calls`, the model will error or ignore
  the result. Always echo `tc["id"]` from the tool call.
- **Recursive tool calls** — a tool that calls the LLM, which calls the tool
  again, can loop forever. Set `recursion_limit` in the graph config:
  `{"recursion_limit": 25}`.
- **Tool errors not surfaced** — by default, exceptions in tools are caught
  and returned as error strings. If you need the agent to stop on error,
  raise `ToolException` from `langchain_core.tools`.
- **Very long tool outputs** — large tool responses bloat the context window
  quickly. Truncate or summarize tool output before returning it.
- **`create_react_agent` is a LangGraph graph** — it accepts the same
  `config` dict (including `thread_id` for memory) as any other graph. Do
  not treat it as a simple callable.
