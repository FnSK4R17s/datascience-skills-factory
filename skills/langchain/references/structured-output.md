# Structured Output

LangChain v1 unifies structured output behind a single method:
`llm.with_structured_output(schema)`. The method selects the best
available extraction mechanism for the underlying provider.

## The canonical pattern

```python
from pydantic import BaseModel, Field
from langchain_openai import ChatOpenAI

class CalendarEvent(BaseModel):
    name: str = Field(description="Name of the event")
    date: str = Field(description="ISO 8601 date string")
    participants: list[str] = Field(description="List of participant names")

llm = ChatOpenAI(model="gpt-4o-mini")
structured_llm = llm.with_structured_output(CalendarEvent)

event = structured_llm.invoke("Alice and Bob are meeting on 2026-05-01.")
# event is a CalendarEvent instance
print(event.name, event.date)
```

## Schema options

| Schema type | When to use |
|-------------|-------------|
| Pydantic `BaseModel` | Preferred — gives you a typed object with validation |
| `TypedDict` | Useful when you want a plain dict without Pydantic overhead |
| JSON Schema dict | When you need to pass a raw schema, e.g. from a config file |

Pydantic field `description=` fields are included in the prompt sent to the
model. Descriptive fields improve extraction accuracy significantly.

## Provider mechanisms (internal, but good to know when debugging)

| Provider | Default mechanism |
|----------|------------------|
| OpenAI (gpt-4o, gpt-4.1, etc.) | Native JSON schema via `response_format` |
| Anthropic (Claude models) | Tool-based extraction (forces a tool call) |
| Google (Gemini) | Native JSON schema |
| Others (Mistral, Groq, etc.) | Tool-based or prompt-based depending on capability |

You do not normally select the mechanism — `with_structured_output` does.
When debugging, set `include_raw=True` to inspect what the model actually
returned before parsing.

## `include_raw=True` for debugging

```python
structured_llm = llm.with_structured_output(CalendarEvent, include_raw=True)
result = structured_llm.invoke("...")
# result is {"raw": AIMessage(...), "parsed": CalendarEvent(...), "parsing_error": None}

if result["parsing_error"]:
    print("Parse failed:", result["parsing_error"])
    print("Raw output:", result["raw"].content)
```

## When `with_structured_output` fails

Common failure modes and fixes:

| Symptom | Likely cause | Fix |
|---------|-------------|-----|
| `ValidationError` on a required field | Model omitted a field | Add `Field(description=...)` to clarify; or make the field `Optional` with a default |
| Empty / null values | Ambiguous schema or underspecified prompt | Add more context to the `description=` or to the system prompt |
| `OutputParserException` | Model returned invalid JSON (prompt-based fallback) | Switch to a model that supports native tool / JSON modes |
| `NotImplementedError` | Provider does not support this schema type | Use `TypedDict` or raw JSON schema instead of Pydantic |
| Schema too large → truncated | Very deeply nested model | Flatten the schema; avoid circular references |

## Tool-based extraction (manual alternative)

For multi-step extractions or when you need the tool-call metadata:

```python
from langchain_core.tools import tool

@tool
def extract_event(name: str, date: str, participants: list[str]) -> str:
    """Extract a calendar event from text."""
    return f"{name} on {date}"

llm_with_tools = llm.bind_tools([extract_event])
msg = llm_with_tools.invoke("Alice and Bob meet on 2026-05-01.")
print(msg.tool_calls)  # [{"name": "extract_event", "args": {...}}]
```

Use this when you need to control when the tool is called, or when you
want to keep the raw `AIMessage` alongside the parsed result.

## Partial / streaming structured output

Some providers support streaming partial JSON; most do not. Do not rely on
structured output being streamable. Buffer the full response, then parse.
If you need streaming tokens AND structured output in the same pipeline,
stream the text and parse the complete string at the end.

## Common traps

- **Nested Pydantic models** — deeply nested schemas sometimes cause
  Anthropic's tool-extraction mechanism to hallucinate missing inner fields.
  Flatten one level when debugging unexpected nulls.
- **`Optional` without a default** — `Optional[str]` with no `= None`
  default will still fail validation if the model omits the field. Always
  pair `Optional` with `= None`.
- **Reusing a Pydantic model name** — if two models share the same class
  name (e.g. both called `Output`), JSON schema de-duplication can silently
  merge them. Use unique class names.
- **`with_structured_output` on a chain, not just the LLM** — the method
  lives on the `BaseChatModel`, not on a composed chain. Apply it before
  chaining: `structured_llm = llm.with_structured_output(Schema)`, then
  `chain = prompt | structured_llm`.
