# Streaming

LangChain v1 provides two streaming surfaces: `.stream()` / `.astream()`
for raw output chunks, and `.astream_events()` for structured event streams
that carry source metadata.

## Basic token streaming

```python
# Sync
for chunk in chain.stream({"question": "Explain quantum entanglement."}):
    print(chunk, end="", flush=True)

# Async
async for chunk in chain.astream({"question": "..."}):
    print(chunk, end="", flush=True)
```

What `chunk` contains depends on the last step in the chain:
- After a chat model: `AIMessageChunk`
- After `StrOutputParser`: a `str` fragment
- After `JsonOutputParser`: a partial dict (may be invalid JSON mid-stream)

## astream_events (v2)

`astream_events` is the recommended pattern for UI integration. It emits
structured events for every step in the chain, not just the final output.

```python
async for event in chain.astream_events(input, version="v2"):
    kind = event["event"]
    name = event["name"]

    if kind == "on_chat_model_stream":
        chunk = event["data"]["chunk"]          # AIMessageChunk
        print(chunk.content, end="", flush=True)

    elif kind == "on_tool_start":
        print(f"\n[Calling tool: {name}]")

    elif kind == "on_chain_end":
        pass                                     # chain finished
```

Always pass `version="v2"`. The v1 event schema is deprecated.

## Key event types

| Event name | When it fires |
|-----------|--------------|
| `on_chat_model_start` | LLM call begins |
| `on_chat_model_stream` | Each token chunk |
| `on_chat_model_end` | LLM call finished |
| `on_chain_start` | Any chain / LCEL step starts |
| `on_chain_end` | Any chain / LCEL step ends |
| `on_tool_start` | Tool invocation begins |
| `on_tool_end` | Tool invocation finished |
| `on_retriever_start` | Retriever query begins |
| `on_retriever_end` | Retriever query finished |

Filter by `event["name"]` to isolate specific components, e.g.:

```python
if event["event"] == "on_chat_model_stream" and event["name"] == "my_llm":
    ...
```

Assign names via `llm = ChatOpenAI(...).with_config({"run_name": "my_llm"})`.

## Streaming from agents (LangGraph)

LangGraph streams at the graph level. Prefer `astream_events` over
`astream` when you need token-level output from inside nodes:

```python
async for event in graph.astream_events(input, version="v2"):
    if event["event"] == "on_chat_model_stream":
        print(event["data"]["chunk"].content, end="", flush=True)
```

For state-level streaming (graph step outputs), use `graph.astream()`:

```python
async for state_update in graph.astream(input):
    print(state_update)   # dict of node outputs per step
```

## UI integration patterns

**SSE (Server-Sent Events) with FastAPI:**

```python
from fastapi import FastAPI
from fastapi.responses import StreamingResponse

app = FastAPI()

@app.post("/stream")
async def stream_endpoint(body: dict):
    async def generate():
        async for chunk in chain.astream(body):
            yield f"data: {chunk}\n\n"
    return StreamingResponse(generate(), media_type="text/event-stream")
```

**WebSocket:**

```python
@app.websocket("/ws")
async def ws_endpoint(websocket):
    await websocket.accept()
    data = await websocket.receive_json()
    async for chunk in chain.astream(data):
        await websocket.send_text(chunk)
```

## Common traps

- **Breaking out of the stream iterator early** — if you `break` from
  `astream()` before the iterator is exhausted, the underlying HTTP
  connection may not be closed cleanly. Use `aclose()` if you need to abort.
- **`astream_events` with sync runnables** — `astream_events` requires every
  step to support async. A `RunnableLambda` wrapping a sync function is fine;
  a blocking I/O call inside will stall the event loop.
- **Structured output + streaming** — `with_structured_output` buffers the
  full response before parsing. Do not expect partial parsed objects from
  `.stream()` on a structured-output chain.
- **Missing `version="v2"`** — omitting the version argument uses v1 events,
  which have a different schema and are deprecated. Always pass `version="v2"`.
- **Token counts in streaming** — usage metadata (token counts) is typically
  only available in the final chunk or in the `on_chat_model_end` event, not
  in intermediate chunks.
