<!-- Source: https://langfuse.com/docs/observability/sdk/upgrade-path/python-v2-to-v3 -->
<!-- Fetched: 2026-03-30 -->
<!-- Langfuse Python SDK v4.0.4 -->

# Python v2 to v3 Migration Guide

## Overview

The Langfuse Python SDK v3 represents a significant departure from v2, introducing OpenTelemetry foundations and breaking backward compatibility. Users should migrate directly to v4 (latest) after completing v2 to v3 changes.

## Core Changes

Key architectural shifts:

- **OpenTelemetry Foundation**: v3 is built on OpenTelemetry standards
- Trace input/output now derives from root observations by default
- Trace attributes (`user_id`, `session_id`, etc.) set via enclosing spans or integration metadata
- Automatic context propagation using OTEL standards

## Migration by Integration Type

### @observe Decorator

**Previous approach:** Used `langfuse_context.update_current_trace()` within decorated functions.

**New approach:** Leverage `get_client()` to access the global client instance and update traces explicitly.

### OpenAI Integration

Two migration paths for trace attributes:

**Option 1 - Metadata fields:** Use `langfuse_user_id`, `langfuse_session_id`, `langfuse_tags` within the metadata dictionary during API calls.

**Option 2 - Enclosing spans:** Wrap calls with `start_as_current_observation()` and `propagate_attributes()` for granular control.

### LangChain Integration

Replace direct constructor parameters with metadata fields in chain invocation, or wrap invocations with enclosing spans for enhanced control.

### LlamaIndex Integration

Migrate from Langfuse callbacks to third-party OpenTelemetry instrumentation (`openinference-instrumentation-llama-index`).

### Low-Level SDK Usage

Replace manual object creation (`trace()`, `generation()`) with context managers using `start_as_current_observation()`.

## Key Migration Checklist

1. **Update imports** - Use `get_client`, `Langfuse`, `observe` appropriately
2. **Trace attributes** - Move to metadata fields or `propagate_attributes()`
3. **Explicit I/O** - Set trace input/output via `span.update_trace()`
4. **Context managers** - Adopt `with` statements instead of manual `.end()` calls
5. **LlamaIndex** - Install and configure third-party OTEL instrumentation
6. **ID management** - Use `Langfuse.create_trace_id(seed=external_id)` for deterministic IDs
7. **Parameter renaming** - `enabled` -> `tracing_enabled`, `threads` -> `media_upload_thread_count`
8. **Datasets** - Use context manager via `run` method instead of `link`

## Important Considerations

**Third-party span capture:** After upgrading, Langfuse captures spans from other OTEL libraries (database, HTTP), potentially increasing costs. Filter unwanted spans by instrumentation scope before broad rollout.

**Deprecated methods:** `update_trace()` becomes deprecated in v4.

## Future v2 Support

> We will continue to support the v2 SDK for the foreseeable future with critical bug fixes and security patches.
