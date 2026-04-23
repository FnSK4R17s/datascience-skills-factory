# Structured Output

Source: `docs/structured-output.md`, `docs/agents.md`

Structured output from agents is controlled via the `response_format` parameter
on `create_agent`. The result is in `result["structured_response"]`.

For structured output directly from a model (without an agent), use
`model.with_structured_output(schema)` — see the models docs.

## Choosing a strategy

```
response_format=MySchema    →  auto: ProviderStrategy if supported, else ToolStrategy
response_format=ProviderStrategy(MySchema)  →  native JSON from provider
response_format=ToolStrategy(MySchema)      →  tool calling for output
```

When passing a schema type directly, LangChain reads model profile data
(`langchain>=1.1`) to select the best strategy automatically.

## Supported schema types (both strategies)

- Pydantic `BaseModel` — returns validated instance
- Python `dataclass` — returns dict
- `TypedDict` — returns dict
- JSON Schema dict — returns dict
- `Union` of the above (ToolStrategy only) — model picks the matching schema

## ProviderStrategy

```python
from langchain.agents.structured_output import ProviderStrategy
from pydantic import BaseModel, Field

class Report(BaseModel):
    summary: str = Field(description="One-sentence summary")
    confidence: float = Field(description="0.0 to 1.0")

agent = create_agent(
    model="openai:gpt-4o",
    response_format=ProviderStrategy(Report),
    # strict=True  # optional, OpenAI and xAI only (langchain>=1.2)
)

result = agent.invoke({"messages": [{"role": "user", "content": "Analyse this..."}]})
report: Report = result["structured_response"]
```

Providers with native structured output support: OpenAI, Anthropic (Claude),
Google Gemini, xAI (Grok). Falls back to ToolStrategy if not available.

If you use `response_format=Report` directly (without wrapping in ProviderStrategy),
behaviour is identical when the model supports native structured output.

## ToolStrategy

Works with any model that supports tool calling. The schema is passed as a
synthetic tool; the model must call it exactly once to produce output.

```python
from langchain.agents.structured_output import ToolStrategy
from typing import Literal, Union
from pydantic import BaseModel, Field

class ProductReview(BaseModel):
    rating: int | None = Field(ge=1, le=5)
    sentiment: Literal["positive", "negative"]
    key_points: list[str]

agent = create_agent(
    model="openai:gpt-4o",
    tools=[search_tool],
    response_format=ToolStrategy(
        schema=ProductReview,
        handle_errors=True,         # default: retry on validation failure
        tool_message_content=None,  # optional custom confirmation message
    )
)
```

### handle_errors options

| Value | Behaviour |
|-------|-----------|
| `True` (default) | Catch all errors, use default retry message |
| `False` | All errors propagate, no retry |
| `str` | Catch all errors, use this fixed retry message |
| `type[Exception]` | Only catch this type, default message |
| `tuple[type[Exception], ...]` | Only catch these types |
| `Callable[[Exception], str]` | Custom handler returns retry message |

Error types to catch: `StructuredOutputValidationError` (schema mismatch),
`MultipleStructuredOutputsError` (model called the tool more than once).

```python
from langchain.agents.structured_output import (
    StructuredOutputValidationError,
    MultipleStructuredOutputsError,
)

def my_error_handler(error: Exception) -> str:
    if isinstance(error, StructuredOutputValidationError):
        return "Format error, please retry."
    elif isinstance(error, MultipleStructuredOutputsError):
        return "Return exactly one structured response."
    return f"Error: {error}"
```

### Union schemas

When the output can be one of several types, pass a `Union`:

```python
agent = create_agent(
    model,
    response_format=ToolStrategy(Union[ProductReview, CustomerComplaint])
)
```

The model chooses the appropriate schema based on context.

## Custom tool_message_content

Controls what appears in the conversation history after the structured tool call:

```python
ToolStrategy(
    schema=Report,
    tool_message_content="Report captured successfully.",
)
```

Without this, the default message is `"Returning structured response: {...}"`.

## State schema restriction

Custom state schemas (`state_schema`) must be `TypedDict` subclasses of
`AgentState`. Pydantic models and dataclasses are NOT valid for state schemas
in v1+. This restriction does not apply to `response_format` schemas or tool
`args_schema` — those still accept Pydantic, dataclass, and TypedDict.
