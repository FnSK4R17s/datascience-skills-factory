# Structured Output

Source: `docs/structured-output.md`, `docs/agents.md`

Structured output from agents is controlled via the `response_format` parameter on
`create_agent`. The result is in `result["structured_response"]`.

For structured output directly from a model (without an agent), use
`model.with_structured_output(schema)` — see the models reference.

## Choosing a strategy

```
response_format=MySchema          →  auto: ProviderStrategy if supported, else ToolStrategy
response_format=ProviderStrategy(MySchema)  →  native JSON from provider
response_format=ToolStrategy(MySchema)      →  tool calling for output
```

When passing a schema type directly, LangChain reads model profile data
(`langchain>=1.1`) to select the best strategy automatically.

Auto-selection uses `ProviderStrategy` for: OpenAI, Anthropic (Claude), Google Gemini,
xAI (Grok). Falls back to `ToolStrategy` for all others.

## Supported schema types

| Schema type | ProviderStrategy | ToolStrategy | Returns |
|-------------|:---:|:---:|---------|
| Pydantic `BaseModel` | Yes | Yes | Validated instance |
| Python `dataclass` | Yes | Yes | dict |
| `TypedDict` | Yes | Yes | dict |
| JSON Schema dict | Yes | Yes | dict |
| `Union` of the above | No | **Yes** | Whichever schema the model picks |

## ProviderStrategy

Uses the model provider's native structured output API. More reliable when available.

```python
from langchain.agents.structured_output import ProviderStrategy
from pydantic import BaseModel, Field

class ContactInfo(BaseModel):
    """Contact information for a person."""
    name: str = Field(description="The name of the person")
    email: str = Field(description="The email address")
    phone: str = Field(description="The phone number")

agent = create_agent(
    model="openai:gpt-5.4",
    tools=[search_tool],
    response_format=ProviderStrategy(ContactInfo),
    # strict=True,  # OpenAI and xAI only (langchain>=1.2) — enforces strict schema
)

result = agent.invoke({
    "messages": [{"role": "user", "content": "Extract: John Doe, john@example.com, (555) 123-4567"}]
})
contact = result["structured_response"]  # ContactInfo instance
print(contact.name)   # "John Doe"
print(contact.email)  # "john@example.com"
```

### All schema types with ProviderStrategy

```python
# Pydantic Model (returns validated instance)
from pydantic import BaseModel, Field

class ContactInfo(BaseModel):
    name: str = Field(description="The name of the person")
    email: str = Field(description="The email address")
    phone: str = Field(description="The phone number")

agent = create_agent(model="openai:gpt-5.4", response_format=ContactInfo)  # auto-selects ProviderStrategy
result = agent.invoke({"messages": [{"role": "user", "content": "Extract contact..."}]})
# result["structured_response"] → ContactInfo(name=..., email=..., phone=...)

# Dataclass (returns dict)
from dataclasses import dataclass

@dataclass
class ContactInfo:
    name: str
    email: str
    phone: str

agent = create_agent(model="openai:gpt-5.4", response_format=ContactInfo)
# result["structured_response"] → {'name': ..., 'email': ..., 'phone': ...}

# TypedDict (returns dict)
from typing_extensions import TypedDict

class ContactInfo(TypedDict):
    name: str
    email: str
    phone: str

agent = create_agent(model="openai:gpt-5.4", response_format=ContactInfo)
# result["structured_response"] → {'name': ..., 'email': ..., 'phone': ...}

# JSON Schema dict (returns dict)
contact_schema = {
    "type": "object",
    "description": "Contact information",
    "properties": {
        "name": {"type": "string"},
        "email": {"type": "string"},
        "phone": {"type": "string"},
    },
    "required": ["name", "email", "phone"],
}

agent = create_agent(
    model="openai:gpt-5.4",
    response_format=ProviderStrategy(contact_schema),
)
```

## ToolStrategy

Works with any model that supports tool calling. The schema is passed as a synthetic tool;
the model must call it exactly once to produce output.

```python
from langchain.agents.structured_output import ToolStrategy
from typing import Literal

class ProductReview(BaseModel):
    """Analysis of a product review."""
    rating: int | None = Field(description="Rating (1-5)", ge=1, le=5)
    sentiment: Literal["positive", "negative"] = Field(description="Sentiment")
    key_points: list[str] = Field(description="Key points, lowercase, 1-3 words each")

agent = create_agent(
    model="openai:gpt-5.4-mini",
    tools=[search_tool],
    response_format=ToolStrategy(
        schema=ProductReview,
        handle_errors=True,         # default: retry on validation failure
        tool_message_content=None,  # optional custom confirmation message
    )
)

result = agent.invoke({
    "messages": [{"role": "user", "content": "Analyze: 'Great product, 5 stars, fast shipping'"}]
})
review = result["structured_response"]  # ProductReview instance
# ProductReview(rating=5, sentiment='positive', key_points=['fast shipping'])
```

### Union schemas (ToolStrategy only)

When the output can be one of several types:

```python
from typing import Union

class ProductReview(BaseModel):
    """Analysis of a product review."""
    rating: int | None = Field(ge=1, le=5)
    sentiment: Literal["positive", "negative"]
    key_points: list[str]

class CustomerComplaint(BaseModel):
    """A customer complaint."""
    issue_type: Literal["product", "service", "shipping", "billing"]
    severity: Literal["low", "medium", "high"]
    description: str

agent = create_agent(
    model="openai:gpt-5.4",
    tools=[search_tool],
    response_format=ToolStrategy(Union[ProductReview, CustomerComplaint])
)

# Model selects the most appropriate schema based on context
result = agent.invoke({
    "messages": [{"role": "user", "content": "Analyze: 'Order never arrived, 2 weeks late'"}]
})
# result["structured_response"] → CustomerComplaint(issue_type='shipping', severity='high', ...)
```

### Custom tool_message_content

Controls what appears in the conversation history after the structured tool call:

```python
from langchain.agents.structured_output import ToolStrategy

class MeetingAction(BaseModel):
    """Action item extracted from a meeting."""
    task: str = Field(description="The specific task")
    assignee: str = Field(description="Person responsible")
    priority: Literal["low", "medium", "high"]

agent = create_agent(
    model="openai:gpt-5.4",
    response_format=ToolStrategy(
        schema=MeetingAction,
        tool_message_content="Action item captured and added to meeting notes!",
    )
)

# Conversation trace:
# Human: "Sarah needs to update the timeline ASAP"
# AI Tool Call: MeetingAction(task="Update project timeline", assignee="Sarah", priority="high")
# Tool Message: "Action item captured and added to meeting notes!"  ← customized

# Without tool_message_content, the default is:
# Tool Message: "Returning structured response: {'task': '...', ...}"
```

## handle_errors options and behavior

| Value | Behaviour |
|-------|-----------|
| `True` (default) | Catch all errors, use default retry message |
| `False` | All errors propagate, no retry |
| `str` | Catch all errors, use this fixed retry message |
| `type[Exception]` | Only catch this type, default message |
| `tuple[type[Exception], ...]` | Only catch these types |
| `Callable[[Exception], str]` | Custom handler returns retry message |

### Validation error retry (automatic)

When the model returns data that fails schema validation, the agent automatically retries:

```python
from pydantic import BaseModel, Field
from langchain.agents.structured_output import ToolStrategy

class ProductRating(BaseModel):
    rating: int | None = Field(description="Rating from 1-5", ge=1, le=5)
    comment: str = Field(description="Review comment")

agent = create_agent(
    model="openai:gpt-5.4",
    tools=[],
    response_format=ToolStrategy(ProductRating),  # handle_errors=True by default
    system_prompt="Parse product reviews. Do not make up values.",
)

result = agent.invoke({
    "messages": [{"role": "user", "content": "Parse: 'Amazing product, 10/10!'"}]
})
# Conversation trace:
# AI calls ProductRating(rating=10, comment="Amazing product")
# Tool: "Error: 1 validation error for ProductRating.rating: Input should be ≤ 5"
# AI retries: ProductRating(rating=5, comment="Amazing product")
# result["structured_response"] → ProductRating(rating=5, comment="Amazing product")
```

### Multiple structured outputs error (automatic)

When the model incorrectly calls the schema tool multiple times:

```python
agent = create_agent(
    model="openai:gpt-5.4",
    tools=[],
    response_format=ToolStrategy(Union[ContactInfo, EventDetails]),
)

result = agent.invoke({
    "messages": [{"role": "user", "content": "John Doe (john@email.com) is organizing Tech Conf on March 15"}]
})
# Model mistakenly calls both ContactInfo AND EventDetails
# LangChain adds error: "Model incorrectly returned multiple responses..."
# Model retries with a single schema
```

### Custom error handler

```python
from langchain.agents.structured_output import StructuredOutputValidationError, MultipleStructuredOutputsError

def my_error_handler(error: Exception) -> str:
    if isinstance(error, StructuredOutputValidationError):
        return "There was a format issue. Please retry with valid values."
    elif isinstance(error, MultipleStructuredOutputsError):
        return "Please return only ONE structured response, not multiple."
    return f"Unexpected error: {error}"

agent = create_agent(
    model="openai:gpt-5.4",
    response_format=ToolStrategy(
        schema=Union[ContactInfo, EventDetails],
        handle_errors=my_error_handler,
    ),
)
```

### Disable error handling (handle_errors=False)

```python
# All errors propagate — agent raises instead of retrying
agent = create_agent(
    model="openai:gpt-5.4",
    response_format=ToolStrategy(schema=ProductRating, handle_errors=False),
)
```

## Standalone model structured output

For extraction or classification without an agent loop:

```python
from langchain.chat_models import init_chat_model
from pydantic import BaseModel

class Sentiment(BaseModel):
    label: Literal["positive", "negative", "neutral"]
    score: float = Field(ge=0.0, le=1.0)

model = init_chat_model("openai:gpt-5.4")
structured = model.with_structured_output(Sentiment)
result = structured.invoke("This movie was absolutely wonderful!")
# Sentiment(label='positive', score=0.95)

# Or with tool calling explicitly
result = model.with_structured_output(Sentiment, method="function_calling").invoke("Great product!")
```

## State schema restriction reminder

Custom state schemas (`state_schema`) must be `TypedDict` subclasses of `AgentState`.
Pydantic models and dataclasses are **NOT** valid for state schemas in v1+.

This restriction does NOT apply to `response_format` schemas or tool `args_schema` —
those still accept Pydantic, dataclass, and TypedDict.

## Complete example: document analysis agent

```python
from typing import Literal
from pydantic import BaseModel, Field
from langchain.agents import create_agent
from langchain.agents.structured_output import ToolStrategy, ProviderStrategy
from langchain.tools import tool

class DocumentSummary(BaseModel):
    """Structured summary of a document."""
    title: str = Field(description="Document title or inferred title")
    language: str = Field(description="Primary language (ISO 639-1)")
    document_type: Literal["report", "contract", "article", "email", "other"]
    key_points: list[str] = Field(description="3-5 key points, each ≤ 15 words")
    action_items: list[str] = Field(description="Action items found (empty list if none)")
    sentiment: Literal["positive", "negative", "neutral", "mixed"]
    word_count_estimate: int = Field(description="Estimated word count")

@tool
def retrieve_document(doc_id: str) -> str:
    """Fetch a document by its ID."""
    # In a real implementation, fetch from storage
    return "Annual sales report showing 15% growth in Q4..."

agent = create_agent(
    model="openai:gpt-5.4",
    tools=[retrieve_document],
    response_format=ProviderStrategy(DocumentSummary),  # explicit native JSON
    system_prompt=(
        "You are a document analysis assistant. "
        "Retrieve and analyze documents, then provide a structured summary."
    ),
)

result = agent.invoke({
    "messages": [{"role": "user", "content": "Analyze document ID: report-2025-q4"}]
})
summary: DocumentSummary = result["structured_response"]
print(f"Type: {summary.document_type}")
print(f"Key points: {summary.key_points}")
print(f"Action items: {summary.action_items}")
```
