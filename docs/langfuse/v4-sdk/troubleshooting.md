<!-- Source: https://langfuse.com/docs/observability/sdk/troubleshooting-and-faq -->
<!-- Fetched: 2026-03-30 -->
<!-- Langfuse Python SDK v4.0.4 -->

# Troubleshooting and FAQ

## Overview

This documentation addresses common issues with Python and JavaScript/TypeScript SDKs. For additional help, users can access Ask AI, submit a GitHub issue, or contact support.

## Authentication Issues

Ensure three environment variables are properly configured:

- `LANGFUSE_PUBLIC_KEY`
- `LANGFUSE_SECRET_KEY`
- `LANGFUSE_BASE_URL`

These can be set as environment variables or supplied directly to the `Langfuse()` constructor. During initial setup (not in production environments), calling `langfuse.auth_check()` verifies that the connection works correctly.

## No Traces Appearing

Several factors may prevent traces from displaying:

- The `tracing_enabled` setting should be set to `True`
- `sample_rate` must not equal `0.0`
- Invoke `langfuse.shutdown()` or `langfuse.flush()` for short-lived processes to ensure queued data is properly exported
- Enable debug logging via `debug=True` on Python or `LANGFUSE_DEBUG="true"` on JavaScript/TypeScript to examine exporter behavior

## Incorrect Nesting or Missing Spans

- Self-hosted deployments require Langfuse platform version **3.63.0 or later** for OTel-based SDKs
- Context managers using `with langfuse.start_as_current_observation(...)` are recommended over manual spans
- When manually creating spans with `langfuse.start_observation()`, you must explicitly call `.end()`
- Asynchronous code should utilize Langfuse helpers to prevent context loss across await statements

## LangChain/OpenAI Integration Issues

- Langfuse wrappers (either via `from langfuse.openai import openai` or `LangfuseCallbackHandler`) must be initialized before making API calls
- Version compatibility should be verified across Langfuse, LangChain, and model SDKs

## Media Not Appearing

Audio and image payloads require `LangfuseMedia` objects. Debug logs reveal upload errors that occur on background threads.

## Missing Traces with @vercel/otel

Manual OpenTelemetry configuration using `NodeSDK` with registered `LangfuseSpanProcessor` is the recommended approach. The `@vercel/otel` helper lacks support for OpenTelemetry JS SDK v2, which Langfuse currently depends on. The TypeScript instrumentation documentation provides a complete implementation example.
