<!-- Source: https://langfuse.com/docs/observability/sdk/upgrade-path/python-v3-to-v4 -->
<!-- Fetched: 2026-03-30 -->
<!-- Langfuse Python SDK v4.0.4 -->

# Python v3 to v4 Migration Guide

## Overview

The Python SDK v4 introduces an "observation-centric data model" where correlating attributes like `user_id` and `session_id` propagate to every observation. This replaces the previous approach of updating trace objects imperatively with `update_current_trace()`, shifting to `propagate_attributes()` as a context manager.

**Key change:** v4 introduces a smart default span filter to reduce trace noise from non-LLM instrumentation.

## Breaking Changes Summary

### 1. Smart Default Span Filtering

V4 no longer exports all OpenTelemetry spans by default. Spans are exported only if:

- Created by Langfuse SDK
- Contains `gen_ai.*` attributes
- Instrumentation scope matches known LLM prefixes (openinference, langsmith, etc.)

**To restore pre-v4 behavior:**

```python
from langfuse import Langfuse
langfuse = Langfuse(should_export_span=lambda span: True)
```

**To compose custom filters:**

```python
from langfuse import Langfuse
from langfuse.span_filter import is_default_export_span

langfuse = Langfuse(
    should_export_span=lambda span: (
        is_default_export_span(span)
        or span.instrumentation_scope.name.startswith("my_framework")
    )
)
```

The deprecated `blocked_instrumentation_scopes` parameter still works but should migrate to `should_export_span`.

### 2. `update_current_trace()` Decomposed

The single method splits into three:

| Attribute | v3 | v4 |
|-----------|----|----|
| `name` | `update_current_trace(name=...)` | `propagate_attributes(trace_name=...)` |
| `user_id`, `session_id`, `tags`, `version` | `update_current_trace(...)` | `propagate_attributes(...)` |
| `metadata` | `update_current_trace(metadata=any)` | `propagate_attributes(metadata=dict[str,str])` |
| `input`, `output` | `update_current_trace(...)` | `set_current_trace_io(...)` |
| `public` | `update_current_trace(public=True)` | `set_current_trace_as_public()` |
| `release` | `update_current_trace(release=...)` | Use `LANGFUSE_RELEASE` env var |
| `environment` | `update_current_trace(environment=...)` | Use `LANGFUSE_TRACING_ENVIRONMENT` env var |

**V3 example:**

```python
langfuse.update_current_trace(
    name="trace-name",
    user_id="user-123",
    metadata={"key": "value"},
    tags=["tag1"],
    public=True,
)
```

**V4 example:**

```python
from langfuse import observe, propagate_attributes, get_client

@observe()
def my_function():
    with propagate_attributes(
        trace_name="trace-name",
        user_id="user-123",
        metadata={"key": "value"},
        tags=["tag1"],
    ):
        result = call_llm("hello")

    langfuse.set_current_trace_io(input={...}, output={...})
    langfuse.set_current_trace_as_public()
```

> **Note:** `set_current_trace_io()` is deprecated and exists only for backward compatibility with legacy trace-level evaluation patterns.

### 3. Observation-Level Changes

The same decomposition applies to `span.update_trace()`:

```python
# V4 replacement
with langfuse.start_as_current_observation(as_type="span", name="my-op") as span:
    with propagate_attributes(trace_name="trace-name", user_id="user-123"):
        result = call_llm("hello")
    span.set_trace_io(input={...}, output={...})
    span.set_trace_as_public()
```

### 4. Public API Namespace Remapping

| V3 Name | V4 Name |
|---------|---------|
| `api.observations_v_2` | `api.observations` |
| `api.score_v_2` | `api.scores` |
| `api.metrics_v_2` | `api.metrics` |
| `api.observations` (legacy) | `api.legacy.observations_v1` |
| `api.score` (legacy) | `api.legacy.score_v1` |
| `api.metrics` (legacy) | `api.legacy.metrics_v1` |

> **Warning for self-hosted:** Do not use the new defaults yet if self-hosting; use `api.legacy.observations_v1` and `api.legacy.metrics_v1` until v2 endpoints are available.

### 5. Unified Observation API

`start_span()` and `start_generation()` consolidate into `start_observation()`:

| V3 | V4 |
|----|-----|
| `start_span(name="x")` | `start_observation(name="x")` |
| `start_generation(name="x", model="gpt-4")` | `start_observation(name="x", as_type="generation", model="gpt-4")` |
| `start_as_current_span(name="x")` | `start_as_current_observation(name="x")` |
| `start_as_current_generation(name="x")` | `start_as_current_observation(name="x", as_type="generation")` |

### 6. Dataset Experiments

`DatasetItemClient.run()` is removed in favor of the Experiment SDK:

**V3:**

```python
for item in dataset.items:
    with item.run(run_name="my-run", run_metadata={...}) as span:
        result = my_llm(item.input)
        span.update(output=result)
```

**V4:**

```python
from langfuse import get_client

dataset = get_client().get_dataset("my-dataset")

def my_task(*, item, **kwargs):
    return my_llm(item.input)

dataset.run_experiment(name="my-run", task=my_task)
```

### 7. LangChain CallbackHandler Changes

The `update_trace` parameter is removed:

```python
# V3
handler = CallbackHandler(update_trace=True, trace_context={...})

# V4
handler = CallbackHandler(trace_context={...})
```

Use `propagate_attributes()` to set trace attributes instead.

### 8. Removed Types

- `TraceMetadata` TypedDict
- `ObservationParams` TypedDict
- `MapValue`, `ModelUsage`, `PromptClient` (moved to `langfuse.model`)

### 9. Pydantic v2 Required

Pydantic v1 support is dropped. Applications on v1 must use the `pydantic.v1` compatibility shim.

### 10. Validation Changes

- `metadata`: Now restricted to `dict[str, str]` with 200-character value limits
- `user_id`, `session_id`: Maximum 200 characters each
- Non-string values are coerced; oversized values are dropped with warnings

## Migration Checklist

1. Audit traces for non-LLM OpenTelemetry spans that may disappear
2. Set `should_export_span=lambda span: True` if preserving pre-v4 behavior
3. Migrate `blocked_instrumentation_scopes` to `should_export_span` composition
4. Replace `update_current_trace()` calls with appropriate decomposed methods
5. Replace `.update_trace()` on observations similarly
6. Replace `start_span()`/`start_generation()` with `start_observation()`
7. Replace `item.run()` with `dataset.run_experiment()`
8. Remove `update_trace` parameter from `CallbackHandler`
9. Verify metadata is `dict[str, str]` with <=200 character values
10. Upgrade to Pydantic v2
11. Update API namespace references to remove `_v_2` aliases
12. Move legacy v1 API calls to `api.legacy.*` namespaces
13. For self-hosted: avoid new `api.observations`/`api.metrics` until v2 available
14. Remove remaining `*_v_2` alias references
