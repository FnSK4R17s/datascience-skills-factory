# Graph API Reference

Source: `docs/graph-api.md`, `docs/use-graph-api.md`, `docs/thinking-in-langgraph.md`

## StateGraph

`StateGraph` is the main class. Parameterize it with a state schema, compile it,
then invoke or stream it. You **must** compile before use.

```python
from langgraph.graph import StateGraph, START, END
from typing_extensions import TypedDict

class State(TypedDict):
    topic: str
    joke: str

builder = StateGraph(State)
builder.add_node("generate", generate_fn)
builder.add_edge(START, "generate")
builder.add_edge("generate", END)
graph = builder.compile()             # validates structure

result = graph.invoke({"topic": "cats"})
print(result["joke"])
```

### Optional: separate I/O schemas

```python
class InputState(TypedDict):
    user_input: str

class OutputState(TypedDict):
    result: str

class OverallState(TypedDict):
    user_input: str
    result: str
    _scratch: str          # internal only — not exposed in output

builder = StateGraph(OverallState, input_schema=InputState, output_schema=OutputState)
```

Nodes can write to any channel in the union of all declared schemas, even private ones.

### Full multi-schema example

Source: `docs/graph-api.md`

```python
from typing_extensions import TypedDict
from langgraph.graph import StateGraph, START, END

class InputState(TypedDict):
    user_input: str

class OutputState(TypedDict):
    graph_output: str

class OverallState(TypedDict):
    foo: str
    user_input: str
    graph_output: str

class PrivateState(TypedDict):
    bar: str

def node_1(state: InputState) -> OverallState:
    return {"foo": state["user_input"] + " name"}

def node_2(state: OverallState) -> PrivateState:
    return {"bar": state["foo"] + " is"}

def node_3(state: PrivateState) -> OutputState:
    return {"graph_output": state["bar"] + " Lance"}

builder = StateGraph(OverallState, input_schema=InputState, output_schema=OutputState)
builder.add_node("node_1", node_1)
builder.add_node("node_2", node_2)
builder.add_node("node_3", node_3)
builder.add_edge(START, "node_1")
builder.add_edge("node_1", "node_2")
builder.add_edge("node_2", "node_3")
builder.add_edge("node_3", END)

graph = builder.compile()
graph.invoke({"user_input": "My"})
# {'graph_output': 'My name is Lance'}
```

`compile()` accepts: `checkpointer`, `store`, `interrupt_before=["node_a"]`,
`interrupt_after=["node_b"]`, `cache`. All optional.

## State schemas

Three supported forms:
- `TypedDict` — fastest, no validation overhead (recommended default)
- `dataclass` — supports field default values
- Pydantic `BaseModel` — recursive validation, slower; incompatible with `create_agent`

## Reducers

Reducers control how node output merges into state. Default is overwrite.

```python
from typing import Annotated
from operator import add
from typing_extensions import TypedDict

class State(TypedDict):
    foo: int                          # overwrite on each node update
    bar: Annotated[list[str], add]    # append; never overwrites
    tags: Annotated[set, lambda a, b: a | b]   # custom reducer
```

Example of default vs annotated reducer behavior (from `docs/graph-api.md`):

```python
# Starting state: {"foo": 1, "bar": ["hi"]}
# node returns: {"foo": 2}
# After: {"foo": 2, "bar": ["hi"]}   (bar unchanged since node didn't write it)

# node_b returns: {"bar": ["bye"]}
# With operator.add reducer: {"foo": 2, "bar": ["hi", "bye"]}
# Without reducer (default): {"foo": 2, "bar": ["bye"]}   (overwrites!)
```

Use `langgraph.types.Overwrite` to force an overwrite on a key that has a reducer:

```python
from langgraph.types import Overwrite

class State(TypedDict):
    data: Annotated[list, add]
    data_reset: Annotated[list, Overwrite]    # always overwrites even though annotated
```

### `add_messages` and `MessagesState`

```python
from langgraph.graph import MessagesState
from langgraph.graph.message import add_messages

class State(MessagesState):           # single 'messages' key + add_messages reducer
    documents: list[str]

# Or manually:
from langchain.messages import AnyMessage
from typing import Annotated

class State(TypedDict):
    messages: Annotated[list[AnyMessage], add_messages]
```

`add_messages` deduplicates by message ID (enabling human edits without duplicates),
deserializes plain dicts to LangChain message objects, and appends genuinely new
messages. Pass `RemoveMessage(id=m.id)` or `REMOVE_ALL_MESSAGES` to delete messages.

Both of these input forms work with `add_messages`:
```python
{"messages": [HumanMessage(content="hi")]}
{"messages": [{"type": "human", "content": "hi"}]}
```

Use **dot notation** to access message content: `state["messages"][-1].content`
(not bracket notation — messages are LangChain objects after deserialization).

## Nodes

Nodes are plain Python functions (sync or async). LangGraph injects parameters based
on declared names and types.

```python
from langgraph.runtime import Runtime
from langchain_core.runnables import RunnableConfig
from dataclasses import dataclass

@dataclass
class Context:
    user_id: str

def plain_node(state: State):
    return {"foo": "updated"}

def node_with_config(state: State, config: RunnableConfig):
    thread_id = config["configurable"]["thread_id"]
    return {"foo": thread_id}

def node_with_runtime(state: State, runtime: Runtime[Context]):
    uid = runtime.context.user_id
    store = runtime.store
    step = runtime.execution_info.thread_id
    return {"result": uid}
```

LangGraph injects `state`, `config` (RunnableConfig), and `runtime` (Runtime) based
on declared parameter names and types. Runtime carries: `context`, `store`,
`stream_writer`, `execution_info`, `server_info`.

Node name defaults to the function name when added without an explicit label:
```python
builder.add_node(my_node)         # name = "my_node"
builder.add_node("custom", my_node)  # name = "custom"
```

### Node caching

Cache node outputs based on inputs. Useful for expensive deterministic operations.

```python
from langgraph.cache.memory import InMemoryCache
from langgraph.types import CachePolicy
import time

class State(TypedDict):
    x: int
    result: int

def expensive_node(state: State) -> dict:
    time.sleep(2)                  # simulate expensive work
    return {"result": state["x"] * 2}

builder = StateGraph(State)
builder.add_node("expensive_node", expensive_node, cache_policy=CachePolicy(ttl=3))
builder.set_entry_point("expensive_node")
builder.set_finish_point("expensive_node")

graph = builder.compile(cache=InMemoryCache())

# First call: takes 2 seconds
print(graph.invoke({"x": 5}, stream_mode="updates"))
# [{'expensive_node': {'result': 10}}]

# Second call with same input: instant, from cache
print(graph.invoke({"x": 5}, stream_mode="updates"))
# [{'expensive_node': {'result': 10}, '__metadata__': {'cached': True}}]
```

## Edges

```python
# Always go A → B
builder.add_edge("a", "b")

# Conditional routing
from typing import Literal

def route(state) -> Literal["b", "c"]:
    return "b" if state["ok"] else "c"

builder.add_conditional_edges("a", route)
builder.add_conditional_edges("a", route, {True: "b", False: "c"})   # map output

# Conditional entry point
builder.add_conditional_edges(START, routing_function)
```

A node with multiple outgoing edges runs all destination nodes in parallel (same
super-step). Entry points use `START` as the source.

### Common edge patterns

```python
# Sequential pipeline
builder.add_edge(START, "step_a")
builder.add_edge("step_a", "step_b")
builder.add_edge("step_b", END)

# Parallel fan-out (both run in same super-step)
builder.add_edge(START, "node_a")
builder.add_edge(START, "node_b")

# Loop with exit condition
def should_retry(state) -> Literal["retry", "__end__"]:
    return "retry" if state["needs_retry"] else END

builder.add_conditional_edges("act", should_retry)
builder.add_edge("retry", "act")
```

## `Send` — map-reduce

`Send` dispatches independent state copies to a node in parallel. The number of
copies can vary at runtime — classic map-reduce pattern.

```python
from langgraph.types import Send

def fan_out(state):
    # Generate one Send per item — all run in parallel
    return [Send("process", {"item": x}) for x in state["items"]]

builder.add_conditional_edges("collect", fan_out)
builder.add_edge("process", "aggregate")
```

Full map-reduce example from `docs/graph-api.md`:

```python
from typing_extensions import TypedDict
from typing import Annotated
from langgraph.types import Send
from operator import add

class OverallState(TypedDict):
    subjects: list[str]
    jokes: Annotated[list[str], add]    # reducer to collect from all workers

class JokeState(TypedDict):
    subject: str

def generate_joke(state: JokeState):
    return {"jokes": [f"Why did the {state['subject']} cross the road? To get to the other side!"]}

def continue_to_jokes(state: OverallState):
    return [Send("generate_joke", {"subject": s}) for s in state["subjects"]]

builder = StateGraph(OverallState)
builder.add_node("generate_joke", generate_joke)
builder.add_conditional_edges(START, continue_to_jokes)
builder.add_edge("generate_joke", END)

graph = builder.compile()
result = graph.invoke({"subjects": ["cats", "dogs", "rabbits"], "jokes": []})
print(result["jokes"])   # three jokes collected via reducer
```

## `Command`

`Command` combines state update + routing in one return value from a node.

```python
from langgraph.types import Command
from typing import Literal

def my_node(state) -> Command[Literal["next"]]:
    return Command(update={"foo": "bar"}, goto="next")

# Dynamic routing — same as conditional edge but also updates state
def router_node(state) -> Command[Literal["path_a", "path_b"]]:
    if state["flag"]:
        return Command(update={"chosen": "a"}, goto="path_a")
    return Command(update={"chosen": "b"}, goto="path_b")

# Navigate from subgraph to parent graph
def subgraph_node(state) -> Command:
    return Command(update={...}, goto="parent_node", graph=Command.PARENT)
```

**Warning:** `Command` only *adds* a dynamic edge — static `add_edge` edges still
execute. To suppress a static edge, remove it and use only `Command`.

**As invoke input:** `Command(resume=...)` is the only valid form. Never pass
`Command(update=...)` as invoke input to continue a multi-turn conversation; pass
a plain dict instead (which re-runs from `__start__`, not the last checkpoint).

```python
# WRONG — graph resumes from latest checkpoint, appears stuck
graph.invoke(Command(update={"messages": [{"role": "user", "content": "follow up"}]}), config)

# CORRECT — plain dict restarts from __start__
graph.invoke({"messages": [{"role": "user", "content": "follow up"}]}, config)
```

### `Command` in tools

Return `Command` from tools to update state and control flow from inside a tool:

```python
from langchain.tools import tool

@tool
def lookup_customer(customer_id: str) -> Command:
    """Look up customer and update graph state with their info."""
    customer = db.get_customer(customer_id)
    return Command(
        update={"customer_name": customer.name, "customer_tier": customer.tier},
        # goto a different node after tool completes (in addition to static edges)
        goto="premium_handler" if customer.tier == "premium" else "standard_handler",
    )
```

## Runtime context

Per-invocation dependency injection. Not persisted. Accessed via `runtime.context`
inside nodes.

```python
from dataclasses import dataclass

@dataclass
class Ctx:
    db_pool: object
    model_name: str

builder = StateGraph(State, context_schema=Ctx)
graph = builder.compile()

graph.invoke(inputs, context={"db_pool": pool, "model_name": "claude-sonnet-4-6"})
```

## Recursion limit

```python
# CORRECT — top-level key, NOT inside configurable
graph.invoke(inputs, config={"recursion_limit": 200})
```

Default 1000 (since v1.0.6). Raises `GraphRecursionError` when exceeded.

### Proactive recursion handling with `RemainingSteps`

`RemainingSteps` is a managed value that automatically tracks steps remaining.
Source: `docs/graph-api.md`.

```python
from typing import Annotated, Literal
from langgraph.managed import RemainingSteps
from langgraph.errors import GraphRecursionError

class State(TypedDict):
    messages: Annotated[list, lambda x, y: x + y]
    remaining_steps: RemainingSteps    # auto-populated by LangGraph

def reasoning_node(state: State) -> dict:
    remaining = state["remaining_steps"]
    if remaining <= 2:
        return {"messages": ["Approaching limit, wrapping up..."]}
    return {"messages": ["thinking..."]}

def route_decision(state: State) -> Literal["reasoning_node", "fallback_node"]:
    if state["remaining_steps"] <= 2:
        return "fallback_node"
    return "reasoning_node"

def fallback_node(state: State) -> dict:
    return {"messages": ["Reached complexity limit, providing best effort answer"]}

builder = StateGraph(State)
builder.add_node("reasoning_node", reasoning_node)
builder.add_node("fallback_node", fallback_node)
builder.add_edge(START, "reasoning_node")
builder.add_conditional_edges("reasoning_node", route_decision)
builder.add_edge("fallback_node", END)
graph = builder.compile()

result = graph.invoke({"messages": []}, {"recursion_limit": 10})
```

Proactive approach (internal routing) vs reactive (external try/catch):

| Approach | Detection | Handling | Control Flow |
|---|---|---|---|
| Proactive (`RemainingSteps`) | Before limit | Inside graph | Graph completes normally |
| Reactive (`GraphRecursionError`) | After limit | try/catch | Graph execution terminates |

### Accessing step metadata in nodes

```python
from langchain_core.runnables import RunnableConfig

def inspect_metadata(state: dict, config: RunnableConfig) -> dict:
    metadata = config["metadata"]
    print(f"Step: {metadata['langgraph_step']}")
    print(f"Node: {metadata['langgraph_node']}")
    print(f"Triggers: {metadata['langgraph_triggers']}")
    print(f"Path: {metadata['langgraph_path']}")
    print(f"Checkpoint NS: {metadata['langgraph_checkpoint_ns']}")
    return state
```

## Visualization

```python
# In Jupyter / IPython
from IPython.display import Image, display
display(Image(graph.get_graph(xray=True).draw_mermaid_png()))

# Save to file
with open("graph.png", "wb") as f:
    f.write(graph.get_graph().draw_mermaid_png())
```

`xray=True` expands subgraphs in the visualization.

## Graph migrations

- Add/remove state keys: fully compatible with existing threads.
- Rename keys: existing thread values are lost for renamed key.
- Rename/remove nodes: only safe for threads NOT interrupted at that node.
- Topology changes: safe for completed threads; restricted for interrupted threads.
