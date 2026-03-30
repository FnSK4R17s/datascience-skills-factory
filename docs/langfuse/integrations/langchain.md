<!-- Source: https://langfuse.com/integrations/frameworks/langchain -->
<!-- Fetched: 2026-03-30 -->
<!-- Langfuse Python SDK v4.0.4 -->

# LangChain Tracing and LangGraph Integration

## Overview

Langfuse integrates with LangChain using **LangChain Callbacks**, the standard mechanism for hooking into LangChain component execution. The Langfuse `CallbackHandler` captures detailed traces of LangChain executions, LLMs, tools, and retrievers for evaluation and debugging.

- **LangChain**: Open-source framework for building applications powered by large language models
- **LangGraph**: Framework built on top of LangChain for designing stateful, multi-step AI agents
- **Langfuse**: Platform for observability and tracing of LLM applications

## Getting Started

### Python SDK Installation

```bash
pip install langfuse langchain langchain_openai langgraph
```

**Environment Configuration (.env):**

```bash
LANGFUSE_SECRET_KEY = "sk-lf-..."
LANGFUSE_PUBLIC_KEY = "pk-lf-..."
LANGFUSE_BASE_URL = "https://cloud.langfuse.com" # EU
# LANGFUSE_BASE_URL = "https://us.cloud.langfuse.com" # US
OPENAI_API_KEY = "sk-proj-..."
```

**Initialize Client:**

```python
from langfuse import get_client
from langfuse.langchain import CallbackHandler

langfuse = get_client()
langfuse_handler = CallbackHandler()
```

**LangChain Example:**

```python
from langchain.agents import create_agent

def add_numbers(a: int, b: int) -> int:
    """Add two numbers together and return the result."""
    return a + b

agent = create_agent(
    model="openai:gpt-5-mini",
    tools=[add_numbers],
    system_prompt="You are a helpful math tutor who can do calculations using the provided tools.",
)

agent.invoke(
    {"messages": [{"role": "user", "content": "what is 42 + 58?"}]},
    config={"callbacks": [langfuse_handler]}
)
```

### JS/TS SDK Installation

```bash
npm install @langfuse/core @langfuse/langchain
```

**Initialize with OpenTelemetry:**

```typescript
import { NodeSDK } from "@opentelemetry/sdk-node";
import { LangfuseSpanProcessor } from "@langfuse/otel";

const sdk = new NodeSDK({
  spanProcessors: [new LangfuseSpanProcessor()],
});

sdk.start();
```

**Initialize Handler:**

```typescript
import { CallbackHandler } from "@langfuse/langchain";

const langfuseHandler = new CallbackHandler({
  sessionId: "user-session-123",
  userId: "user-abc",
  tags: ["langchain-test"],
});
```

## Interoperability with Langfuse SDKs

### Using @observe() Decorator (Python)

```python
from langfuse import observe, get_client, propagate_attributes
from langfuse.langchain import CallbackHandler
from langchain_openai import ChatOpenAI
from langchain_core.prompts import ChatPromptTemplate

@observe()
def process_user_query(user_input: str):
    langfuse = get_client()

    with propagate_attributes(
        trace_name="user-query-processing",
        session_id="session-1234",
        user_id="user-5678",
    ):
      langfuse_handler = CallbackHandler()

      llm = ChatOpenAI(model_name="gpt-4o")
      prompt = ChatPromptTemplate.from_template("Respond to: {input}")
      chain = prompt | llm

      result = chain.invoke({"input": user_input}, config={"callbacks": [langfuse_handler]})

      langfuse.set_current_trace_io(
        input={"query": user_input},
        output={"response": result.content},
      )

    return result.content
```

### Using Context Managers (Python)

```python
from langfuse import get_client, propagate_attributes
from langfuse.langchain import CallbackHandler

langfuse = get_client()

with langfuse.start_as_current_observation(as_type="span", name="multi-step-process") as root_span:
    with propagate_attributes(
        session_id="session-1234",
        user_id="user-5678",
    ):
      langfuse_handler = CallbackHandler()

      with langfuse.start_as_current_observation(as_type="span", name="input-preprocessing") as prep_span:
          processed_input = "Simplified: Explain quantum computing"
          prep_span.update(output={"processed_query": processed_input})

      llm = ChatOpenAI(model_name="gpt-4o")
      prompt = ChatPromptTemplate.from_template("Answer this question: {input}")
      chain = prompt | llm

      result = chain.invoke(
          {"input": processed_input},
          config={"callbacks": [langfuse_handler]}
      )

      with langfuse.start_as_current_observation(as_type="span", name="output-postprocessing") as post_span:
          final_result = f"Response: {result.content}"
          post_span.update(output={"final_response": final_result})

      root_span.set_trace_io(
        input={"user_query": "Explain quantum computing"},
        output={"final_answer": final_result}
      )
```

## Setting Trace Attributes Dynamically

### Python - Metadata Fields (Recommended)

```python
from langfuse.langchain import CallbackHandler
from langchain_openai import ChatOpenAI
from langchain_core.prompts import ChatPromptTemplate

langfuse_handler = CallbackHandler()

llm = ChatOpenAI(model_name="gpt-4o")
prompt = ChatPromptTemplate.from_template("Tell me a joke about {topic}")
chain = prompt | llm

response = chain.invoke(
    {"topic": "cats"},
    config={
        "callbacks": [langfuse_handler],
        "metadata": {
            "langfuse_user_id": "random-user",
            "langfuse_session_id": "random-session",
            "langfuse_tags": ["random-tag-1", "random-tag-2"]
        }
    }
)
```

### JS/TS Approach

```typescript
import { CallbackHandler } from "@langfuse/langchain";

const langfuseHandler = new CallbackHandler();

const traceName = "langchain_trace_name";
const sessionId = "random-session";
const userId = "random-user";
const tags = ["random-tag-1", "random-tag-2"];

await chain.invoke(
  { animal: "dog" },
  {
    callbacks: [langfuseHandler],
    runName: traceName,
    tags,
    metadata: { langfuseUserId: userId, langfuseSessionId: sessionId },
  }
);
```

## Trace IDs and Distributed Tracing

### Python

```python
from langfuse import get_client, Langfuse
from langfuse.langchain import CallbackHandler

langfuse = get_client()

external_request_id = "req_12345"
predefined_trace_id = Langfuse.create_trace_id(seed=external_request_id)

langfuse_handler = CallbackHandler()

with langfuse.start_as_current_observation(
    as_type="span",
    name="langchain-request",
    trace_context={"trace_id": predefined_trace_id}
) as span:
    span.set_trace_io(input={"person": "Ada Lovelace"})

    with propagate_attributes(user_id="user_123"):
        response = chain.invoke(
            {"person": "Ada Lovelace"},
            config={"callbacks": [langfuse_handler]}
        )

    span.set_trace_io(output={"response": response})

print(f"Trace ID: {predefined_trace_id}")
print(f"Trace ID: {langfuse_handler.last_trace_id}")
```

## Scoring Traces

### Python Options

**Option 1: Using span object from context manager**

```python
from langfuse import get_client

langfuse = get_client()

with langfuse.start_as_current_observation(
    as_type="span",
    name="langchain-request",
    trace_context={"trace_id": predefined_trace_id}
) as span:
    span.score_trace(
        name="user-feedback",
        value=1,
        data_type="NUMERIC",
        comment="This was correct, thank you"
    )
```

**Option 2: Using score_current_trace()**

```python
with langfuse.start_as_current_observation(as_type="span", name="langchain-request") as span:
    langfuse.score_current_trace(
        name="user-feedback",
        value=1,
        data_type="NUMERIC"
    )
```

**Option 3: Using create_score() with trace ID**

```python
langfuse.create_score(
    trace_id=predefined_trace_id,
    name="user-feedback",
    value=1,
    data_type="NUMERIC",
    comment="This was correct, thank you"
)
```

## Queuing and Flushing

### Python

```python
from langfuse import get_client

# Shutdown (flush + cleanup)
get_client().shutdown()

# Flush only
get_client().flush()
```

### JS/TS

```typescript
// Shutdown
await langfuseHandler.shutdownAsync();

// Flush only
await langfuseHandler.flushAsync();
```

## Serverless Environments (JS/TS)

For serverless deployments (Google Cloud Functions, AWS Lambda, Cloudflare Workers), set callbacks to blocking mode:

- Set `LANGCHAIN_CALLBACKS_BACKGROUND` environment variable to `"false"`
- Or import and use the global `awaitAllCallbacks` method

## Upgrade Paths

### Python v2.x.x to v3.x.x

| Topic | v2 | v3 |
|-------|----|----|
| Package import | `from langfuse.callback import CallbackHandler` | `from langfuse.langchain import CallbackHandler` |
| Client handling | Multiple instantiated clients | Singleton pattern via `get_client()` |
| Trace/Span context | `CallbackHandler` accepted `root` to group runs | Use context managers `with langfuse.start_as_current_observation(...)` |
| Dynamic trace attrs | Pass via LangChain `config` metadata | Use `metadata["langfuse_user_id"]` OR `propagate_attributes(user_id=...)` |
| Constructor args | `CallbackHandler(sample_rate=..., user_id=...)` | No constructor args -- use Langfuse client or spans |

### Minimal Migration Example

```python
pip install --upgrade langfuse

from langfuse import Langfuse, get_client
from langfuse.langchain import CallbackHandler
from langchain_openai import ChatOpenAI
from langchain_core.prompts import ChatPromptTemplate

Langfuse(
    public_key="your-public-key",
    secret_key="your-secret-key",
)

langfuse = get_client()
handler = CallbackHandler()

llm = ChatOpenAI(model_name="gpt-4o")
prompt = ChatPromptTemplate.from_template("Tell me a joke about {topic}")
chain = prompt | llm

response = chain.invoke(
    {"topic": "cats"},
    config={
        "callbacks": [handler],
        "metadata": {"langfuse_user_id": "user_123"}
    }
)

langfuse.flush()
```

## Additional Configuration Notes

- **LangGraph**: Uses the same pattern as LangChain; pass `langfuse_handler` to agent invocation
- All arguments like `sample_rate` must be provided during Langfuse client construction, not on the handler
- Functions like `flush()` and `shutdown()` are called on client instance (`get_client().flush()`)
