<!-- Source: https://langfuse.com/docs/observability/sdk/advanced-features -->
<!-- Fetched: 2026-03-30 -->
<!-- Langfuse Python SDK v4.0.4 -->

# Advanced Features

## Overview

This page covers hardening Langfuse instrumentation through filtering, masking, logging, sampling, multi-project routing, evaluations, and environment-specific configurations for Python and JS/TS SDKs.

## Filtering by Instrumentation Scope

Langfuse applies a default span filter to maintain LLM-focused exports. Spans are exported if they meet any of these criteria:

- Created by Langfuse SDK (`instrumentation_scope.name == "langfuse-sdk"`)
- Contain at least one `gen_ai.*` attribute
- Originate from known LLM instrumentation scopes (OpenInference, LangSmith, Haystack, LiteLLM, etc.)

**Debugging filtered spans:**

1. Enable debug logging via `Langfuse(debug=True)` or environment variables
2. Check logs for dropped-span messages
3. Compose custom filters with `is_default_export_span` / `isDefaultExportSpan`
4. Temporarily use permissive filters to inspect all spans

> **Warning:** Filtering spans may break the parent-child relationships in your traces, potentially creating orphaned observations.

### Python SDK Examples

Default filtering:

```python
from langfuse import Langfuse
langfuse = Langfuse()
```

Custom composition:

```python
from langfuse import Langfuse
from langfuse.span_filter import is_default_export_span

langfuse = Langfuse(
    should_export_span=lambda span: (
        is_default_export_span(span)
        or (span.instrumentation_scope is not None
            and span.instrumentation_scope.name.startswith("my_framework"))
    )
)
```

Available helpers: `is_default_export_span`, `is_langfuse_span`, `is_genai_span`, `is_known_llm_instrumentor`, `KNOWN_LLM_INSTRUMENTATION_SCOPE_PREFIXES`

### JS/TS SDK Examples

```typescript
import { NodeSDK } from "@opentelemetry/sdk-node";
import { LangfuseSpanProcessor } from "@langfuse/otel";

const shouldExportSpan = ({ otelSpan }) =>
  otelSpan.instrumentationScope.name !== "express";

const sdk = new NodeSDK({
  spanProcessors: [new LangfuseSpanProcessor({ shouldExportSpan })],
});
sdk.start();
```

Compose with defaults:

```typescript
import { isDefaultExportSpan } from "@langfuse/otel";

const shouldExportSpan = ({ otelSpan }) =>
  isDefaultExportSpan(otelSpan) ||
  otelSpan.instrumentationScope.name.startsWith("my-framework");
```

## Masking Sensitive Data

Implement masking functions to redact PII and secrets before transmission.

### Python SDK

```python
from langfuse import Langfuse
import re

def pii_masker(data: any, **kwargs) -> any:
    if isinstance(data, str):
        return re.sub(
            r"[a-zA-Z0-9_.+-]+@[a-zA-Z0-9-]+\.[a-zA-Z0-9-.]+",
            "[EMAIL_REDACTED]",
            data
        )
    elif isinstance(data, dict):
        return {k: pii_masker(data=v) for k, v in data.items()}
    elif isinstance(data, list):
        return [pii_masker(data=item) for item in data]
    return data

langfuse = Langfuse(mask=pii_masker)
```

### JS/TS SDK

```typescript
import { NodeSDK } from "@opentelemetry/sdk-node";
import { LangfuseSpanProcessor } from "@langfuse/otel";

const spanProcessor = new LangfuseSpanProcessor({
  mask: ({ data }) =>
    data.replace(
      /\b\d{4}[- ]?\d{4}[- ]?\d{4}[- ]?\d{4}\b/g,
      "***MASKED_CREDIT_CARD***"
    ),
});

const sdk = new NodeSDK({ spanProcessors: [spanProcessor] });
sdk.start();
```

## Logging and Debugging

### Python SDK

Environment variable:

```bash
export LANGFUSE_DEBUG="True"
```

In code:

```python
import logging
langfuse_logger = logging.getLogger("langfuse")
langfuse_logger.setLevel(logging.DEBUG)
```

Or during initialization: `Langfuse(debug=True)`

### JS/TS SDK

Environment variable:

```bash
export LANGFUSE_LOG_LEVEL="DEBUG"
```

In code:

```typescript
import { configureGlobalLogger, LogLevel } from "@langfuse/core";
configureGlobalLogger({ level: LogLevel.DEBUG });
```

Available levels: `DEBUG`, `INFO`, `WARN`, `ERROR`

## Sampling

Reduce costs and noise by sampling traces in high-volume applications.

### Python SDK

```python
from langfuse import Langfuse
langfuse_sampled = Langfuse(sample_rate=0.2)
```

Or via environment variable:

```bash
export LANGFUSE_SAMPLE_RATE="0.2"
```

### JS/TS SDK

```typescript
import { NodeSDK } from "@opentelemetry/sdk-node";
import { TraceIdRatioBasedSampler } from "@opentelemetry/sdk-trace-base";
import { LangfuseSpanProcessor } from "@langfuse/otel";

const sdk = new NodeSDK({
  sampler: new TraceIdRatioBasedSampler(0.2),
  spanProcessors: [new LangfuseSpanProcessor()],
});
sdk.start();
```

Or via environment variable:

```bash
export LANGFUSE_SAMPLE_RATE="0.2"
```

## Isolated TracerProvider

Create separate OpenTelemetry TracerProviders for isolation between Langfuse and other observability systems.

**Benefits:**

- Langfuse spans won't reach other backends (Datadog, Jaeger, Zipkin)
- Third-party spans stay out of Langfuse
- Independent configuration and sampling

> **Warning:** TracerProviders are isolated, but they share the same OpenTelemetry context, which can cause parent-child relationship issues and orphaned spans.

### Python SDK

```python
from opentelemetry.sdk.trace import TracerProvider
from langfuse import Langfuse

langfuse_tracer_provider = TracerProvider()
langfuse = Langfuse(tracer_provider=langfuse_tracer_provider)
langfuse.start_observation(name="myspan").end()
```

### JS/TS SDK

```typescript
import { NodeTracerProvider } from "@opentelemetry/sdk-trace-node";
import { setLangfuseTracerProvider } from "@langfuse/tracing";
import { LangfuseSpanProcessor } from "@langfuse/otel";

const langfuseTracerProvider = new NodeTracerProvider({
  spanProcessors: [new LangfuseSpanProcessor()],
});

setLangfuseTracerProvider(langfuseTracerProvider);
```

## Multi-Project Setups

### Python SDK (Experimental)

> **Important Limitation:** Third-party libraries that emit OpenTelemetry spans automatically do not have the Langfuse public key span attribute, causing potential routing issues. This feature is experimental due to requiring `public_key` parameters across all integrations.

Initialization:

```python
from langfuse import Langfuse

project_a_client = Langfuse(
    public_key="pk-lf-project-a-...",
    secret_key="sk-lf-project-a-...",
    base_url="https://cloud.langfuse.com"
)

project_b_client = Langfuse(
    public_key="pk-lf-project-b-...",
    secret_key="sk-lf-project-b-...",
    base_url="https://cloud.langfuse.com"
)
```

Observe decorator (from SDK >= 3.2.2, nested functions automatically inherit context):

```python
from langfuse import observe

@observe
def process_data_for_project_a(data):
    return {"processed": data}

result_a = process_data_for_project_a(
    data="input data",
    langfuse_public_key="pk-lf-project-a-..."
)
```

OpenAI integration:

```python
from langfuse.openai import openai

client = openai.OpenAI()
response_a = client.chat.completions.create(
    model="gpt-4o",
    messages=[{"role": "user", "content": "Hello from Project A"}],
    langfuse_public_key="pk-lf-project-a-..."
)
```

LangChain integration:

```python
from langfuse.langchain import CallbackHandler

handler_a = CallbackHandler(public_key="pk-lf-project-a-...")
handler_b = CallbackHandler(public_key="pk-lf-project-b-...")

response_a = chain.invoke(
    {"topic": "machine learning"},
    config={"callbacks": [handler_a]}
)
```

### JS/TS SDK

```typescript
import { NodeSDK } from "@opentelemetry/sdk-node";
import { LangfuseSpanProcessor } from "@langfuse/otel";

const sdk = new NodeSDK({
  spanProcessors: [
    new LangfuseSpanProcessor({
      publicKey: "pk-lf-public-key-project-1",
      secretKey: "sk-lf-secret-key-project-1",
    }),
    new LangfuseSpanProcessor({
      publicKey: "pk-lf-public-key-project-2",
      secretKey: "sk-lf-secret-key-project-2",
    }),
  ],
});

sdk.start();
```

## Time to First Token (TTFT)

Manually set TTFT measurements for LLM latency analysis.

### Python

```python
from langfuse import get_client
import datetime, time

langfuse = get_client()

with langfuse.start_as_current_observation(
    as_type="generation",
    name="TTFT-Generation"
) as generation:
    time.sleep(3)
    generation.update(
        completion_start_time=datetime.datetime.now(),
        output="some response",
    )

langfuse.flush()
```

### JS/TS

```typescript
import { startActiveObservation } from "@langfuse/tracing";

startActiveObservation("llm-call", async (span) => {
  span.update({
    completionStartTime: new Date().toISOString(),
  });
});
```

## Self-Signed SSL Certificates

For self-hosted Langfuse with self-signed certificates:

Set OpenTelemetry certificate:

```bash
export OTEL_EXPORTER_OTLP_TRACES_CERTIFICATE="/path/to/my-selfsigned-cert.crt"
```

Configure HTTPX client:

```python
import os
import httpx
from langfuse import Langfuse

httpx_client = httpx.Client(
    verify=os.environ["OTEL_EXPORTER_OTLP_TRACES_CERTIFICATE"]
)
langfuse = Langfuse(httpx_client=httpx_client)
```

> **Warning:** Changing SSL settings has major security implications depending on your environment.

## Thread Pools and Multiprocessing

### Python

Enable OpenTelemetry threading instrumentation:

```python
from opentelemetry.instrumentation.threading import ThreadingInstrumentor

ThreadingInstrumentor().instrument()
```

For multiprocessing, follow OpenTelemetry guidance. If using Pydantic Logfire, enable `distributed_tracing=True`. For cross-process tracing, see distributed tracing documentation.
