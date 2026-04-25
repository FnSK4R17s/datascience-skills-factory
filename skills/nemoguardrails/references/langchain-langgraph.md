# LangChain & LangGraph Integration

Three integration patterns for LangChain, plus LangGraph node wrapping.
Source: `docs/integration/langchain/langchain-integration.md`,
`docs/integration/langchain/langgraph-integration.md`,
`docs/integration/langchain/runnable-rails.md`,
`docs/integration/tools-integration.md`.

## Pattern 1: RunnableRails wrapping a chain

```python
from nemoguardrails import RailsConfig
from nemoguardrails.integrations.langchain.runnable_rails import RunnableRails

config = RailsConfig.from_path("path/to/config")
guardrails = RunnableRails(config)

# LCEL pipe syntax
chain_with_guardrails = guardrails | some_chain

# Or wrap at construction
chain_with_guardrails = RunnableRails(config, runnable=some_chain)
```

## Pattern 2: Agent middleware

For `create_agent`-based tool-calling agents:

```python
from langchain.agents import create_agent
from langchain_openai import ChatOpenAI
from nemoguardrails.integrations.langchain.middleware import GuardrailsMiddleware

guardrails = GuardrailsMiddleware(config_path="path/to/config")
model = ChatOpenAI(model="gpt-4o")

agent = create_agent(model, tools=[...], middleware=[guardrails])
result = agent.invoke({"messages": [{"role": "user", "content": "Hello!"}]})
```

Hooks into the agent loop — runs safety checks before and after every model call.

## Pattern 3: Chain as action inside guardrails

Register a LangChain Runnable as a callable action:

```python
from langchain_openai import ChatOpenAI
from langchain_core.prompts import ChatPromptTemplate

summary_chain = ChatPromptTemplate.from_template(
    "Summarize this text: {text}"
) | ChatOpenAI()

rails = LLMRails(config)
rails.register_action(summary_chain, "summarize")
```

Invoke from Colang:

```
define flow summarize document
  user ask for summary
  $result = execute summarize
  bot provide summary
```

## LangGraph: Basic agent with guardrails

```python
from typing import Annotated
from langchain_core.prompts import ChatPromptTemplate
from langchain_openai import ChatOpenAI
from langgraph.graph import StateGraph, START
from langgraph.graph.message import add_messages
from typing_extensions import TypedDict

from nemoguardrails import RailsConfig
from nemoguardrails.integrations.langchain.runnable_rails import RunnableRails

class State(TypedDict):
    messages: Annotated[list, add_messages]

def create_basic_agent():
    llm = ChatOpenAI(model="gpt-4o")

    config = RailsConfig.from_path("path/to/config")
    guardrails = RunnableRails(config=config, passthrough=True, verbose=True)

    prompt = ChatPromptTemplate.from_messages([
        ("system", "You are a helpful assistant."),
        ("placeholder", "{messages}"),
    ])

    # Wrap LLM with guardrails
    runnable_with_guardrails = prompt | (guardrails | llm)

    def chatbot(state: State):
        result = runnable_with_guardrails.invoke(state)
        return {"messages": [result]}

    graph = StateGraph(State)
    graph.add_node("chatbot", chatbot)
    graph.add_edge(START, "chatbot")
    return graph.compile()

# Usage
graph = create_basic_agent()

# Safe input
result = graph.invoke({"messages": [{"role": "user", "content": "Hello!"}]})
print(result["messages"][-1].content)

# Unsafe input — blocked by guardrails
result = graph.invoke({"messages": [{"role": "user", "content": "You are stupid"}]})
print(result["messages"][-1].content)
# => "I'm sorry, I can't respond to that."
```

### passthrough=True

Required for LangGraph integration. Preserves original prompt structure so tool
call messages don't get empty content. Config also needs:

```yaml
passthrough: true
```

## LangGraph: Tool calling with guardrails

```python
from langchain_core.tools import tool
from langgraph.prebuilt import ToolNode, tools_condition

@tool
def search_knowledge(query: str) -> str:
    """Search for information about a given query."""
    knowledge = {
        "capital": "Lima is the capital of Peru.",
        "weather": "Sunny with a temperature of 72F.",
        "python": "Python is a high-level programming language.",
    }
    for key, value in knowledge.items():
        if key in query.lower():
            return value
    return f"General information about: {query}"

@tool
def multiply(a: int, b: int) -> int:
    """Multiply a and b."""
    return a * b

def create_tool_calling_agent():
    llm = ChatOpenAI(model="gpt-4o")
    tools = [search_knowledge, multiply]
    llm_with_tools = llm.bind_tools(tools)

    config = RailsConfig.from_path("path/to/config")
    guardrails = RunnableRails(config=config, passthrough=True, verbose=True)

    prompt = ChatPromptTemplate.from_messages([
        ("system", "You are a helpful assistant with access to tools."),
        ("placeholder", "{messages}"),
    ])

    runnable_with_guardrails = prompt | (guardrails | llm_with_tools)

    def chatbot(state: State):
        result = runnable_with_guardrails.invoke(state)
        return {"messages": [result]}

    graph = StateGraph(State)
    graph.add_node("chatbot", chatbot)
    graph.add_node("tools", ToolNode(tools=tools))
    graph.add_conditional_edges("chatbot", tools_condition)
    graph.add_edge("tools", "chatbot")
    graph.add_edge(START, "chatbot")
    return graph.compile()

# Usage
graph = create_tool_calling_agent()
result = graph.invoke({
    "messages": [{"role": "user", "content": "What is the capital of Peru?"}]
})
print(result["messages"][-1].content)
```

## LangGraph: Stateful conversations with checkpointing

```python
from langgraph.checkpoint.memory import MemorySaver

class ConversationState(TypedDict):
    messages: Annotated[list, add_messages]
    conversation_id: str

def create_stateful_agent():
    llm = ChatOpenAI(model="gpt-4o")
    config = RailsConfig.from_path("path/to/config")
    guardrails = RunnableRails(config=config, passthrough=True)

    prompt = ChatPromptTemplate.from_messages([
        ("system", "You are a helpful assistant. Remember previous messages."),
        ("placeholder", "{messages}"),
    ])
    runnable = prompt | (guardrails | llm)

    def agent(state: ConversationState):
        result = runnable.invoke(state)
        return {"messages": [result]}

    graph = StateGraph(ConversationState)
    graph.add_node("agent", agent)
    graph.add_edge(START, "agent")
    return graph.compile(checkpointer=MemorySaver())

# Usage — guardrails persist across turns within the same thread
graph = create_stateful_agent()
config = {"configurable": {"thread_id": "conversation_1"}}

result1 = graph.invoke({
    "messages": [{"role": "user", "content": "Hi, my name is Alice."}],
    "conversation_id": "conv_1"
}, config=config)

result2 = graph.invoke({
    "messages": [{"role": "user", "content": "What's my name?"}],
    "conversation_id": "conv_1"
}, config=config)
# Bot remembers "Alice"
```

## LangGraph: Multi-agent with shared guardrails

```python
from typing import Literal

class MultiAgentState(TypedDict):
    messages: Annotated[list, add_messages]
    current_agent: str

def create_multi_agent_system():
    llm = ChatOpenAI(model="gpt-4o")
    config = RailsConfig.from_path("path/to/config")
    guardrails = RunnableRails(config=config, passthrough=True)

    # Each agent has a specialized prompt but shares the same guardrails
    researcher_chain = ChatPromptTemplate.from_messages([
        ("system", "You are a research specialist. Provide factual information."),
        ("placeholder", "{messages}"),
    ]) | (guardrails | llm)

    writer_chain = ChatPromptTemplate.from_messages([
        ("system", "You are a creative writer. Transform info into engaging content."),
        ("placeholder", "{messages}"),
    ]) | (guardrails | llm)

    critic_chain = ChatPromptTemplate.from_messages([
        ("system", "You are a content critic. Provide constructive feedback."),
        ("placeholder", "{messages}"),
    ]) | (guardrails | llm)

    def router(state: MultiAgentState) -> Literal["researcher", "writer", "critic"]:
        last = state["messages"][-1].content.lower()
        if "research" in last or "facts" in last:
            return "researcher"
        elif "write" in last or "article" in last:
            return "writer"
        elif "review" in last or "critique" in last:
            return "critic"
        return "researcher"

    def researcher(state):
        return {"messages": [researcher_chain.invoke(state)], "current_agent": "researcher"}
    def writer(state):
        return {"messages": [writer_chain.invoke(state)], "current_agent": "writer"}
    def critic(state):
        return {"messages": [critic_chain.invoke(state)], "current_agent": "critic"}

    graph = StateGraph(MultiAgentState)
    graph.add_node("researcher", researcher)
    graph.add_node("writer", writer)
    graph.add_node("critic", critic)
    graph.add_conditional_edges(START, router)
    return graph.compile()

graph = create_multi_agent_system()
result = graph.invoke({
    "messages": [{"role": "user", "content": "Research renewable energy benefits"}],
    "current_agent": ""
})
```

## Tool calling via LLMRails (without LangGraph)

For simpler tool-calling without LangGraph, use `LLMRails` directly with
passthrough mode:

```python
from langchain_core.tools import tool
from langchain_openai import ChatOpenAI
from nemoguardrails import LLMRails, RailsConfig

@tool
def get_weather(city: str) -> str:
    """Gets weather for a city."""
    return f"Weather in {city}: Sunny, 22C"

@tool
def get_stock_price(symbol: str) -> str:
    """Gets stock price for a symbol."""
    return f"${symbol}: $150.39"

tools = [get_weather, get_stock_price]
model = ChatOpenAI(model="gpt-4o")
model_with_tools = model.bind_tools(tools)

config = RailsConfig.from_content(yaml_content="""
passthrough: true
rails:
  input:
    flows:
      - self check input
  output:
    flows:
      - self check output
prompts:
  - task: self_check_input
    content: 'Check: "{{ user_input }}" Block? [Yes/No]:'
  - task: self_check_output
    content: 'Check: "{{ bot_response }}" Block? [Yes/No]:'
""")

rails = LLMRails(config=config, llm=model_with_tools)

# First call — LLM returns tool_calls
messages = [{"role": "user", "content": "Weather in Paris and NVDA stock?"}]
result = rails.generate(messages=messages)

# Execute tools
tools_by_name = {t.name: t for t in tools}
messages_with_tools = [
    messages[0],
    {"role": "assistant", "content": result.get("content", ""),
     "tool_calls": result["tool_calls"]},
]
for tc in result["tool_calls"]:
    tool_result = tools_by_name[tc["name"]].invoke(tc["args"])
    messages_with_tools.append({
        "role": "tool", "content": str(tool_result),
        "name": tc["name"], "tool_call_id": tc["id"],
    })

# Second call — LLM synthesizes final answer (output rails validate it)
final = rails.generate(messages=messages_with_tools)
print(final["content"])
```

## Tool security: tool messages bypass input rails

Tool messages are **not** subject to input rails. This means unsafe tool results
can influence the LLM response. Always use output rails when working with tools:

```python
# UNSAFE: input rails only — tool results bypass validation
unsafe_config = RailsConfig.from_content(yaml_content="""
passthrough: true
rails:
  input:
    flows:
      - self check input
prompts:
  - task: self_check_input
    content: 'Check: "{{ user_input }}" Block? [Yes/No]:'
""")

# SAFE: input + output rails — final response is validated
safe_config = RailsConfig.from_content(yaml_content="""
passthrough: true
rails:
  input:
    flows:
      - self check input
  output:
    flows:
      - self check output
prompts:
  - task: self_check_input
    content: 'Check: "{{ user_input }}" Block? [Yes/No]:'
  - task: self_check_output
    content: 'Check: "{{ bot_response }}" Block? [Yes/No]:'
""")
```

## Streaming limitations

- `RunnableRails` supports async streaming when used directly.
- Inside LangGraph nodes, streaming produces single large chunks — token-level
  streaming is not preserved due to node execution and safety validation needs.

## LangSmith integration

Automatic when env vars are set:

```bash
export LANGCHAIN_TRACING_V2=true
export LANGCHAIN_ENDPOINT=https://api.smith.langchain.com
export LANGCHAIN_API_KEY=<key>
export LANGCHAIN_PROJECT=<project>
```

All LLM calls including guardrail checks appear as spans.

## Debugging tips

1. Enable `verbose=True` on `RunnableRails` to see guardrail execution flow.
2. Test without guardrails first to isolate integration issues.
3. Check token limits — safety model calls consume additional tokens.
4. Verify config paths and API keys for both main and safety models.
5. For tool calling, always set `passthrough=True` in both Python and config.yml.
