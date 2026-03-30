# Troubleshooting: Diagnostic Decision Tree

## No Traces Appearing

**Symptom**: Langfuse UI shows no traces after running instrumented code.

**Likely Cause 1: Missing flush** (most common)
The SDK sends data asynchronously in background batches. Short-lived processes exit before the buffer drains.

Fix: Add `langfuse.flush()` (or `langfuse.shutdown()` for scripts, NOT serverless) before process exit. Use a `finally` block.

**Likely Cause 2: Tracing disabled**

Fix: Ensure `Langfuse(tracing_enabled=True)` (default) and `LANGFUSE_TRACING_ENABLED` is not `"false"`.

**Likely Cause 3: Sample rate is 0**

Fix: Ensure `Langfuse(sample_rate=1.0)` (default) and `LANGFUSE_SAMPLE_RATE` is not `"0"`.

**Likely Cause 4: Auth failure (silent)**

Fix: `Langfuse(debug=True)` then `langfuse.auth_check()`. Or `export LANGFUSE_DEBUG="True"`. Debug logs reveal exporter behavior and auth errors.

---

## Incorrect Nesting or Missing Spans

**Symptom**: Traces appear flat instead of hierarchical, or some spans are missing.

**Likely Cause 1: Using manual observations without context managers**

Fix: Prefer context managers over manual `start_observation()`:
```python
# WRONG: manual observation does not shift context
obs = langfuse.start_observation(name="child")
# ... child work -- subsequent observations are NOT children of obs
obs.end()

# RIGHT: context manager shifts active context
with langfuse.start_as_current_observation(as_type="span", name="parent"):
    with langfuse.start_as_current_observation(as_type="span", name="child"):
        pass  # child is properly nested under parent
```

**Likely Cause 2: Platform version too old for self-hosted**

Fix: Self-hosted Langfuse requires platform version 3.63.0 or later for OTEL-based SDKs. Upgrade the server.

**Likely Cause 3: Async context loss**

Fix: Use Langfuse async helpers. Ensure `@observe()` decorated async functions use `await` properly.

Verification: Enable debug logging and inspect parent-child IDs in span output.

---

## OTEL Context Collisions

**Symptom**: Unexpected parent-child relationships, orphaned spans, or Langfuse spans appearing in Datadog/Sentry.

**Likely Cause**: Langfuse shares the global OpenTelemetry context with other OTEL tools (Sentry, Datadog, Pydantic Logfire). A parent span from one TracerProvider can accidentally adopt children from another.

Fix: Use an isolated TracerProvider:
```python
from opentelemetry.sdk.trace import TracerProvider
from langfuse import Langfuse

langfuse = Langfuse(tracer_provider=TracerProvider())
```

Caveat: TracerProviders are isolated but share the same OTEL context. Filtering spans may break parent-child relationships and create orphaned observations.

Verification: Check that Langfuse traces no longer contain spans from other instrumentors, and vice versa.

---

## Missing Traces with Streaming

**Symptom**: Streaming OpenAI calls produce incomplete or missing observations.

**Likely Cause 1: Premature break**

The wrapper finalizes the observation only when the stream iterator completes. Breaking early produces an incomplete observation with missing token counts.

Fix: Always consume the full stream:
```python
from langfuse.openai import openai

stream = openai.chat.completions.create(
    model="gpt-4o", messages=[...], stream=True,
    stream_options={"include_usage": True}
)
result = ""
for chunk in stream:
    if chunk.choices:
        result += chunk.choices[0].delta.content or ""
# Do NOT break early
```

**Likely Cause 2: Empty choices chunk crash**

When `stream_options={"include_usage": True}`, OpenAI sends a final chunk with empty `choices`. Code that accesses `chunk.choices[0]` without a guard crashes.

Fix: Always check `if chunk.choices:` before accessing.

Verification: Confirm the complete observation appears in Langfuse with token counts populated.

---

## Credential Ordering

**Symptom**: Auth errors or no traces despite correct credentials in `.env`.

**Likely Cause**: Environment variables must be set BEFORE importing the Langfuse SDK. The singleton initializes on first import.

Fix: Set env vars BEFORE `from langfuse import Langfuse`, or pass credentials directly to constructor. In Jupyter, restart the kernel after changing credentials. Verify with `langfuse.auth_check()`.

---

## Azure OpenAI Model Names

**Symptom**: Token costs show as $0 or missing for Azure OpenAI generations.

**Likely Cause**: Azure deployments use custom deployment names, not standard model names. Langfuse cannot match the deployment name to a pricing model.

Fix: Explicitly set `model=` on `AzureChatOpenAI`:
```python
from langchain_openai import AzureChatOpenAI

llm = AzureChatOpenAI(
    azure_deployment="my-gpt4-deployment",
    model="gpt-4o",  # REQUIRED for Langfuse cost matching
)
```

Verification: Check that the generation in Langfuse shows the correct model name and cost.

---

## Third-Party Spans Leaking Across Projects

**Symptom**: Spans from other OTEL-instrumented libraries (database drivers, HTTP clients) appear in Langfuse, or spans route to the wrong project in multi-project setups.

**Likely Cause**: v3+ captures spans from any OTEL-instrumented library. Third-party spans lack the Langfuse public key attribute, causing routing issues in multi-project setups.

Fix: v4 smart span filtering is on by default. Compose custom filters with `should_export_span` callback using `is_default_export_span` from `langfuse.span_filter`. To export everything: `Langfuse(should_export_span=lambda span: True)`.

---

## ThreadPoolExecutor Context Loss

**Symptom**: `@observe` decorated functions called from `ThreadPoolExecutor` produce disconnected traces or no spans.

**Likely Cause**: `contextvars` are not copied to new threads by default. OTEL context propagation breaks.

Fix:
```python
from opentelemetry.instrumentation.threading import ThreadingInstrumentor
ThreadingInstrumentor().instrument()
```

For `ProcessPoolExecutor`, follow OpenTelemetry multiprocessing guidance. If using Pydantic Logfire, enable `distributed_tracing=True`.

Verification: Spans from thread pool tasks appear as children of the calling span.

---

## LangChain Callbacks Backgrounded in Serverless

**Symptom**: LangChain traces are incomplete or missing in serverless environments (Lambda, Cloud Functions).

**Likely Cause**: LangChain runs callbacks in background threads by default. Serverless runtimes kill the process before callbacks complete.

Fix: Set callbacks to blocking mode:
```bash
export LANGCHAIN_CALLBACKS_BACKGROUND="false"
```

Also ensure explicit flush:
```python
from langfuse import get_client
get_client().flush()
```

Verification: Traces appear completely in Langfuse after each invocation.

---

## Manual Spans Without .end()

**Symptom**: Some spans appear in the trace but are marked incomplete, or are missing entirely.

**Likely Cause**: Manual observations created with `start_observation()` require explicit `.end()`. Without it, the span is never exported.

Fix: Always prefer context managers:
```python
# WRONG
obs = langfuse.start_observation(name="my-span")
# forgot obs.end()

# RIGHT: context manager auto-closes
with langfuse.start_as_current_observation(as_type="span", name="my-span") as span:
    span.update(output="result")
# .end() called automatically
```

If you must use manual observations, always call `.end()` in a `finally` block.

---

## Media Not Appearing

**Symptom**: Audio or image payloads are not visible in the Langfuse UI.

**Likely Cause**: Raw bytes/base64 strings are not automatically handled. Media requires `LangfuseMedia` objects for proper upload.

Fix: Wrap media content:
```python
from langfuse import LangfuseMedia

media = LangfuseMedia(content=image_bytes, content_type="image/png")
span.update(output={"image": media})
```

Verification: Enable debug logging -- upload errors appear in background thread logs.

---

## Cost Tracking: Token Counts Missing

**Symptom**: Generations appear in Langfuse but cost shows $0 or "N/A".

**Likely Cause 1: No usage_details provided and model not in Langfuse's built-in list**

Fix: Ingest usage explicitly:
```python
generation.update(
    usage_details={
        "input": response.usage.input_tokens,
        "output": response.usage.output_tokens,
    }
)
```

**Likely Cause 2: Model name doesn't match any model definition**

Fix: Check the `model` parameter matches a Langfuse model definition. Add a custom model definition in Project Settings > Models if needed.

**Likely Cause 3: Reasoning models (o1 family)**

Cost inference by tokenization is NOT supported for reasoning models -- reasoning tokens are invisible to Langfuse. You must provide token usage from the API response.

**Likely Cause 4: Only generation/embedding types support cost**

Fix: Ensure the observation has `as_type="generation"` or `as_type="embedding"`. Plain spans do not track cost.

Verification: Check the generation detail view in Langfuse -- usage_details and cost_details should be populated.

---

## Quick Debug Checklist

1. Enable debug: `Langfuse(debug=True)` or `LANGFUSE_DEBUG=True`
2. Verify auth: `get_client().auth_check()`
3. Check flush: `get_client().flush()` before process exit
4. Check sample rate: `LANGFUSE_SAMPLE_RATE` is not 0
5. Check tracing enabled: `LANGFUSE_TRACING_ENABLED` is not false
6. Check platform version: self-hosted needs >= 3.63.0 for v3/v4 SDK
7. Check for OTEL conflicts: Sentry, Datadog, Logfire -> use isolated TracerProvider
