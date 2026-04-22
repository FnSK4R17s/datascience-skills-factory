# Messages

LangChain v1 represents all LLM input and output as typed message objects.
The message layer is the provider abstraction: your code uses generic types;
each provider integration translates to its wire format.

## Core types (langchain-core)

| Class | Role |
|-------|------|
| `HumanMessage` | User turn |
| `AIMessage` | Assistant turn; carries `tool_calls` when the model calls a tool |
| `SystemMessage` | System prompt |
| `ToolMessage` | Result returned to the model after a tool call |
| `AIMessageChunk` | Streaming chunk; accumulates into `AIMessage` via `+` |

All live in `langchain_core.messages`.

## Building messages

```python
from langchain_core.messages import HumanMessage, SystemMessage, AIMessage

messages = [
    SystemMessage(content="You are a concise assistant."),
    HumanMessage(content="Explain asyncio in one sentence."),
]
response: AIMessage = llm.invoke(messages)
print(response.content)
```

## Content blocks (multimodal)

`content` is `str | list[dict]`. For multimodal payloads, use the list form
with typed blocks:

```python
# Image (base64 or URL — provider-dependent)
HumanMessage(content=[
    {"type": "text", "text": "What do you see?"},
    {"type": "image_url", "image_url": {"url": "https://example.com/img.jpg"}},
])

# Document (Anthropic models)
HumanMessage(content=[
    {"type": "text", "text": "Summarize this document."},
    {
        "type": "document",
        "source": {"type": "base64", "media_type": "application/pdf", "data": "<b64>"},
    },
])
```

Not every provider supports every block type. Check the provider integration
docs — passing an unsupported block type typically raises a validation error,
not a silent failure.

## Tool calls inside AIMessage

When a model requests a tool call, it arrives as a structured field, not
embedded text:

```python
msg: AIMessage = llm_with_tools.invoke(messages)
for tc in msg.tool_calls:
    print(tc["name"], tc["args"])   # {"name": "...", "args": {...}, "id": "..."}
```

Tool call IDs must be echoed back in `ToolMessage.tool_call_id` so the model
matches results to requests.

## Accumulating streaming chunks

```python
from langchain_core.messages import AIMessageChunk

chunks: list[AIMessageChunk] = []
async for chunk in llm.astream(messages):
    chunks.append(chunk)

full_msg = chunks[0]
for c in chunks[1:]:
    full_msg = full_msg + c          # AIMessageChunk supports __add__

print(full_msg.content)              # complete text
print(full_msg.tool_calls)           # accumulated tool calls
```

## ChatPromptTemplate and message variables

```python
from langchain_core.prompts import ChatPromptTemplate, MessagesPlaceholder

prompt = ChatPromptTemplate.from_messages([
    ("system", "You are {persona}."),
    MessagesPlaceholder("history"),   # injects a list[BaseMessage] at runtime
    ("human", "{question}"),
])

chain = prompt | llm
result = chain.invoke({
    "persona": "a pirate",
    "history": [HumanMessage("Ahoy!"), AIMessage("Ahoy, matey!")],
    "question": "What year is it?",
})
```

## Common traps

- **Dict messages** — passing `{"role": "user", "content": "..."}` bypasses
  validation and may silently strip tool-call metadata. Use typed classes.
- **`content` vs. `text`** — `AIMessage.content` may be a list when the
  model returns mixed text+tool output. Always check the type:
  `msg.content if isinstance(msg.content, str) else msg.content[0]["text"]`.
- **`AIMessageChunk` not accumulating tool calls** — partial tool-call JSON
  arrives across multiple chunks; do not attempt to parse `tool_calls` from
  individual chunks. Accumulate first.
- **Provider-specific message extras** — response metadata (finish reason,
  token counts, model name) lives in `msg.response_metadata`, not in
  `content`. Access it after the full message arrives.
