---
name: langfuse-tracing
description: >
  Instruments LLM applications with Langfuse v4 tracing, debugs missing or slow
  traces, analyzes token costs, manages prompt versions, and runs evaluations.
  Use when adding observability to LLM pipelines, investigating production issues,
  tracking costs, evaluating output quality, or setting up Langfuse for the first
  time. Triggers on mentions of Langfuse, LLM tracing, observability, token costs,
  prompt management, or evaluation experiments. Also use when the user asks about
  LLM monitoring, trace debugging, or cost optimization.
---

# Langfuse Tracing Skill

Langfuse Python SDK v4 (OTEL-native). This skill covers setup, instrumentation,
integrations, prompt management, evaluation, cost tracking, and debugging.

## Decision Tree

Follow this routing logic based on the user's intent:

### 1. First-Time Setup

If Langfuse is not installed or configured:

1. `pip install langfuse`
2. Set environment variables:
   ```bash
   export LANGFUSE_PUBLIC_KEY="pk-lf-..."
   export LANGFUSE_SECRET_KEY="sk-lf-..."
   export LANGFUSE_BASE_URL="https://cloud.langfuse.com"  # or self-hosted URL
   ```
3. Verify connectivity:
   ```python
   from langfuse import Langfuse
   langfuse = Langfuse()
   langfuse.auth_check()  # dev only, not production
   ```
4. Run `scripts/check_langfuse_setup.py` for full diagnostics.

### 2. Instrumentation

Determine the user's framework, then apply the right pattern:

**Pure Python** — use `@observe` decorator:
```python
from langfuse import observe, get_client

@observe()
def my_pipeline(query: str) -> str:
    return call_llm(query)

@observe(as_type="generation")
def call_llm(prompt: str) -> str:
    # LLM call here
    return response

# CRITICAL: flush before exit in scripts/serverless
langfuse = get_client()
langfuse.flush()
```

**LangChain / LangGraph** — use CallbackHandler:
```python
from langfuse import Langfuse
from langfuse.langchain import CallbackHandler

Langfuse()  # init singleton
handler = CallbackHandler()

# Pass on every invoke
chain.invoke({"input": "..."}, config={"callbacks": [handler]})

# LangGraph — same pattern
graph.invoke({"messages": [...]}, config={"callbacks": [handler]})
```

**OpenAI SDK** — drop-in import replacement:
```python
from langfuse.openai import openai  # replaces `import openai`

# Everything is traced automatically
response = openai.chat.completions.create(
    model="gpt-4o",
    messages=[{"role": "user", "content": "Hello"}]
)
```

**Mixed providers** — `@observe` is the universal glue:
```python
@observe()
def mixed_pipeline(query: str):
    # OpenAI wrapper traces automatically
    embedding = openai.embeddings.create(...)

    # LangChain traces via callback
    result = chain.invoke({"query": query}, config={"callbacks": [handler]})

    return result
```

For detailed patterns, read `references/sdk-patterns.md`.
For integration specifics, read `references/integrations.md`.

### 3. Always Include: Flush

**This is the #1 cause of missing traces.** Always flush before exit:

- **Scripts/notebooks**: `langfuse.flush()` at the end
- **FastAPI**: middleware or shutdown event
- **Serverless**: `langfuse.flush()` in finally block
- **Long-running**: SDK auto-flushes via atexit, but call `shutdown()` on graceful stop

```python
# FastAPI pattern
from contextlib import asynccontextmanager
from langfuse import get_client

@asynccontextmanager
async def lifespan(app):
    yield
    get_client().shutdown()

app = FastAPI(lifespan=lifespan)
```

### 4. Debugging Missing or Broken Traces

If traces don't appear, read `references/troubleshooting.md`. Quick checklist:

1. Enable debug: `Langfuse(debug=True)` or `LANGFUSE_DEBUG=true`
2. Check credentials are set BEFORE importing Langfuse
3. Check `tracing_enabled` is not False and `sample_rate` is not 0.0
4. Check `flush()` / `shutdown()` is called (scripts, serverless)
5. Check for OTEL context collisions (Sentry, Datadog, Pydantic Logfire)
6. For manual spans: verify `.end()` is called (prefer context managers)
7. Self-hosted: requires Langfuse platform >= 3.63.0 for OTEL SDKs

### 5. Cost Analysis

If the user asks about costs or token usage, read `references/cost-tracking.md`.

Key patterns:
```python
# Explicit cost/usage on generations
with langfuse.start_as_current_observation(
    as_type="generation", model="gpt-4o"
) as gen:
    response = call_llm(prompt)
    gen.update(
        output=response,
        usage_details={"input_tokens": 100, "output_tokens": 50},
        cost_details={"input": 0.0025, "output": 0.005}  # USD
    )
```

### 6. Prompt Management

If the user asks about prompt versioning, read `references/prompts-and-evals.md`.

```python
# Fetch production prompt
prompt = langfuse.get_prompt("my-prompt")
compiled = prompt.compile(variable="value")

# Fetch specific version or label
prompt = langfuse.get_prompt("my-prompt", version=3)
prompt = langfuse.get_prompt("my-prompt", label="staging")
```

### 7. Evaluation & Experiments

If the user asks about evaluating LLM outputs, read `references/prompts-and-evals.md`.

```python
# Score a trace
langfuse.create_score(name="accuracy", value=0.95, trace_id="trace-abc")

# Run an experiment
result = dataset.run_experiment(
    name="v2-test",
    task=my_task_fn,
    evaluators=[my_eval_fn],
)
assert result.run_evaluations[0].value >= 0.8
```

## Important Version Notes

- Python SDK v4 requires Python >= 3.10 and Pydantic v2
- `@observe` does NOT work with `ThreadPoolExecutor` (contextvars not copied)
- `metadata` is `dict[str, str]` with 200-char value limit (not `Any`)
- Streaming: never break early from stream iterator or observation will be incomplete
- v2 patterns (`langfuse.trace()`, `langfuse.generation()`) are removed in v3+
