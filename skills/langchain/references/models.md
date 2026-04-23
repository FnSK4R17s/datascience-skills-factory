# Models

Source: `docs/models.md`, `docs/quickstart.md`, `docs/overview.md`

LangChain provides a standard model interface via `init_chat_model` and per-provider class instances
(`ChatOpenAI`, `ChatAnthropic`, etc.). The same interface works both inside `create_agent` and
standalone (direct model invocation without an agent).

## init_chat_model

```python
from langchain.chat_models import init_chat_model

# Model identifier string format: "provider:model-name"
model = init_chat_model("openai:gpt-5.4")
model = init_chat_model("anthropic:claude-sonnet-4-6")
model = init_chat_model("google_genai:gemini-2.5-flash-lite")

# With explicit parameters
model = init_chat_model(
    "openai:gpt-5.4",
    temperature=0.5,
    timeout=300,
    max_tokens=25000,
)

# Provider class instances (full parameter control)
from langchain_openai import ChatOpenAI
model = ChatOpenAI(model="gpt-5.4", temperature=0.1, max_tokens=1000)
```

Provider shorthand (provider can be inferred from model name for major providers):
- `"gpt-5.4"` infers `openai:gpt-5.4`
- `"claude-sonnet-4-6"` infers `anthropic:claude-sonnet-4-6`

See the reference for full mappings.

## Provider installation

```bash
pip install "langchain[openai]"      # OpenAI / Azure
pip install "langchain[anthropic]"   # Anthropic
pip install "langchain[google-genai]" # Google Gemini
pip install langchain-aws            # AWS Bedrock
pip install langchain-ollama         # Ollama (local)
pip install langchain-openrouter     # OpenRouter
```

For Bedrock / HuggingFace, pass `model_provider` explicitly:
```python
model = init_chat_model(
    "anthropic.claude-3-5-sonnet-20240620-v1:0",
    model_provider="bedrock_converse"
)
```

## Standalone invocation

```python
from langchain.messages import HumanMessage, SystemMessage

# String shortcut
response = model.invoke("Write a haiku about spring")

# Message list
response = model.invoke([
    SystemMessage("You are a poet."),
    HumanMessage("Write a haiku about spring"),
])

# Dict format (OpenAI chat completions format)
response = model.invoke([
    {"role": "system", "content": "You are a poet."},
    {"role": "user", "content": "Write a haiku about spring"},
])
```

`invoke` returns an `AIMessage`. Access response text via `response.text` or typed blocks via
`response.content_blocks`.

## Stream

```python
for chunk in model.stream("Tell me a story"):
    print(chunk.text, end="", flush=True)
```

Chunks are `AIMessageChunk` objects that can be added together:
```python
full = None
for chunk in model.stream("Hello"):
    full = chunk if full is None else full + chunk
```

## Tool calling (on standalone models)

```python
def get_weather(city: str) -> str:
    """Get weather for a city."""
    return f"Sunny in {city}"

model_with_tools = model.bind_tools([get_weather])
response = model_with_tools.invoke("Weather in Paris?")
for tc in response.tool_calls:
    print(tc["name"], tc["args"])
```

Note: do not pre-call `bind_tools` on models passed to `create_agent(..., response_format=...)`.

## Structured output (standalone)

```python
from pydantic import BaseModel

class Sentiment(BaseModel):
    label: str
    score: float

structured = model.with_structured_output(Sentiment)
result = structured.invoke("This movie was great!")
# result is a Sentiment instance
```

## Token usage

```python
response = model.invoke("Hello!")
print(response.usage_metadata)
# {'input_tokens': 8, 'output_tokens': 12, 'total_tokens': 20,
#  'input_token_details': {'cache_read': 0}, ...}
```

## Model profiles (langchain >= 1.1)

Model profiles provide metadata like context window, max tokens, and structured output support.
Pass custom profiles to override or supplement:

```python
model = init_chat_model("my-model", profile={"max_input_tokens": 128000, "structured_output": True})
```

Profiles power automatic trigger logic in `SummarizationMiddleware` and automatic
strategy selection in `ProviderStrategy`.

## output_version

To store standard content blocks in message `content` (e.g., for external serialization):

```python
model = init_chat_model("gpt-5.4", output_version="v1")
# Or set env: LC_OUTPUT_VERSION=v1
```

## Server-side tools

Some providers support built-in server-side tools (web search, code interpreter). These appear
as `ServerToolCall` / `ServerToolResult` content blocks in the response. See the provider
integration pages for details.
