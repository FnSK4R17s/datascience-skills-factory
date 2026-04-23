# Testing Reference

Source: `docs/test.md`

## Basic graph testing

Create the graph fresh in each test (use a factory function) and compile with a new
`MemorySaver` per test to avoid state leakage:

```python
import pytest
from typing_extensions import TypedDict
from langgraph.graph import StateGraph, START, END
from langgraph.checkpoint.memory import MemorySaver

def create_graph():
    class State(TypedDict):
        value: str

    builder = StateGraph(State)
    builder.add_node("node_a", lambda s: {"value": "from_a"})
    builder.add_node("node_b", lambda s: {"value": "from_b"})
    builder.add_edge(START, "node_a")
    builder.add_edge("node_a", "node_b")
    builder.add_edge("node_b", END)
    return builder

def test_full_execution():
    graph = create_graph().compile(checkpointer=MemorySaver())
    config = {"configurable": {"thread_id": "test-1"}}
    result = graph.invoke({"value": "initial"}, config)
    assert result["value"] == "from_b"
```

## Testing individual nodes

Access compiled nodes via `graph.nodes` to test them in isolation (bypasses
checkpointer and state merging):

```python
def test_node_a():
    graph = create_graph().compile()
    node_a = graph.nodes["node_a"]
    result = node_a.invoke({"value": "input"})
    assert result == {"value": "from_a"}
```

## Testing with state setup (`update_state`)

Use `update_state` to inject state before invoking, or to set up specific scenarios
without running earlier nodes:

```python
def test_from_specific_state():
    graph = create_graph().compile(checkpointer=MemorySaver())
    config = {"configurable": {"thread_id": "test-2"}}

    # Pre-load state as if node_a already ran
    graph.update_state(config, {"value": "simulated_a_output"}, as_node="node_a")

    # Invoke from where node_a left off
    result = graph.invoke(None, config)
    assert result["value"] == "from_b"
```

## Testing interrupt workflows

```python
from langgraph.types import interrupt, Command

def test_interrupt_and_resume():
    class State(TypedDict):
        approved: bool

    def approval(state):
        decision = interrupt("Approve?")
        return {"approved": decision}

    builder = StateGraph(State)
    builder.add_node("approval", approval)
    builder.add_edge(START, "approval")
    builder.add_edge("approval", END)

    graph = builder.compile(checkpointer=MemorySaver())
    config = {"configurable": {"thread_id": "hitl-test"}}

    # First run — hits interrupt
    result = graph.invoke({"approved": False}, config)
    assert "__interrupt__" in result

    # Resume
    result = graph.invoke(Command(resume=True), config)
    assert result["approved"] is True
```

## Testing conditional routing

```python
def test_routing():
    class State(TypedDict):
        path: str

    def router(state) -> Literal["left", "right"]:
        return "left" if state["flag"] else "right"

    builder = StateGraph(State)
    builder.add_node("left", lambda s: {"path": "left"})
    builder.add_node("right", lambda s: {"path": "right"})
    builder.add_conditional_edges(START, router)
    builder.add_edge("left", END)
    builder.add_edge("right", END)

    graph = builder.compile()

    assert graph.invoke({"flag": True})["path"] == "left"
    assert graph.invoke({"flag": False})["path"] == "right"
```

## Mocking LLM calls

Use dependency injection (context schema or constructor args) to swap in a mock model:

```python
@dataclass
class Context:
    model: object

def call_model(state, runtime: Runtime[Context]):
    response = runtime.context.model.invoke(state["messages"])
    return {"messages": [response]}

class MockModel:
    def invoke(self, messages):
        return AIMessage(content="mock response")

graph = builder.compile(checkpointer=MemorySaver())
result = graph.invoke(inputs, config, context=Context(model=MockModel()))
```

## Tips

- Always use a fresh `MemorySaver()` per test — shared instances leak state across tests.
- Use `stream_mode="updates"` instead of `invoke` when testing intermediate steps.
- Test the graph structure itself with `graph.get_graph().nodes` and `.edges`.
- For end-to-end tests, use a temporary SQLite checkpointer instead of in-memory
  to verify serialization actually works.
