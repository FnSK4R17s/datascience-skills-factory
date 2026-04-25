# Messages

Source: `docs/messages.md`

Messages are the primary unit of context in LangChain. Every model invocation accepts a
sequence of messages and returns an `AIMessage`. All message classes are importable from
`langchain.messages` in v1+.

## Message types

| Class | Role | Purpose |
|-------|------|---------|
| `SystemMessage` | `system` | Instructions that prime model behaviour |
| `HumanMessage` | `user` | User input — text or multimodal |
| `AIMessage` | `assistant` | Model response; contains text, tool calls, reasoning |
| `ToolMessage` | `tool` | Result of a tool execution, tied to a `tool_call_id` |

```python
from langchain.messages import SystemMessage, HumanMessage, AIMessage, ToolMessage
```

## Input formats

Three equivalent ways to pass messages to `model.invoke()` or `agent.invoke()`:

```python
# 1. Message objects (most explicit)
messages = [
    SystemMessage("Be concise and accurate."),
    HumanMessage("What is the capital of France?"),
]

# 2. Dict (OpenAI chat completions format — works everywhere)
messages = [
    {"role": "system", "content": "Be concise and accurate."},
    {"role": "user", "content": "What is the capital of France?"},
]

# 3. Plain string shortcut (single HumanMessage)
response = model.invoke("Write a haiku about spring")
```

## AIMessage attributes

```python
response = model.invoke(messages)

response.text            # str — plain text output (convenience property; v1 new)
response.content         # str | list — raw provider payload
response.content_blocks  # list[dict] — normalized, type-safe representation (new in v1)
response.tool_calls      # list[dict] — [{name, args, id, type}]
response.usage_metadata  # {input_tokens, output_tokens, total_tokens, ...}
response.response_metadata  # provider-specific metadata
response.id              # unique message identifier
response.name            # agent name if set (useful in multi-agent)
```

`content_blocks` is lazy — it parses `content` on first access and normalises
provider-specific formats (Anthropic `thinking`, OpenAI `reasoning_summary`) into the
standard `"reasoning"` block type.

## Standard content blocks

Content blocks are typed dicts. Key block types:

| type | When it appears | Key fields |
|------|-----------------|------------|
| `"text"` | Normal text output | `text` (str) |
| `"reasoning"` | Model reasoning / thinking | `reasoning` (str), `extras` (dict) |
| `"tool_call"` | Tool invocation request | `name`, `args`, `id` |
| `"tool_call_chunk"` | Streaming partial tool call | `name`, `args`, `id`, `index` |
| `"image"` | Image input/output | `url` or `base64`, `mime_type` |
| `"audio"` | Audio data | `url` or `base64`, `mime_type` |
| `"video"` | Video data | `url` or `base64`, `mime_type` |
| `"file"` | Generic file (PDF, etc.) | `url` or `base64`, `mime_type` |
| `"text-plain"` | Plain text document | `text`, `mime_type` |
| `"server_tool_call"` | Server-side tool call | `name`, `args`, `id` |
| `"server_tool_result"` | Server-side tool result | `name`, `result`, `id` |
| `"non_standard"` | Provider escape hatch | `value` (dict) |

Filtering content blocks by type is the standard pattern for extracting
reasoning tokens during streaming:

```python
from langchain.messages import AIMessageChunk

for chunk in model.stream("What is 27 * 41?"):
    for block in chunk.content_blocks:
        if block["type"] == "reasoning":
            print(f"[thinking] {block['reasoning']}", end="")
        elif block["type"] == "text":
            print(block["text"], end="")
```

## Multimodal input

Pass multimodal content in `HumanMessage.content` as a list of dicts:

```python
from langchain.messages import HumanMessage

# Image from URL
message = HumanMessage(content=[
    {"type": "text", "text": "What's in this image?"},
    {"type": "image", "url": "https://example.com/photo.jpg"},
])

# Image from base64
import base64
with open("photo.jpg", "rb") as f:
    b64 = base64.b64encode(f.read()).decode()

message = HumanMessage(content=[
    {"type": "text", "text": "Describe this image."},
    {"type": "image", "base64": b64, "mime_type": "image/jpeg"},
])

# PDF from URL
message = HumanMessage(content=[
    {"type": "text", "text": "Summarize this document."},
    {"type": "file", "url": "https://example.com/report.pdf"},
])

# Audio
message = HumanMessage(content=[
    {"type": "text", "text": "Transcribe this audio."},
    {"type": "audio", "url": "https://example.com/recording.mp3", "mime_type": "audio/mpeg"},
])

# Provider-specific extras (e.g., filename required by AWS Bedrock for PDFs)
message = HumanMessage(content=[
    {"type": "text", "text": "Summarize."},
    {"type": "file", "url": "...", "filename": "report.pdf"},  # extra at top level
    # or: {"type": "file", "url": "...", "extras": {"filename": "report.pdf"}}
])
```

Not all providers support all modalities. Check each provider's integration page.

## SystemMessage for prompt caching (Anthropic)

Pass structured content blocks in SystemMessage to enable Anthropic prompt caching:

```python
from langchain.messages import SystemMessage
from langchain.agents import create_agent

# Content up to each "cache_control" block is cached
large_doc_agent = create_agent(
    model="anthropic:claude-sonnet-4-6",
    tools=[],
    system_prompt=SystemMessage(
        content=[
            {
                "type": "text",
                "text": "You are an AI assistant for document analysis.",
            },
            {
                "type": "text",
                "text": "<the entire contents of a 50K-token knowledge base>",
                "cache_control": {"type": "ephemeral"},  # cache everything up to here
            }
        ]
    )
)
```

## ToolMessage

Tools return results as `ToolMessage`. The `tool_call_id` must match the
`id` from the corresponding `AIMessage.tool_calls` entry.

```python
from langchain.messages import ToolMessage

tool_message = ToolMessage(
    content="Sunny, 72°F with light winds.",   # text sent to model for reasoning
    tool_call_id="call_abc123",                # must match AIMessage.tool_calls[i]["id"]
    name="get_weather",                        # tool name (optional but helpful)
    artifact={"raw_response": {...}},          # supplementary data NOT sent to model
)
```

The `artifact` field stores data for downstream processing (e.g., document objects for
rendering, raw API responses for logging) without cluttering the model's context.

### ToolMessage in multi-turn conversations

```python
from langchain.messages import HumanMessage, AIMessage, ToolMessage

# Manual multi-turn with tool calls
messages = [
    {"role": "user", "content": "Weather in Paris and London?"},
]
response = model.bind_tools([get_weather]).invoke(messages)

# Execute the parallel tool calls
tool_results = []
for tc in response.tool_calls:
    result = get_weather(**tc["args"])
    tool_results.append(ToolMessage(
        content=result,
        tool_call_id=tc["id"],
        name=tc["name"],
    ))

# Continue conversation
messages = messages + [response] + tool_results
final = model.bind_tools([get_weather]).invoke(messages)
print(final.text)
```

## Streaming chunks

During streaming, `AIMessageChunk` objects are emitted. They accumulate into a
full message via the `+` operator:

```python
from langchain.messages import AIMessageChunk

# Accumulate chunks
full_msg = None
for chunk in model.stream("Hi"):
    print(chunk.text, end="")
    full_msg = chunk if full_msg is None else full_msg + chunk

# full_msg is now a complete AIMessage-equivalent with all fields
print(full_msg.tool_calls)  # any tool calls from the streamed response

# chunk_position indicates streaming progress
for chunk in model.stream("Tell me about Paris."):
    if chunk.chunk_position == "last":
        print("\n[Final chunk received]")
        print(f"Tool calls: {chunk.tool_calls}")
```

`chunk.chunk_position` is `"last"` on the final chunk — useful for detecting when a
complete tool call has been assembled during streaming.

## Message serialization and output_version

By default, `message.content` stores the provider-specific raw format. To store the
standard `content_blocks` format in `content` (for external consumers):

```python
from langchain.chat_models import init_chat_model

model = init_chat_model("openai:gpt-5.4", output_version="v1")
# Now response.content == response.content_blocks

# Or globally via environment variable:
# export LC_OUTPUT_VERSION=v1
```

## Message pretty printing

For debugging:

```python
for msg in result["messages"]:
    msg.pretty_print()

# Output:
# ================================ Human Message =================================
# What is the capital of France?
# ================================== Ai Message ==================================
# Tool Calls:
#   search (call_abc123)
#   Args: query: capital of France
# ================================= Tool Message =================================
# Name: search
# Paris is the capital of France.
# ================================== Ai Message ==================================
# The capital of France is Paris.
```

## Filtering messages by type

```python
from langchain.messages import HumanMessage, AIMessage, ToolMessage

all_messages = result["messages"]

# Get all AI messages
ai_messages = [m for m in all_messages if isinstance(m, AIMessage)]

# Get messages with tool calls
tool_call_messages = [m for m in ai_messages if m.tool_calls]

# Get all tool results
tool_messages = [m for m in all_messages if isinstance(m, ToolMessage)]

# Get reasoning blocks from last AI message
last_ai = ai_messages[-1] if ai_messages else None
if last_ai:
    reasoning = [b for b in last_ai.content_blocks if b["type"] == "reasoning"]
    text = [b for b in last_ai.content_blocks if b["type"] == "text"]
```
