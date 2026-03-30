<!-- Source: https://langfuse.com/integrations/model-providers/openai-py -->
<!-- Fetched: 2026-03-30 -->
<!-- Langfuse Python SDK v4.0.4 -->

# Observability for OpenAI SDK (Python)

## Overview

Langfuse provides a drop-in replacement for the OpenAI Python SDK that enables full observability by changing only the import statement. This integration works with both OpenAI and Azure OpenAI.

```python
# Replace this:
import openai

# With this:
from langfuse.openai import openai
```

Alternative imports available:

```python
from langfuse.openai import OpenAI, AsyncOpenAI, AzureOpenAI, AsyncAzureOpenAI
```

## Automatic Tracking

Langfuse automatically tracks:

- All prompts and completions with streaming, async, and function support
- Latencies
- API errors
- Model usage (tokens) and cost in USD

## Installation and Setup

### Prerequisites

The integration requires OpenAI SDK version `>=0.27.8`. For async and streaming support, use version `>=1.0.0`.

```bash
pip install langfuse openai
```

### Configuration Options

**Option 1: Environment Variables**

```bash
LANGFUSE_SECRET_KEY = "sk-lf-..."
LANGFUSE_PUBLIC_KEY = "pk-lf-..."
LANGFUSE_BASE_URL = "https://cloud.langfuse.com"  # EU
# LANGFUSE_BASE_URL = "https://us.cloud.langfuse.com"  # US
```

**Option 2: Code Attributes**

```python
from langfuse.openai import openai

openai.langfuse_public_key = "pk-lf-..."
openai.langfuse_secret_key = "sk-lf-..."
openai.langfuse_enabled = True
openai.LANGFUSE_BASE_URL = "https://cloud.langfuse.com"
openai.api_key = "sk-..."
```

### Connection Verification

```python
from langfuse import get_client

get_client().auth_check()
```

## Basic Usage

After setup, use the OpenAI SDK normally -- no additional changes required:

```python
from langfuse.openai import openai

result = openai.chat.completions.create(
    model="gpt-3.5-turbo",
    messages=[
        {"role": "system", "content": "You are a helpful assistant."},
        {"role": "user", "content": "Hello!"}
    ]
)
```

## Advanced Features

### Custom Trace Properties

Add properties to OpenAI method calls:

| Property | Description |
|----------|-------------|
| `name` | Identifies a specific generation type |
| `metadata` | Additional information visible in Langfuse |
| `trace_id` | For interoperability with Langfuse SDK |
| `parent_observation_id` | For trace hierarchy control |

### Setting Trace Attributes

**Method 1: Via Metadata**

```python
from langfuse.openai import openai

result = openai.chat.completions.create(
    model="gpt-3.5-turbo",
    messages=[
        {"role": "system", "content": "You are a calculator."},
        {"role": "user", "content": "1 + 1 = "}
    ],
    name="test-chat",
    metadata={
        "langfuse_session_id": "session_123",
        "langfuse_user_id": "user_456",
        "langfuse_tags": ["calculator"],
        "customKey": "customValue"
    }
)
```

**Method 2: Via Context Manager**

```python
from langfuse import get_client, propagate_attributes
from langfuse.openai import openai

langfuse = get_client()

with langfuse.start_as_current_observation(as_type="span", name="calculator") as span:
    with propagate_attributes(
        session_id="session_123",
        user_id="user_456",
        tags=["calculator"]
    ):
        result = openai.chat.completions.create(
            model="gpt-3.5-turbo",
            messages=[...],
            name="test-chat"
        )
```

### Using Traces

Group multiple OpenAI calls into a single trace using the decorator pattern:

```python
from langfuse import observe
from langfuse.openai import openai

@observe()
def capital_poem_generator(country):
    capital = openai.chat.completions.create(
        model="gpt-3.5-turbo",
        messages=[
            {"role": "system", "content": "What is the capital?"},
            {"role": "user", "content": country}
        ],
        name="get-capital"
    ).choices[0].message.content

    poem = openai.chat.completions.create(
        model="gpt-3.5-turbo",
        messages=[
            {"role": "system", "content": "Write a poem about this city."},
            {"role": "user", "content": capital}
        ],
        name="generate-poem"
    ).choices[0].message.content

    return poem
```

### Streaming with Token Usage

For streamed responses with token tracking:

```python
from langfuse import get_client
from langfuse.openai import openai

client = openai.OpenAI()

stream = client.chat.completions.create(
    model="gpt-4o",
    messages=[{"role": "user", "content": "How are you?"}],
    stream=True,
    stream_options={"include_usage": True}
)

result = ""
for chunk in stream:
    if chunk.choices:
        result += chunk.choices[0].delta.content or ""

get_client().flush()
```

### Structured Output

For structured output parsing, use the `response_format` argument:

```python
from langfuse import get_client
from langfuse.openai import openai
from openai.lib._parsing._completions import type_to_response_format_param
from pydantic import BaseModel

class CalendarEvent(BaseModel):
    name: str
    date: str
    participants: list[str]

completion = openai.chat.completions.create(
    model="gpt-4o-2024-08-06",
    messages=[
        {"role": "system", "content": "Extract event information."},
        {"role": "user", "content": "Alice and Bob attend a fair Friday."}
    ],
    response_format=type_to_response_format_param(CalendarEvent)
)

get_client().flush()
```

## Troubleshooting

### Event Flushing

Short-lived applications must flush events before exit:

```python
from langfuse import get_client

langfuse = get_client()
langfuse.flush()
```

### Debug Mode

Enable detailed logging:

```python
from langfuse import Langfuse

langfuse = Langfuse(debug=True)
```

Or via environment variable:

```bash
export LANGFUSE_DEBUG=true
```

### Sampling

Control trace volume:

```python
from langfuse import Langfuse

langfuse = Langfuse(sample_rate=0.1)  # Collect 10% of traces
```

Or via environment variable:

```bash
export LANGFUSE_SAMPLE_RATE=0.1
```

### Disable Tracing

Temporarily disable Langfuse:

```python
from langfuse import Langfuse

langfuse = Langfuse(tracing_enabled=False)
```

Or via environment variable:

```bash
export LANGFUSE_TRACING_ENABLED=false
```

## Error Tracking

Langfuse automatically captures OpenAI API errors through the `level` and `statusMessage` fields.

## Limitations

- **Assistants API**: Tracing is not supported due to OpenAI Assistants' server-side state architecture
- **Beta APIs**: Only stable OpenAI APIs are fully supported. For beta features, use the `@observe()` decorator for manual tracing
