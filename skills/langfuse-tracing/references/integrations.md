# Framework Integration Patterns

## LangChain CallbackHandler

### v4 singleton pattern

Initialize the Langfuse client once, then create lightweight handlers:

```python
from langfuse import Langfuse, get_client
from langfuse.langchain import CallbackHandler
from langchain_openai import ChatOpenAI
from langchain_core.prompts import ChatPromptTemplate

# Initialize singleton (once at app startup)
Langfuse(public_key="pk-lf-...", secret_key="sk-lf-...")

# Create handler (lightweight, reusable)
langfuse_handler = CallbackHandler()

llm = ChatOpenAI(model_name="gpt-4o")
prompt = ChatPromptTemplate.from_template("Tell me a joke about {topic}")
chain = prompt | llm

response = chain.invoke(
    {"topic": "cats"},
    config={"callbacks": [langfuse_handler]}
)

get_client().flush()
```

### Session/user tracking

**Option 1: Via config metadata (simple)**

```python
response = chain.invoke(
    {"topic": "cats"},
    config={
        "callbacks": [langfuse_handler],
        "metadata": {
            "langfuse_user_id": "user-123",
            "langfuse_session_id": "session-456",
            "langfuse_tags": ["production", "v2"]
        }
    }
)
```

**Option 2: Via propagate_attributes (full control)**

```python
from langfuse import get_client, propagate_attributes
from langfuse.langchain import CallbackHandler

langfuse = get_client()

with langfuse.start_as_current_observation(as_type="span", name="my-workflow") as root:
    with propagate_attributes(
        session_id="session-456",
        user_id="user-123",
        tags=["production"]
    ):
        handler = CallbackHandler()
        response = chain.invoke(
            {"topic": "cats"},
            config={"callbacks": [handler]}
        )
    root.set_trace_io(
        input={"topic": "cats"},
        output={"response": response.content}
    )
```

### Custom trace naming and deterministic IDs

```python
from langfuse import Langfuse, get_client, propagate_attributes
from langfuse.langchain import CallbackHandler

langfuse = get_client()
external_id = "req_12345"
trace_id = Langfuse.create_trace_id(seed=external_id)

handler = CallbackHandler()

with langfuse.start_as_current_observation(
    as_type="span",
    name="langchain-request",
    trace_context={"trace_id": trace_id}
) as span:
    with propagate_attributes(user_id="user_123"):
        response = chain.invoke(
            {"person": "Ada Lovelace"},
            config={"callbacks": [handler]}
        )
    span.set_trace_io(input={"person": "Ada Lovelace"}, output={"response": response})
```

---

## LangGraph Agent Tracing

Same `CallbackHandler` pattern -- pass to the compiled graph's `.invoke()` or `.stream()`.

```python
from langgraph.graph import StateGraph
from langfuse.langchain import CallbackHandler

# Build your graph
graph = build_agent_graph()
compiled = graph.compile()

handler = CallbackHandler()
result = compiled.invoke(
    {"messages": [{"role": "user", "content": "What is 42 + 58?"}]},
    config={"callbacks": [handler]}
)
```

Langfuse automatically captures node execution, LLM generation, tool call, and conditional-edge routing spans.

### LangGraph Server pattern

For persistent deployments, bind at compile time: `graph_builder.compile().with_config({"callbacks": [CallbackHandler()]})`

### Multi-agent grouping

```python
from langfuse import Langfuse, get_client

langfuse = get_client()
trace_id = Langfuse.create_trace_id()

with langfuse.start_as_current_observation(
    as_type="span", name="multi-agent-workflow",
    trace_context={"trace_id": trace_id}
):
    # Each sub-agent runs under the same trace
    result_a = agent_a.invoke(input_a, config={"callbacks": [CallbackHandler()]})
    result_b = agent_b.invoke(input_b, config={"callbacks": [CallbackHandler()]})
```

### Agent graph visualization

Langfuse infers visual agent graphs from observation timing and nesting (beta). The graph view renders automatically when a trace contains agentic observation types -- no configuration needed.

---

## OpenAI Drop-in Wrapper

### Single import change

```python
# Replace this:
# import openai

# With this:
from langfuse.openai import openai

# Alternative imports:
# from langfuse.openai import OpenAI, AsyncOpenAI, AzureOpenAI, AsyncAzureOpenAI
```

### What's captured automatically

- All prompts and completions (sync, async, streaming)
- Latencies and TTFT on first chunk
- API errors (level + statusMessage)
- Token usage and USD cost
- Function/tool calls and structured outputs

### Basic usage (no other changes needed)

```python
from langfuse.openai import openai

result = openai.chat.completions.create(
    model="gpt-4o",
    messages=[
        {"role": "system", "content": "You are a helpful assistant."},
        {"role": "user", "content": "Hello!"}
    ]
)
```

### Custom trace properties on OpenAI calls

```python
from langfuse.openai import openai

result = openai.chat.completions.create(
    model="gpt-4o",
    messages=[{"role": "user", "content": "1 + 1 = "}],
    name="calculator",
    metadata={
        "langfuse_session_id": "session_123",
        "langfuse_user_id": "user_456",
        "langfuse_tags": ["calculator"],
        "custom_key": "custom_value"
    }
)
```

### Grouping multiple OpenAI calls via @observe

```python
from langfuse import observe
from langfuse.openai import openai

@observe()
def capital_poem_generator(country):
    capital = openai.chat.completions.create(
        model="gpt-4o",
        messages=[
            {"role": "system", "content": "What is the capital?"},
            {"role": "user", "content": country}
        ],
        name="get-capital"
    ).choices[0].message.content

    poem = openai.chat.completions.create(
        model="gpt-4o",
        messages=[
            {"role": "system", "content": "Write a poem about this city."},
            {"role": "user", "content": capital}
        ],
        name="generate-poem"
    ).choices[0].message.content

    return poem

# Both generations nest under the decorated function automatically
capital_poem_generator("France")
```

### Streaming caveats

**Empty choices chunk**: When using `stream_options={"include_usage": True}`, OpenAI sends a final chunk with empty `choices`. Always guard:

```python
from langfuse.openai import openai
from langfuse import get_client

client = openai.OpenAI()
stream = client.chat.completions.create(
    model="gpt-4o",
    messages=[{"role": "user", "content": "How are you?"}],
    stream=True,
    stream_options={"include_usage": True}
)

result = ""
for chunk in stream:
    if chunk.choices:  # REQUIRED: final usage chunk has empty choices
        result += chunk.choices[0].delta.content or ""

get_client().flush()
```

**Premature break**: The wrapper finalizes the observation only when the stream iterator completes. Breaking out of the loop early produces an incomplete observation with missing token counts. Always consume the full stream.

### Assistants API

NOT supported -- OpenAI Assistants use server-side state that the wrapper cannot intercept. Use `@observe()` to manually wrap Assistants API calls.

---

## Mixing Providers

The `@observe()` decorator is the universal glue. A `CallbackHandler()` created inside a decorated function inherits the decorator's trace context:

```python
from langfuse import observe, get_client, propagate_attributes
from langfuse.openai import openai
from langfuse.langchain import CallbackHandler

@observe()
def mixed_pipeline(query: str):
    with propagate_attributes(user_id="user_123", session_id="sess_abc"):
        # OpenAI call -- auto-nests under @observe
        enriched = openai.chat.completions.create(
            model="gpt-4o",
            messages=[{"role": "user", "content": f"Enrich: {query}"}],
            name="enrich"
        ).choices[0].message.content

        # LangChain call -- inherits trace context via handler
        handler = CallbackHandler()
        result = chain.invoke(
            {"input": enriched},
            config={"callbacks": [handler]}
        )

    return result
```
