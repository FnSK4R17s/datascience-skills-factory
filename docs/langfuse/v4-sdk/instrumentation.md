<!-- Source: https://langfuse.com/docs/observability/sdk/instrumentation -->
<!-- Fetched: 2026-03-30 -->
<!-- Langfuse Python SDK v4.0.4 -->

# Instrumentation

## Overview

The Langfuse SDKs provide two primary instrumentation approaches:

1. **Native integrations** for popular LLM libraries (OpenAI, LangChain, Vercel AI SDK) that automatically capture observations, traces, prompts, responses, usage, and errors
2. **Manual instrumentation** using three patterns: context managers, observe wrappers, and manual observations

All approaches are interoperable and can be combined within the same trace.

## Custom Instrumentation Methods

### Context Manager

The context manager creates a new span and sets it as the active observation in the OpenTelemetry context. Child observations created within the block inherit the parent automatically.

**Python SDK**: `start_as_current_observation()` updates the active context. Observations can specify types via the `as_type` parameter.

**JS/TS SDK**: `startActiveObservation` accepts a callback, activates the span for callback scope, and automatically ends it even across async boundaries.

Key characteristics:

- Automatically manages span lifecycle
- Child observations inherit parent automatically
- Supports different observation types (span, generation, etc.)

### Observe Wrapper (Decorator)

The observe decorator automatically captures function inputs, outputs, timings, and errors without modifying internal logic.

**Python SDK**: Use `@observe()` decorator to wrap functions and specify `as_type` parameter for observation type.

**JS/TS SDK**: Use `observe()` wrapper function with configuration options including `asType`.

> **Note:** Capturing large inputs/outputs may add overhead. Disable via `capture_input=False`, `capture_output=False` or the `LANGFUSE_OBSERVE_DECORATOR_IO_CAPTURE_ENABLED` environment variable.

### Manual Observations

Manual creation offers explicit lifecycle control for:

- Self-contained work happening in parallel to main execution
- Observations with non-contiguous start/end events
- Obtaining observation references before context binding

**Python SDK**: `start_observation()` creates observations without changing active context. Must explicitly call `.end()`.

**JS/TS SDK**: `startObservation()` provides full control. Returns observation object that must be manually ended.

> **Critical requirement**: Always call `.end()` on manually created observations or they will be incomplete/missing in Langfuse.

**Context behavior**: Manual observations don't shift the active context. They become children of the active span at creation time, but subsequent observations created globally remain parented to the original active span, not the manual one.

## Nesting Observations

Nesting happens automatically through OpenTelemetry's context propagation:

- **Decorator**: Function call hierarchy automatically reflects in the trace
- **Context manager**: New observations become children of the currently active observation
- **Manual observations**: Use methods on parent objects (e.g., `parent.start_observation()`) to create nested children

## Updating Observations

**Python SDK**:

- Use `.update()` on observation objects for direct references
- Use `langfuse.update_current_span()` or `langfuse.update_current_generation()` for active observations without direct references

**JS/TS SDK**: Call `observation.update()` on the active observation

## Adding Attributes

Use attribute propagation to add:

- `userId`
- `sessionId`
- `metadata`
- `version`
- `tags`
- `traceName`

**Python SDK**: `propagate_attributes()` context manager propagates attributes to nested observations.

**JS/TS SDK**: `propagateAttributes()` function propagates attributes within callback scope.

For cross-service propagation, enable the `as_baggage` (Python) or `asBaggage` (JS/TS) parameter to propagate attributes via HTTP headers using OpenTelemetry baggage.

> **Security warning**: Baggage propagation adds attributes to all outbound HTTP headers. Only use with non-sensitive values.

## Trace Input/Output Behavior

By default, trace-level input/output mirror the root observation (first observation in trace). Override this behavior if needed for LLM-as-a-Judge, AB-tests, or UI clarity.

**Python SDK**: Use deprecated `set_trace_io()` or `langfuse.set_current_trace_io()` to override (for backward compatibility only).

**JS/TS SDK**: Use deprecated `setTraceIO()` for backward compatibility.

> **Recommendation**: Set input/output directly on the root observation rather than using deprecated methods.

## Trace and Observation IDs

Langfuse follows W3C Trace Context standard:

- Trace IDs: 32-character lowercase hex strings (16 bytes)
- Observation IDs: 16-character lowercase hex strings (8 bytes)

**Python SDK**:

- `create_trace_id(seed=...)` generates deterministic IDs
- `get_current_trace_id()` retrieves active trace ID
- `get_current_observation_id()` retrieves active observation ID
- Access via `observation.trace_id` and `observation.id`

**JS/TS SDK**:

- `createTraceId(seed)` generates deterministic IDs
- `getActiveTraceId()` retrieves active trace ID
- `getActiveSpanId()` retrieves active observation ID

Use deterministic IDs to correlate external system IDs with Langfuse traces via the same seed value.

Link to existing traces by supplying W3C trace context via `trace_context` (Python) or `parentSpanContext` (JS/TS) parameters.

## Client Lifecycle and Flushing

The SDKs buffer spans asynchronously in the background. Short-lived processes (scripts, serverless functions, workers) must flush or shutdown before exiting.

**Python SDK**:

- `flush()`: Sends all buffered observations to Langfuse API
- `shutdown()`: Flushes data, waits for background threads to finish, releases resources. Auto-registers `atexit` hook but manual invocation recommended for daemons and serverless environments.

**JS/TS SDK**:

- Export `LangfuseSpanProcessor` from instrumentation setup
- Call `forceFlush()` in serverless function handlers before exit
- In Vercel Cloud Functions, use the `after` utility to schedule flush after request completion
- Optional: Set `exportMode: "immediate"` for immediate span export in serverless environments
