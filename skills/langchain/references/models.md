# Models

Source: `docs/models.md`, `docs/quickstart.md`, `docs/overview.md`

LangChain provides a standard model interface via `init_chat_model` and per-provider
class instances (`ChatOpenAI`, `ChatAnthropic`, etc.). The same interface works both
inside `create_agent` and standalone (direct model invocation without an agent).

## init_chat_model

```python
from langchain.chat_models import init_chat_model

# Provider:model string format
model = init_chat_model("openai:gpt-5.4")
model = init_chat_model("anthropic:claude-sonnet-4-6")
model = init_chat_model("google_genai:gemini-2.5-flash-lite")
model = init_chat_model("google_genai:gemini-3.1-pro-preview")

# Auto-inferred (major providers)
model = init_chat_model("gpt-5.4")           # → openai:gpt-5.4
model = init_chat_model("claude-sonnet-4-6") # → anthropic:claude-sonnet-4-6

# With explicit parameters
model = init_chat_model(
    "openai:gpt-5.4",
    temperature=0.5,
    timeout=300,
    max_tokens=25000,
)

# With model profile (langchain>=1.1) to enable automatic feature detection
model = init_chat_model(
    "my-custom-model",
    profile={
        "max_input_tokens": 128000,
        "structured_output": True,
        "tool_calling": True,
    }
)
```

## Provider installation and setup

```bash
# OpenAI
pip install "langchain[openai]"
export OPENAI_API_KEY="sk-..."

# Anthropic
pip install "langchain[anthropic]"
export ANTHROPIC_API_KEY="sk-ant-..."

# Google Gemini
pip install "langchain[google-genai]"
export GOOGLE_API_KEY="..."

# AWS Bedrock (uses boto3 credentials)
pip install langchain-aws

# Ollama (local)
pip install langchain-ollama
# No API key needed — run: ollama serve

# OpenRouter (proxy for many models)
pip install langchain-openrouter
export OPENROUTER_API_KEY="sk-or-..."
```

## Provider class instances (full control)

```python
from langchain_openai import ChatOpenAI
from langchain_anthropic import ChatAnthropic
from langchain_google_genai import ChatGoogleGenerativeAI

# OpenAI
model = ChatOpenAI(
    model="gpt-5.4",
    temperature=0.1,
    max_tokens=4000,
    timeout=30,
    max_retries=3,
    # streaming=False,  # disable streaming if needed
)

# Anthropic
model = ChatAnthropic(
    model_name="claude-sonnet-4-6",
    timeout=None,
    max_tokens=8192,
)

# Anthropic with thinking (extended reasoning)
model = ChatAnthropic(
    model_name="claude-sonnet-4-6",
    thinking={"type": "enabled", "budget_tokens": 5000},
)

# Google Gemini
model = ChatGoogleGenerativeAI(model="gemini-2.5-flash-lite")

# Azure OpenAI
from langchain_openai import AzureChatOpenAI
model = AzureChatOpenAI(
    model="gpt-5.4",
    azure_deployment="my-deployment",
    azure_endpoint="https://my-resource.openai.azure.com/",
    api_version="2025-03-01-preview",
)

# AWS Bedrock via init_chat_model
model = init_chat_model(
    "anthropic.claude-3-5-sonnet-20240620-v1:0",
    model_provider="bedrock_converse",
)

# Ollama (local)
from langchain_ollama import ChatOllama
model = ChatOllama(model="llama3")

# OpenRouter
model = init_chat_model("auto", model_provider="openrouter")
```

## Standalone invocation

```python
from langchain.messages import HumanMessage, SystemMessage

model = init_chat_model("openai:gpt-5.4")

# String shortcut (single HumanMessage)
response = model.invoke("Write a haiku about spring")

# Message list (full control)
response = model.invoke([
    SystemMessage("You are a concise poet."),
    HumanMessage("Write a haiku about spring"),
])

# Dict format (OpenAI chat completions format)
response = model.invoke([
    {"role": "system", "content": "You are a poet."},
    {"role": "user", "content": "Write a haiku"},
])

# Access response
print(response.text)           # plain text (convenience property)
print(response.content_blocks) # typed content blocks
print(response.content)        # raw provider payload
```

## Streaming (standalone)

```python
# Stream text tokens
for chunk in model.stream("Tell me a story"):
    print(chunk.text, end="", flush=True)

# Accumulate chunks
full = None
for chunk in model.stream("Hello"):
    full = chunk if full is None else full + chunk
# full is a complete AIMessage

# Async streaming
async for chunk in model.astream("Hello"):
    print(chunk.text, end="")
```

## Tool calling (standalone models)

```python
def get_weather(city: str) -> str:
    """Get weather for a city."""
    return f"Sunny in {city}"

def calculate_tip(bill: float, pct: float = 18.0) -> float:
    """Calculate tip amount."""
    return bill * pct / 100

# Bind tools to model
model_with_tools = model.bind_tools([get_weather, calculate_tip])
response = model_with_tools.invoke("Weather in Paris, and 20% tip on $85?")

# Inspect tool calls
for tc in response.tool_calls:
    print(tc["name"], tc["args"])

# Execute tools manually
import json
tool_map = {"get_weather": get_weather, "calculate_tip": calculate_tip}
tool_messages = []
for tc in response.tool_calls:
    fn = tool_map[tc["name"]]
    result = fn(**tc["args"])
    from langchain.messages import ToolMessage
    tool_messages.append(ToolMessage(content=str(result), tool_call_id=tc["id"]))

# Continue the conversation
messages = [{"role": "user", "content": "Weather in Paris, 20% tip on $85?"}]
messages.append(response)
messages.extend(tool_messages)
final = model_with_tools.invoke(messages)
print(final.text)
```

Note: do NOT pre-call `bind_tools` on models passed to `create_agent(..., response_format=...)`.

## Structured output (standalone)

```python
from pydantic import BaseModel
from typing import Literal

class Sentiment(BaseModel):
    label: Literal["positive", "negative", "neutral"]
    score: float  # 0.0 to 1.0

# Automatic method selection (prefers native structured output)
structured = model.with_structured_output(Sentiment)
result = structured.invoke("This movie was absolutely wonderful!")
# Sentiment(label='positive', score=0.95)

# Force tool calling method
result = model.with_structured_output(Sentiment, method="function_calling").invoke("Bad product!")

# JSON mode
result = model.with_structured_output(Sentiment, method="json_mode").invoke("Mediocre experience")

# TypedDict also works
from typing_extensions import TypedDict
class SentimentDict(TypedDict):
    label: str
    score: float

result = model.with_structured_output(SentimentDict).invoke("Decent quality")
# {'label': 'positive', 'score': 0.7}
```

## Token usage

```python
response = model.invoke("Hello!")
print(response.usage_metadata)
# {
#   'input_tokens': 8,
#   'output_tokens': 12,
#   'total_tokens': 20,
#   'input_token_details': {'cache_read': 0, 'cache_creation': 0},
#   'output_token_details': {'reasoning': 0}
# }

# Accumulate usage across streamed chunks
total_usage = None
for chunk in model.stream("Hello"):
    if chunk.usage_metadata:
        if total_usage is None:
            total_usage = chunk.usage_metadata
        else:
            total_usage = {
                k: total_usage.get(k, 0) + chunk.usage_metadata.get(k, 0)
                for k in set(total_usage) | set(chunk.usage_metadata)
            }
```

## Reasoning / thinking models

```python
# Anthropic extended thinking
from langchain_anthropic import ChatAnthropic
from langchain.messages import AIMessageChunk

model = ChatAnthropic(
    model_name="claude-sonnet-4-6",
    thinking={"type": "enabled", "budget_tokens": 5000},
)

# Stream reasoning tokens
for chunk in model.stream("What is 27 * 41?"):
    for block in chunk.content_blocks:
        if block["type"] == "reasoning":
            print(f"[thinking] {block['reasoning']}", end="")
        elif block["type"] == "text":
            print(block["text"], end="")

# Access reasoning in completed response
response = model.invoke("What is 27 * 41?")
reasoning_blocks = [b for b in response.content_blocks if b["type"] == "reasoning"]
text_blocks = [b for b in response.content_blocks if b["type"] == "text"]
print("Reasoning:", reasoning_blocks[0]["reasoning"][:200])
print("Answer:", text_blocks[0]["text"])
```

## Model profiles (langchain >= 1.1)

Model profiles power automatic feature detection. LangChain uses them to:
- Select `ProviderStrategy` vs `ToolStrategy` for structured output
- Determine `SummarizationMiddleware` trigger thresholds via `fraction` mode

```python
# Built-in profiles are downloaded automatically for major models
# Override for custom/fine-tuned models:
model = init_chat_model(
    "my-finetuned-model",
    profile={
        "max_input_tokens": 128000,
        "max_output_tokens": 4096,
        "structured_output": True,
        "tool_calling": True,
        "vision": False,
        "audio": False,
    }
)
```

## output_version

To store standard content blocks in message `content` (for external serialization):

```python
# Per-model
model = init_chat_model("openai:gpt-5.4", output_version="v1")

# Global via environment variable
# export LC_OUTPUT_VERSION=v1
```

With `output_version="v1"`, `message.content` contains the normalized `content_blocks`
list instead of the provider-specific raw format.

## Server-side tools

Some providers support built-in server-side tools (web search, code interpreter). These
appear as `ServerToolCall` / `ServerToolResult` content blocks:

```python
from langchain_openai import ChatOpenAI

# OpenAI web search (if available for your model)
model = ChatOpenAI(model="gpt-5.4")
# Pass server tool config in the request metadata
response = model.invoke(
    "What are the latest AI news?",
    tools=[{"type": "web_search"}],  # provider-specific
)

# Access server tool results in content_blocks
for block in response.content_blocks:
    if block["type"] == "server_tool_call":
        print(f"Server tool: {block['name']}")
    elif block["type"] == "server_tool_result":
        print(f"Server result: {block}")
```

## Multimodal input

```python
from langchain.messages import HumanMessage

# Image from URL
response = model.invoke([
    HumanMessage(content=[
        {"type": "text", "text": "What's in this image?"},
        {"type": "image", "url": "https://example.com/photo.jpg"},
    ])
])

# Image from base64
import base64
with open("image.jpg", "rb") as f:
    b64 = base64.b64encode(f.read()).decode()

response = model.invoke([
    HumanMessage(content=[
        {"type": "text", "text": "Describe this image."},
        {"type": "image", "base64": b64, "mime_type": "image/jpeg"},
    ])
])

# PDF from URL
response = model.invoke([
    HumanMessage(content=[
        {"type": "text", "text": "Summarize this document."},
        {"type": "file", "url": "https://example.com/report.pdf"},
    ])
])

# Provider-specific extras (e.g., filename for AWS Bedrock PDFs)
response = model.invoke([
    HumanMessage(content=[
        {"type": "text", "text": "Summarize."},
        {"type": "file", "url": "...", "filename": "report.pdf"},
    ])
])
```

Not all providers support all modalities. Check the provider's integration page.
