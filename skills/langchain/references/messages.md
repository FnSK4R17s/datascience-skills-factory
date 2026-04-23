# Messages

Source: `docs/messages.md`

Messages are the primary unit of context in LangChain. Every model invocation
accepts a sequence of messages and returns an `AIMessage`.

## Message types

| Class | Role | Purpose |
|-------|------|---------|
| `SystemMessage` | `system` | Instructions that prime model behaviour |
| `HumanMessage` | `user` | User input, can be text or multimodal |
| `AIMessage` | `assistant` | Model response; contains text, tool calls, reasoning |
| `ToolMessage` | `tool` | Result of a tool execution, tied to a `tool_call_id` |

```python
from langchain.messages import SystemMessage, HumanMessage, AIMessage, ToolMessage
```

All message classes are importable from `langchain.messages` in v1+.

## Input formats

Three equivalent ways to pass messages to `model.invoke()` or `agent.invoke()`:

```python
# 1. Message objects
messages = [SystemMessage("Be concise."), HumanMessage("Hello")]

# 2. Dict (OpenAI chat completions format)
messages = [
    {"role": "system", "content": "Be concise."},
    {"role": "user", "content": "Hello"},
]

# 3. Plain string (shortcut for a single HumanMessage)
response = model.invoke("Write a haiku about spring")
```

## AIMessage attributes

```python
response = model.invoke(messages)

response.text            # str — plain text output (convenience property)
response.content         # str | list — raw provider payload
response.content_blocks  # list[dict] — normalized, type-safe representation (new in v1)
response.tool_calls      # list[dict] — [{name, args, id, type}]
response.usage_metadata  # {input_tokens, output_tokens, total_tokens, ...}
response.response_metadata  # provider-specific metadata
response.id              # unique message identifier
```

`content_blocks` is lazy — it parses `content` on first access and normalises
provider-specific formats (Anthropic `thinking`, OpenAI `reasoning_summary`) into
a standard `"reasoning"` block type.

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
| `"non_standard"` | Provider escape hatch | `value` (dict) |

Filtering content blocks by type is the standard pattern for extracting
reasoning tokens during streaming (see `streaming.md`).

## Multimodal input

Pass multimodal content in `HumanMessage.content` as a list of dicts:

```python
# Image from URL
message = HumanMessage(content=[
    {"type": "text", "text": "What's in this image?"},
    {"type": "image", "url": "https://example.com/photo.jpg"},
])

# Image from base64
message = HumanMessage(content=[
    {"type": "text", "text": "Describe this image."},
    {"type": "image", "base64": "<base64-encoded-data>", "mime_type": "image/jpeg"},
])

# PDF from URL
message = HumanMessage(content=[
    {"type": "text", "text": "Summarize this document."},
    {"type": "file", "url": "https://example.com/report.pdf"},
])
```

Extra provider-specific keys (e.g., `filename` required by AWS Bedrock for PDFs)
can be included top-level in the content block or nested in `"extras": {...}`.

Not all providers support all modalities. Check the provider's integration page.

## ToolMessage

Tools return results as `ToolMessage`. The `tool_call_id` must match the
`id` from the corresponding `AIMessage.tool_calls` entry.

```python
tool_message = ToolMessage(
    content="Sunny, 72F",
    tool_call_id="call_abc123",
    name="get_weather",      # tool name
    artifact={"raw": {...}}, # supplementary data NOT sent to model
)
```

The `artifact` field stores data for downstream processing (e.g., document IDs
for rendering) without cluttering the model's context.

## Serializing content_blocks

To store `content_blocks` format in `content` (for external consumers):

```python
model = init_chat_model("gpt-4o", output_version="v1")
# or
# export LC_OUTPUT_VERSION=v1
```

## Streaming chunks

During streaming, `AIMessageChunk` objects are emitted. They accumulate into a
full message via the `+` operator:

```python
full_msg = None
for chunk in model.stream("Hi"):
    print(chunk.text)
    full_msg = chunk if full_msg is None else full_msg + chunk
```

`chunk.chunk_position` is `"last"` on the final chunk — useful for detecting
when a complete tool call has been assembled.
