# Agents and Prebuilt Patterns

Source: `docs/overview.md`, `docs/workflows-agents.md`, `docs/quickstart.md`,
`docs/thinking-in-langgraph.md`

## create_react_agent

LangGraph ships a prebuilt `create_react_agent` factory for the standard
LLM-tool loop (reason → act → observe). It is the fastest path to a working
agent when the architecture is a straightforward tool-calling loop.

```python
from langgraph.prebuilt import create_react_agent
from langchain.chat_models import init_chat_model
from langchain.tools import tool

@tool
def add(a: int, b: int) -> int:
    """Add two numbers."""
    return a + b

model = init_chat_model("claude-sonnet-4-6", temperature=0)
agent = create_react_agent(model, tools=[add])

result = agent.invoke({"messages": [{"role": "user", "content": "What is 2+3?"}]})
```

`create_react_agent` returns a compiled `StateGraph` using `MessagesState`.
Add a `checkpointer` for persistence and `interrupt_before=["tools"]` for
tool approval. Source: LangGraph overview and prebuilt module.

## When to build a custom graph instead

Use `create_react_agent` for the common LLM-plus-tools loop. Build a custom
`StateGraph` when you need:
- Multi-step workflows with non-LLM nodes.
- Branching based on classification results.
- Parallel fan-out and merge.
- Fine-grained retry policies per node.
- Human review at points other than before every tool call.

Source: `docs/overview.md`.

## Common workflow patterns (Graph API)

Source: `docs/workflows-agents.md`

### Prompt chaining

Sequential nodes, each processing the output of the previous:

```python
builder = StateGraph(State)
builder.add_node("step_1", step_1)
builder.add_node("step_2", step_2)
builder.add_edge(START, "step_1")
builder.add_edge("step_1", "step_2")
builder.add_edge("step_2", END)
```

### Routing / branching

One node classifies and routes to different specialised nodes:

```python
def router(state: State) -> Command[Literal["path_a", "path_b"]]:
    if state["intent"] == "a":
        return Command(goto="path_a")
    return Command(goto="path_b")
```

### Parallelization (fan-out / fan-in)

Multiple outgoing edges from one node run branches in the same super-step:

```python
builder.add_edge("classify", "search_docs")
builder.add_edge("classify", "fetch_history")
builder.add_edge("search_docs", "draft")
builder.add_edge("fetch_history", "draft")
```

Both `search_docs` and `fetch_history` run in parallel; `draft` runs after both
complete. Source: `docs/workflows-agents.md`.

### Map-reduce (Send API)

Fan out over a dynamic list with separate state copies:

```python
from langgraph.types import Send

def generate_subjects(state: State):
    return [Send("write_section", {"subject": s}) for s in state["subjects"]]

builder.add_conditional_edges("plan", generate_subjects)
```

Source: `docs/graph-api.md`.

### Orchestrator-subagent

One node decides what tasks to spawn; subgraph or `Send` carries out each task.
The orchestrator coordinates; subagents specialise. Source: `docs/workflows-agents.md`.

## Tool binding (LangChain integration)

LangGraph does not require LangChain, but integrates naturally:

```python
from langchain.tools import tool
from langchain.chat_models import init_chat_model

model = init_chat_model("claude-sonnet-4-6")

@tool
def search(query: str) -> str:
    """Search the web."""
    ...

model_with_tools = model.bind_tools([search])
```

The LLM node calls `model_with_tools.invoke(state["messages"])`. A separate
tool node executes the tool calls in the returned message. Conditional edge
routes back to the LLM node until no more tool calls. Source: `docs/quickstart.md`.

## Error handling strategies in agents

Source: `docs/thinking-in-langgraph.md`

| Error type | Strategy |
|------------|----------|
| Transient (network, rate limit) | `RetryPolicy` on the node |
| LLM-recoverable (tool failure, parse error) | Store error in state; `Command(goto="llm")` |
| User-fixable (missing info) | `interrupt()` to collect from user |
| Unexpected | Let propagate for debugging |
