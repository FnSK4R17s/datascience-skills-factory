# Testing Reference

Source: `docs/test.md`

## Key principles

1. Create the graph fresh in each test (use a factory function).
2. Compile with a new `MemorySaver` per test to avoid state leakage.
3. Use unique `thread_id` per test to prevent cross-test interference.
4. For node isolation, access via `graph.nodes["node_name"]`.

## Basic graph testing

```python
import pytest
from typing_extensions import TypedDict
from langgraph.graph import StateGraph, START, END
from langgraph.checkpoint.memory import MemorySaver

def create_graph():
    class MyState(TypedDict):
        my_key: str

    graph = StateGraph(MyState)
    graph.add_node("node1", lambda state: {"my_key": "hello from node1"})
    graph.add_node("node2", lambda state: {"my_key": "hello from node2"})
    graph.add_edge(START, "node1")
    graph.add_edge("node1", "node2")
    graph.add_edge("node2", END)
    return graph

def test_basic_agent_execution() -> None:
    checkpointer = MemorySaver()    # fresh per test
    graph = create_graph()
    compiled_graph = graph.compile(checkpointer=checkpointer)
    result = compiled_graph.invoke(
        {"my_key": "initial_value"},
        config={"configurable": {"thread_id": "test-1"}}
    )
    assert result["my_key"] == "hello from node2"
```

## Testing individual nodes

Access compiled nodes via `graph.nodes` to test them in isolation.
This bypasses checkpointer and state merging.

```python
def test_individual_node_execution() -> None:
    checkpointer = MemorySaver()
    graph = create_graph()
    compiled_graph = graph.compile(checkpointer=checkpointer)

    # Only invoke node1
    result = compiled_graph.nodes["node1"].invoke({"my_key": "initial_value"})
    assert result == {"my_key": "hello from node1"}

    # Only invoke node2
    result = compiled_graph.nodes["node2"].invoke({"my_key": "from_node1"})
    assert result == {"my_key": "hello from node2"}
```

## Testing with state setup (`update_state`)

Use `update_state` to inject state before invoking, or to start from a specific
point without running earlier nodes.

```python
def test_from_specific_state():
    graph = create_graph().compile(checkpointer=MemorySaver())
    config = {"configurable": {"thread_id": "test-2"}}

    # Pre-load state as if node1 already ran — no need to actually run node1
    graph.update_state(
        config,
        values={"my_key": "simulated_node1_output"},
        as_node="node1"    # marks update as coming from node1's perspective
    )

    # Invoke from where node1 left off (only node2 runs)
    result = graph.invoke(None, config)
    assert result["my_key"] == "hello from node2"
```

## Partial execution

Test a subset of nodes without running the entire graph. Uses persistence to
simulate a starting state and `interrupt_after` to stop at the right point.
Source: `docs/test.md`.

```python
def test_partial_execution() -> None:
    """Test only node2 and node3 of a longer pipeline."""

    def create_three_node_graph():
        class State(TypedDict):
            my_key: str

        g = StateGraph(State)
        g.add_node("node1", lambda s: {"my_key": "from_node1"})
        g.add_node("node2", lambda s: {"my_key": s["my_key"] + "_node2"})
        g.add_node("node3", lambda s: {"my_key": s["my_key"] + "_node3"})
        g.add_edge(START, "node1")
        g.add_edge("node1", "node2")
        g.add_edge("node2", "node3")
        g.add_edge("node3", END)
        return g

    graph = create_three_node_graph().compile(checkpointer=MemorySaver())
    config = {"configurable": {"thread_id": "partial-test"}}

    # Step 1: Simulate node1 completion by injecting its output
    graph.update_state(config, {"my_key": "simulated_node1_output"}, as_node="node1")

    # Step 2: Run node2 and node3 only, stopping after node3
    result = graph.invoke(None, config, interrupt_after=["node3"])

    # Only node2 and node3 ran
    assert result["my_key"] == "simulated_node1_output_node2_node3"
```

## Testing interrupt workflows

Source: `docs/test.md`

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
    assert result["__interrupt__"][0].value == "Approve?"

    # Resume with True
    result = graph.invoke(Command(resume=True), config)
    assert result["approved"] is True

def test_interrupt_reject():
    # Same setup
    ...
    # Resume with False
    result = graph.invoke(Command(resume=False), config)
    assert result["approved"] is False
```

## Testing conditional routing

```python
from typing import Literal

def test_routing():
    class State(TypedDict):
        flag: bool
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

    assert graph.invoke({"flag": True, "path": ""})["path"] == "left"
    assert graph.invoke({"flag": False, "path": ""})["path"] == "right"
```

## Testing streaming

```python
def test_streaming():
    class State(TypedDict):
        value: str

    def node_a(state):
        return {"value": "a"}

    def node_b(state):
        return {"value": "b"}

    builder = StateGraph(State)
    builder.add_node("node_a", node_a)
    builder.add_node("node_b", node_b)
    builder.add_edge(START, "node_a")
    builder.add_edge("node_a", "node_b")
    builder.add_edge("node_b", END)

    graph = builder.compile()

    chunks = list(graph.stream({"value": ""}, stream_mode="updates", version="v2"))
    update_chunks = [c for c in chunks if c["type"] == "updates"]

    assert len(update_chunks) == 2
    assert update_chunks[0]["data"] == {"node_a": {"value": "a"}}
    assert update_chunks[1]["data"] == {"node_b": {"value": "b"}}
```

## Mocking LLM calls

Use dependency injection (context schema or constructor args) to swap in a mock model.

```python
from dataclasses import dataclass
from langgraph.runtime import Runtime
from langchain.messages import AIMessage

@dataclass
class Context:
    model: object

def call_model(state, runtime: Runtime[Context]):
    response = runtime.context.model.invoke(state["messages"])
    return {"messages": [response]}

class MockModel:
    def invoke(self, messages):
        return AIMessage(content="mock response for testing")

    def bind_tools(self, tools):
        return self

def test_with_mock_model():
    from langgraph.graph import MessagesState

    builder = StateGraph(MessagesState, context_schema=Context)
    builder.add_node("call_model", call_model)
    builder.add_edge(START, "call_model")
    builder.add_edge("call_model", END)

    graph = builder.compile(checkpointer=MemorySaver())
    config = {"configurable": {"thread_id": "mock-test"}}
    result = graph.invoke(
        {"messages": [{"role": "user", "content": "hello"}]},
        config,
        context=Context(model=MockModel())
    )
    assert result["messages"][-1].content == "mock response for testing"
```

## Testing with SQLite (integration-level)

For end-to-end tests that verify serialization actually works:

```python
import sqlite3
import tempfile
import os
from langgraph.checkpoint.sqlite import SqliteSaver

def test_with_sqlite_checkpointer():
    with tempfile.NamedTemporaryFile(suffix=".db", delete=False) as f:
        db_path = f.name

    try:
        conn = sqlite3.connect(db_path)
        checkpointer = SqliteSaver(conn)

        graph = create_graph().compile(checkpointer=checkpointer)
        config = {"configurable": {"thread_id": "sqlite-test"}}

        result = graph.invoke({"my_key": "start"}, config)
        assert result["my_key"] == "hello from node2"

        # Verify state was persisted
        state = graph.get_state(config)
        assert state.values["my_key"] == "hello from node2"

        conn.close()
    finally:
        os.unlink(db_path)
```

## Inspecting graph structure

```python
def test_graph_structure():
    graph = create_graph().compile()

    # Inspect nodes
    node_names = set(graph.nodes.keys())
    assert "node1" in node_names
    assert "node2" in node_names

    # Inspect graph layout
    graph_repr = graph.get_graph()
    assert "node1" in [n.id for n in graph_repr.nodes.values()]
```

## Tips

- Always use a fresh `MemorySaver()` per test — shared instances leak state.
- Use `stream_mode="updates"` instead of `invoke` when testing intermediate steps.
- Test the graph structure itself with `graph.get_graph().nodes` and `.edges`.
- For end-to-end tests, use a temporary SQLite checkpointer instead of in-memory
  to verify serialization actually works.
- Mock slow LLM calls via context schema injection to keep tests fast.
- Use `update_state` + `as_node` to set up specific scenarios without running earlier nodes.
