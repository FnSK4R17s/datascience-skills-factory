# Python SDK v4 Instrumentation Patterns

## @observe Decorator

The primary instrumentation pattern. Wraps functions in OTEL spans with automatic parent-child nesting via `contextvars`.

```python
from langfuse import observe, get_client

@observe()
def process_request(query: str):
    enriched = enrich_query(query)
    return generate_answer(enriched)

@observe(as_type="span")
def enrich_query(query: str):
    return query.upper()

@observe(as_type="generation")
def generate_answer(text: str):
    client = get_client()
    result = call_llm(text)
    client.update_current_generation(
        model="gpt-4o",
        usage_details={"input_tokens": 50, "output_tokens": 200}
    )
    return result
```

The outermost decorated function creates the trace; inner decorated functions become child spans. `as_type` accepts: `"span"` (default), `"generation"`, `"embedding"`, `"event"`, `"agent"`, `"tool"`.

### Async support

Native -- the decorator detects async functions via `asyncio.iscoroutinefunction()`. Generator functions get special handling: the decorator captures `contextvars.Context` and replays it on each `__next__()` call.

### Disable IO capture

Per-function:
```python
@observe(capture_input=False, capture_output=False)
def sensitive_function(data):
    return process(data)
```

Globally via environment variable:
```bash
export LANGFUSE_OBSERVE_DECORATOR_IO_CAPTURE_ENABLED=false
```

`self`/`cls` are auto-excluded from method inputs. Reserved kwargs (`langfuse_trace_id`, `langfuse_parent_observation_id`, `langfuse_public_key`) are stripped before capture.

### Exception handling

The decorator captures exceptions at each nesting level, sets `level="ERROR"` and `status_message`, ends the observation, and re-raises unchanged.

---

## Context Manager

For cases where decorators are impractical. Auto-calls `.end()` on exit.

```python
from langfuse import get_client

langfuse = get_client()

with langfuse.start_as_current_observation(
    as_type="span", name="user-request", input={"query": "..."}
) as root:
    with langfuse.start_as_current_observation(
        as_type="generation", name="llm-call", model="gpt-4o"
    ) as gen:
        gen.update(output="...", usage_details={"input_tokens": 5, "output_tokens": 50})
```

Context managers compose with `@observe` -- a manual span inside a decorated function automatically becomes a child through OTEL context. Set `end_on_exit=False` to manage lifecycle manually.

---

## Manual Observations

Explicit lifecycle control for parallel work or non-contiguous start/end events.

```python
langfuse = get_client()
obs = langfuse.start_observation(name="background-task", as_type="span")
# ... do work ...
obs.update(output={"result": "done"})
obs.end()  # CRITICAL: must call .end() or observation is incomplete/missing
```

Manual observations do NOT shift the active context. They become children of the active span at creation time, but subsequent observations remain parented to the original active span.

---

## propagate_attributes()

Sets trace-level metadata on all observations created within the context.

```python
from langfuse import propagate_attributes

with propagate_attributes(
    trace_name="my-workflow",
    user_id="user_123",
    session_id="sess_abc",
    metadata={"experiment": "v1"},  # dict[str, str], 200-char value limit in v4
    version="1.0",
    tags=["production"],
):
    result = process_request("hello")
```

For cross-service distributed tracing, `as_baggage=True` propagates attributes via W3C Baggage HTTP headers. Security warning: this adds attributes to ALL outbound HTTP headers -- only use with non-sensitive values.

---

## Trace and Observation IDs

W3C Trace Context standard:
- Trace IDs: 32-character lowercase hex (16 bytes)
- Observation IDs: 16-character lowercase hex (8 bytes)

```python
from langfuse import Langfuse, get_client

# Deterministic ID from external system ID
trace_id = Langfuse.create_trace_id(seed="external-req-12345")

# Retrieve active IDs
langfuse = get_client()
current_trace = langfuse.get_current_trace_id()
current_obs = langfuse.get_current_observation_id()

# Link to existing trace via W3C trace context
with langfuse.start_as_current_observation(
    as_type="span",
    name="linked-span",
    trace_context={"trace_id": trace_id}
) as span:
    pass
```

---

## Flush and Shutdown Patterns

The SDK buffers spans asynchronously via three background paths:
1. OTEL spans: `BatchSpanProcessor` -> Langfuse API
2. Scores: Background consumer thread
3. Media: Presigned upload

### Scripts and notebooks

```python
langfuse = get_client()
# ... do work ...
langfuse.flush()  # blocks until all queues drain
```

### Serverless (Lambda, Cloud Functions)

```python
langfuse = Langfuse(flush_at=10, flush_interval=1.0)

def handler(event, context):
    try:
        result = process(event)
        return result
    finally:
        get_client().flush()  # NOT shutdown() -- breaks container reuse
```

### FastAPI / long-running servers

```python
from contextlib import asynccontextmanager
from fastapi import FastAPI
from langfuse import Langfuse, get_client

@asynccontextmanager
async def lifespan(app: FastAPI):
    Langfuse()
    yield
    get_client().shutdown()  # flush + stop background threads

app = FastAPI(lifespan=lifespan)
```

The SDK registers an `atexit` hook, but it is NOT reliable for all runtimes. Always call `flush()` explicitly in short-lived processes.

---

## Advanced Patterns

### Sampling

```python
from langfuse import Langfuse
langfuse = Langfuse(sample_rate=0.2)  # 20% of traces
```

Or: `export LANGFUSE_SAMPLE_RATE="0.2"`

### Data masking

```python
import re
from langfuse import Langfuse

def pii_masker(data, **kwargs):
    if isinstance(data, str):
        return re.sub(r"[a-zA-Z0-9_.+-]+@[a-zA-Z0-9-]+\.[a-zA-Z0-9-.]+", "[EMAIL_REDACTED]", data)
    elif isinstance(data, dict):
        return {k: pii_masker(data=v) for k, v in data.items()}
    elif isinstance(data, list):
        return [pii_masker(data=item) for item in data]
    return data

langfuse = Langfuse(mask=pii_masker)
```

### Isolated TracerProvider

Prevents OTEL context collisions with Sentry, Datadog, Logfire.

```python
from opentelemetry.sdk.trace import TracerProvider
from langfuse import Langfuse

langfuse = Langfuse(tracer_provider=TracerProvider())
```

Caveat: providers are isolated but share the same OTEL context -- parent-child relationships can still cross boundaries.

### TTFT tracking

```python
import datetime, time
from langfuse import get_client

langfuse = get_client()
with langfuse.start_as_current_observation(as_type="generation", name="llm-call") as gen:
    time.sleep(3)  # simulated wait for first token
    gen.update(completion_start_time=datetime.datetime.now(), output="response")
langfuse.flush()
```

### ThreadPoolExecutor caveat

`@observe` does NOT work with `ThreadPoolExecutor`/`ProcessPoolExecutor` -- `contextvars` are not copied to new threads.

Fix:
```python
from opentelemetry.instrumentation.threading import ThreadingInstrumentor
ThreadingInstrumentor().instrument()
```

---

## Breaking Changes Summary: v2 -> v3 -> v4

| Area | v2 | v3 | v4 |
|------|----|----|-----|
| Foundation | Proprietary protocol | OpenTelemetry | OTEL + smart span filter |
| Client | Multiple instances | Singleton `get_client()` | Singleton (unchanged) |
| Trace attrs | `update_current_trace()` | `update_current_trace()` | `propagate_attributes()` + `set_current_trace_io()` |
| Trace I/O | Explicit | Root observation mirrors | `set_current_trace_io()` (deprecated) |
| Span creation | `start_span()` / `start_generation()` | `start_span()` / `start_generation()` | `start_observation(as_type=...)` |
| LangChain import | `langfuse.callback` | `langfuse.langchain` | `langfuse.langchain` (no `update_trace` param) |
| Datasets | `item.link()` / `item.run()` | `item.run()` | `dataset.run_experiment()` |
| Metadata | Any type | Any type | `dict[str, str]`, 200-char values |
| Pydantic | v1 supported | v1 supported | v2 required |
| Span filter | N/A | Export all OTEL spans | Smart filter (LLM-only by default) |
| `enabled` param | `enabled` | `tracing_enabled` | `tracing_enabled` |
