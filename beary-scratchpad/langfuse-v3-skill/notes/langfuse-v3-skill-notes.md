# Langfuse v3 Skill -- Merged Research Notes

## General Understanding

This document synthesizes research from four parallel investigations into Langfuse v3/v4 and Claude Code skill design. The goal is to inform the creation of a comprehensive Claude Code skill that helps developers instrument, debug, and optimize LLM applications using Langfuse. The research covers: (1) SDK architecture and migration, (2) prompt management, evaluation, and datasets, (3) framework integrations and pitfalls, and (4) skill authoring patterns.

---

## 1. Langfuse v3/v4 SDK Architecture and Migration

### Architecture Overhaul: OpenTelemetry-Native Foundation

Langfuse v3 (server) and Python SDK v3 represent a ground-up rewrite anchored on OpenTelemetry (OTEL) standards. The legacy proprietary tracing protocol is replaced with OTEL spans, context propagation, and W3C Trace Context IDs (32-char lowercase hex). Langfuse now automatically captures spans from any OTEL-instrumented library (database drivers, HTTP clients, framework instrumentation), which can increase ingestion volume and costs if not filtered [1][4].

The current stable Python SDK is **v4.0.4** (released 2026-03-30), requiring Python >= 3.10 and Pydantic v2 [7].

### Python SDK Breaking Changes: v2 -> v3 -> v4 Progression

**v2 to v3 (June 2025 GA):**
- `langfuse.trace()`, `trace.span()`, `langfuse.generation()` direct methods removed. Replaced by `langfuse.start_as_current_observation(as_type="span"|"generation", name=...)` with explicit `.end()` or context managers [1].
- Imports restructured: `from langfuse.decorators import langfuse_context, observe` becomes `from langfuse import observe, get_client` [1].
- Custom observation IDs removed; W3C Trace Context format enforced. Use `Langfuse.create_trace_id(seed=external_id)` for deterministic IDs [1].
- Trace input/output no longer auto-derived from root observation; must be set explicitly via `span.update_trace(input=..., output=...)` [1].
- Constructor renames: `enabled` -> `tracing_enabled`, `threads` -> `media_upload_thread_count` [1].
- LlamaIndex: `LlamaIndexCallbackHandler` removed entirely. Must use OpenInference OTEL instrumentation [1].
- Dataset API: `.link()` removed, replaced by `.run()` context manager [1].

**v3 to v4 (March 2026):**
- Smart span filtering: SDK no longer exports all OTEL spans. Default filter keeps only Langfuse SDK spans, `gen_ai.*` attributed spans, and known LLM framework spans. Override with `should_export_span` callback [2].
- `update_current_trace()` decomposed into `propagate_attributes()`, `set_current_trace_io()` (deprecated), and `set_current_trace_as_public()` [2].
- `start_span()` / `start_generation()` consolidated into `start_observation(as_type=...)` [2].
- Dataset: `item.run()` removed, replaced by `dataset.run_experiment(name=..., task=...)` [2].
- `metadata` restricted to `dict[str, str]` with 200-char value limit (was `Any`) [2].
- Pydantic v2 required; v1 no longer supported [2].

### Current Tracing Patterns (v4)

**`@observe` decorator** -- the primary instrumentation pattern. Outermost decorated function creates a trace; nested decorated functions become spans. Supports async natively via `contextvars` [3]:

```python
from langfuse import observe, get_client

@observe()
def process_request(query: str):
    return call_llm(query)

@observe(name="llm-call", as_type="generation")
async def call_llm(prompt: str):
    return "response"
```

Disable IO capture: `@observe(capture_input=False, capture_output=False)` or env `LANGFUSE_OBSERVE_DECORATOR_IO_CAPTURE_ENABLED` [3].

**Context manager (manual tracing):**
```python
langfuse = get_client()
with langfuse.start_as_current_observation(
    as_type="span", name="user-request", input={"query": "..."}
) as root:
    with langfuse.start_as_current_observation(
        as_type="generation", name="llm-call", model="gpt-4o"
    ) as gen:
        gen.update(output="...", usage_details={"input_tokens": 5, "output_tokens": 50})
```

**Attribute propagation** -- replaces direct trace attribute setting:
```python
from langfuse import propagate_attributes

with propagate_attributes(
    user_id="user_123", session_id="sess_abc",
    metadata={"experiment": "v1"}, version="1.0"
):
    result = process_request("hello")
```

Supports distributed tracing via `as_baggage=True` for cross-service HTTP header propagation [3].

**ThreadPoolExecutor caveat**: `@observe` does not work with `ThreadPoolExecutor`/`ProcessPoolExecutor` because `contextvars` are not copied to new threads [3].

### Flush and Shutdown

```python
langfuse = get_client()
langfuse.flush()     # send buffered observations
langfuse.shutdown()  # graceful shutdown + flush
```

SDK auto-registers `atexit` hook, but manual `flush()` is required for serverless/short-lived processes [3].

### Self-Hosting v3: Infrastructure Changes

v3 self-hosting is a major architectural shift from v2 [5][6]:

| Component | v2 | v3 |
|-----------|----|----|
| Primary DB | Postgres only | Postgres (transactional) + ClickHouse (analytical) |
| Cache/Queue | None | Redis/Valkey (required) |
| Blob Storage | None | S3-compatible (MinIO default) |
| Containers | Single web container | Web + Worker (async background processing) |
| Min Resources | Modest | 4 cores, 16 GiB RAM, 100 GiB storage |

Migration gotcha: Upgrade path validated between v2.92.0 and v3.29.0 specifically [5].

### Advanced Production Features

- **Sampling**: `sample_rate` (0.0-1.0) or `LANGFUSE_SAMPLE_RATE` [8].
- **Data masking**: Pass mask function at initialization for PII scrubbing [8].
- **Multi-project routing**: Separate client instances with distinct credentials [8].
- **Isolated TracerProvider**: Prevents span leaking to Datadog/Jaeger [8].
- **TTFT tracking**: Set `completion_start_time` on generation observations [8].

### Pricing Model (Cloud)

Free: 50K obs/month. Core: $29/mo. Pro: $199/mo. Enterprise: $2,499/mo. Overage: $8/100K units. Self-hosted: free (MIT) [9]. Tiered model pricing for context-dependent costs [10].

---

## 2. Prompt Management, Evaluation, and Datasets

### Prompt Management

Two prompt types (text, chat), double-brace `{{variable}}` syntax [11]. `get_prompt()` retrieves by name, optional version/label. Default returns `production` label. `compile()` substitutes variables [12]:

```python
prompt = langfuse.get_prompt("movie-critic")
compiled = prompt.compile(criticlevel="expert", movie="Dune 2")
```

Every edit creates new version. `latest` label auto-tracks newest. `production` designates default. Custom labels supported. Promotion/rollback via label reassignment [12].

Prompts cached client-side (zero latency). Throws only when no cache AND network fails. `is_fallback` property detects fallback content [13].

`get_langchain_prompt()` converts `{{}}` to LangChain `{}` format. Prompts link to traces for A/B comparison [11].

### Evaluation and Scoring

Four approaches: LLM-as-a-Judge, UI Scores, Annotation Queues, SDK Scores [14]. Offline evaluation tests before deployment; online evaluation scores live traces. Closed loop: online issues feed back into datasets [14].

Three score data types: Numeric, Categorical, Boolean. Attach to traces, observations, sessions, or dataset runs [15]:

```python
langfuse.create_score(name="accuracy", value=0.95, trace_id="trace-abc", data_type="NUMERIC")
```

LLM-as-a-Judge evaluators run on Observations (recommended), Traces, or Experiments. Template variables `{{input}}`, `{{output}}`, `{{ground_truth}}` mapped via JSONPath. Managed evaluators for hallucination, relevance, toxicity, helpfulness [16][17].

### Datasets and Experiments

Items have `input`, optional `expected_output`, optional `metadata`. JSON Schema validation supported [18].

`run_experiment()` handles concurrent execution, auto trace creation, error isolation [19]:

```python
def my_task(*, item, **kwargs):
    return call_llm(item["input"]["question"])

def accuracy_eval(*, input, output, expected_output, **kwargs):
    return Evaluation(name="accuracy", value=1.0 if expected_output.lower() in output.lower() else 0.0)

result = dataset.run_experiment(name="v2", task=my_task, evaluators=[accuracy_eval])
```

CI/CD: `assert avg_accuracy >= 0.8` on run_evaluations [19].

---

## 3. Integration Patterns: LangChain, LangGraph, OpenAI

### LangChain CallbackHandler

Singleton `Langfuse` client, lightweight handler [20]:

```python
from langfuse.langchain import CallbackHandler
langfuse_handler = CallbackHandler()
chain.invoke({"input": "..."}, config={"callbacks": [langfuse_handler]})
```

Session/user tracking via metadata keys or `propagate_attributes()` [20].

### LangGraph Agent Tracing

Same handler pattern. Pass `config={"callbacks": [langfuse_handler]}` to graph `.invoke()`. Captures node, LLM, tool call, routing spans [21][22][23]. Server: bind at compile time. Multi-agent: shared `trace_id` [22]. Graph visualization inferred from observation nesting (beta) [24][25].

### OpenAI SDK Drop-in Wrapper

Replace `import openai` with `from langfuse.openai import openai`. Captures prompts, completions, tokens, costs, latencies, tool calls, streaming with TTFT [26][27]. Group calls with `@observe()` decorator [28][26].

### The `@observe()` Decorator as Universal Glue

Works across all integration paths. CallbackHandler inside decorated function inherits trace context. Recommended pattern for mixing providers [28][20].

### Common Pitfalls

1. **Flush timing / missing traces**: MUST call `flush()`/`shutdown()` in short-lived processes [29][30].
2. **OTEL context collisions**: Other OTEL tools create unintended parent-child relationships [30][31].
3. **Streaming premature break**: Early break = incomplete observation [27].
4. **Streaming empty choices**: Guard with `if chunk.choices:` when `include_usage=True` [26].
5. **Credential ordering**: Env vars before import [29].
6. **Azure model names**: Must explicitly set `model` for cost parsing [20].
7. **Manual spans need `.end()`**: Prefer context managers [30].
8. **ThreadPoolExecutor**: `@observe` breaks -- contextvars not copied [3].
9. **Assistants API**: Not supported by wrapper [26].

Debug: `Langfuse(debug=True)` reveals dropped spans. Sampling: `sample_rate=0.1`. Disable: `tracing_enabled=False` [30][31].

---

## 4. Claude Code Skill Design Patterns

### SKILL.md Structure

Directory with `SKILL.md`: YAML frontmatter (metadata) + Markdown (instructions) [32][33].

Key fields: `name` (lowercase, hyphens, max 64 chars, gerund form), `description` (max 1024 chars, Claude uses for LLM-based routing -- no algorithmic routing) [34][35]. Optional: `disable-model-invocation`, `user-invocable`, `allowed-tools`, `context: fork` [35]. Variables: `$ARGUMENTS`, `${CLAUDE_SKILL_DIR}`. Dynamic context: `` !`command` `` [32].

### Directory Layout and Progressive Disclosure

```
my-skill/
  SKILL.md           # Core instructions (<500 lines)
  references/        # On-demand docs
  scripts/           # Executable Python/Bash
  assets/            # Templates, static files
  examples/          # Sample outputs
```

Three disclosure levels [34][35]:
1. Metadata -- always in context (~100 words, 15K-char budget)
2. SKILL.md body -- loaded when triggered (<500 lines)
3. Bundled resources -- loaded on-demand

### Effective Design Patterns

Six patterns: Script Automation, Read-Process-Write, Search-Analyze-Report, Command Chain Execution, Wizard-Style Workflows, Iterative Refinement [35].

Anti-patterns: too many library options, time-sensitive info, vague descriptions, deeply nested references, unexplained magic numbers [34].

### Langfuse Debugging Workflows

Filter traces by latency, drill into spans/generations [37]. Two-tier cost: ingested (priority) vs. inferred (tokenizer-based). Context-dependent pricing tiers [38]. LLM-as-a-Judge execution tracing captures judge prompt/response/tokens [39]. Instrumentation decisions yield 3-5x cost variation; architecture choices give 50-90% reductions [40].

---

## Deeper Dive

### DD1: Python SDK v4 Primitives and Complex Agent Workflow Composition

#### Langfuse Client Architecture

The `Langfuse` client initializes through a singleton pattern managed by `LangfuseResourceManager`. Multiple calls with the same `public_key` return the same instance via double-checked locking. If credentials are missing, the client silently falls back to a `NoOpTracer` -- code never crashes due to missing configuration [45][46].

Key initialization parameters:
```python
client = Langfuse(
    public_key="pk-lf-...",
    secret_key="sk-lf-...",
    base_url="https://cloud.langfuse.com",
    environment="production",
    timeout=20,
    flush_at=512,        # events before batch export
    flush_interval=5.0   # seconds between exports
)
```

Environment variables override: `LANGFUSE_FLUSH_AT`, `LANGFUSE_FLUSH_INTERVAL` [45].

#### Three Distinct Export Paths

1. **OTel Span Export**: `Observation.end()` -> `LangfuseSpanProcessor.on_end()` -> `OTLPSpanExporter` -> `POST /api/public/otel/v1/traces`. Batched by `BatchSpanProcessor` per `flush_at`/`flush_interval` [45].
2. **Score Ingestion**: Background thread, queue capacity 100K events, `POST /api/public/ingestion` [45].
3. **Media Upload**: Three-step (presign, PUT, PATCH), configurable `media_upload_thread_count` [45].

#### `flush()` vs `shutdown()` Semantics

`flush()` blocks calling thread until all pending spans, scores, and media uploads complete. `shutdown()` performs a final flush, then stops all background threads -- client should not be used after. SDK registers `atexit` handler for automatic cleanup, but serverless MUST call `flush()` explicitly [45][46].

**Serverless pattern**:
```python
client = Langfuse(
    flush_at=10,          # aggressive in serverless
    flush_interval=1.0,
    timeout=3
)

def lambda_handler(event, context):
    try:
        with client.start_as_current_observation(name="lambda") as obs:
            result = process(event)
            return result
    finally:
        client.flush()
        # Do NOT call shutdown() in serverless -- reused containers need connections alive
```

#### `@observe` Decorator Internals

The decorator wraps functions in OTel spans via `start_as_current_observation()`. It detects async functions via `asyncio.iscoroutinefunction()` and applies `await`. Root decorated function creates a new trace; nested decorated functions become child spans via `contextvars` propagation [47].

`as_type` parameter options: `"span"` (default), `"generation"`, `"embedding"`, `"event"`, `"agent"`, `"tool"`. Invalid types log a warning and default to `"span"` [47].

**Generator handling**: The decorator captures `contextvars.Context` before returning generator and replays via `context.run()` on each `__next__()`. Span only ends when generator is fully consumed or exception occurs. Custom output transform: `@observe(transform_to_string=lambda items: " ".join(items))` [47].

**StreamingResponse detection**: Decorator detects Starlette `StreamingResponse` objects and wraps their internal generator to keep observations alive during streaming [47].

**Exception handling**: Captures exception, sets `level="ERROR"` and `status_message`, ends observation, re-raises unchanged. Each nesting level records error independently [47].

**Input capture exclusions**: `self`/`cls` auto-excluded from methods. Reserved kwargs (`langfuse_trace_id`, `langfuse_parent_observation_id`, `langfuse_public_key`) stripped before capture. Generators as input represented as `"<generator>"` [47].

#### Context Manager Composition

Manual spans compose cleanly with `@observe`:
```python
@observe
def outer():
    client = get_client()
    with client.start_as_current_observation(name="manual", as_type="span") as span:
        span.update(output="result")
```

The manual span becomes a child of the `@observe`-created span through OTel context. `end_on_exit=False` available for deferred ending [45][47].

#### Threading with OTel Instrumentation

To propagate context across `ThreadPoolExecutor`:
```python
from opentelemetry.instrumentation.threading import ThreadingInstrumentor
ThreadingInstrumentor().instrument()
```

This patches threading to copy `contextvars`, enabling `@observe` to work across thread boundaries [46].

---

### DD2: Cost Tracking, Token Counting, and Latency Measurement

#### Cost Calculation Priority

Langfuse uses a priority-based approach [48][49]:
1. Check if USD cost is included in the observation (`cost_details`) -- highest priority
2. Check if usage is included (`usage_details`) -- use model pricing to calculate cost
3. If neither, use model's tokenizer to count tokens, then apply pricing

#### `usage_details` Fields

Flexible, provider-specific keys [48]:
- Standard: `input`, `output`, `total`
- Advanced: `cached_tokens`, `audio_tokens`, `image_tokens`, `cache_read_input_tokens`
- Custom: any arbitrary string keys

UI groups fields containing "input" or "output". If no `total` provided, Langfuse sums all usage type units [48].

`cost_details` mirrors the same keys in USD:
```python
generation.update(
    usage_details={"input": 500, "output": 100, "cache_read_input_tokens": 200},
    cost_details={"input": 0.005, "output": 0.002, "cache_read_input_tokens": 0.001}
)
```

#### Model Definition System

Three PostgreSQL tables: `Model` (match_pattern regex, tokenizer), `PricingTier` (is_default, priority, conditions), `Price` (per-token costs). Built-in models (`projectId=NULL`) are maintained by Langfuse; custom models (`projectId=UUID`) take precedence [50].

Model matching: project-scoped models checked first, then globals. Regex uses PostgreSQL `~` operator [50].

#### Pricing Tiers

Tiers evaluated in ascending `priority` order. A tier matches when ALL conditions satisfied against `usageDetails`. Exactly one `is_default` tier per model (fallback). Conditions use operators: `gt`, `gte`, `lt`, `lte`, `eq`, `neq` against `usageDetailPattern` [48][50].

Example: Claude Sonnet 4.5 "Large Context" tier applies when `input > 200000` [48].

Default model prices sourced from `worker/src/constants/default-model-prices.json`, seeded at worker startup. Updates use transactions, clear Redis cache [50].

#### TTFT and Latency Measurement

Set `completion_start_time` on generation observations for TTFT:
```python
with langfuse.start_as_current_observation(as_type="generation", name="llm-call") as gen:
    # ... wait for first token ...
    gen.update(completion_start_time=datetime.datetime.now(), output="response")
```

Aggregated latency and cost shown at every span level in trace timeline view, making it easy to spot outliers. Color-coded display for quick visual identification [46][51].

#### Metrics API and Dashboards

Three metric categories: Quality (scores), Cost/Latency (per-user/session/model/prompt version), Volume (traces/tokens). Filterable by trace name, user ID, tags, release/version. Customizable dashboards plus programmatic Metrics API. Export to PostHog/Mixpanel supported [52].

#### Edge Cases

- Only `generation` and `embedding` types support cost/usage tracking [48].
- OpenAI schema auto-mapped: `prompt_tokens` -> `input`, `completion_tokens` -> `output` [48].
- Reasoning models (o1): tokenizer-based inference not supported; must ingest counts [48].
- Model definition changes apply only to new traces [48].

---

### DD3: Langfuse Claude Code Skill -- Templates, Debugging Commands, Setup Guides

#### Quickstart Setup Pattern

Installation: `pip install langfuse`. Three env vars required: `LANGFUSE_SECRET_KEY`, `LANGFUSE_PUBLIC_KEY`, `LANGFUSE_BASE_URL` [53].

Minimal tracing:
```python
from langfuse import get_client
langfuse = get_client()
with langfuse.start_as_current_observation(as_type="span", name="process-request") as span:
    span.update(output="Processing complete")
langfuse.flush()
```

Framework-specific: LangChain uses `CallbackHandler`, OpenAI uses drop-in import, both compose with `@observe` [53].

Critical gotcha: start SDK before initializing traced logic. Short-lived apps must call `flush()` [53].

#### Skill Creator Meta-Patterns

The official `skill-creator` SKILL.md defines a rigorous iterative development workflow [54]:

1. **Capture Intent**: What should the skill do? When should it trigger? Expected output format?
2. **Interview & Research**: Edge cases, dependencies, success criteria
3. **Write SKILL.md**: Frontmatter + progressive disclosure
4. **Create Test Cases**: 2-3 realistic prompts in `evals/evals.json`
5. **Run & Evaluate**: With-skill vs baseline comparison, grading, benchmark aggregation
6. **Iterate**: Feedback loop until user satisfied

**Description optimization is critical**: The description is the PRIMARY triggering mechanism. Should be "pushy" -- e.g., "Make sure to use this skill whenever the user mentions X, Y, or Z, even if they don't explicitly ask for it" [54].

**Progressive disclosure hierarchy** [54]:
1. Metadata (~100 words) -- always loaded
2. SKILL.md body (<500 lines) -- loaded on trigger
3. Bundled resources -- loaded on demand

**Evaluation-driven development**: Create `evals/evals.json` with realistic, concrete, edge-case-focused test prompts. Run with-skill and baseline subagents, grade assertions, aggregate benchmarks with variance analysis [54].

**Key writing principles** [54]:
- Use imperative form
- Explain the *why* behind requirements, not just MUST/ALWAYS
- Remove what isn't pulling weight
- 3+ concrete examples dramatically improve consistency
- Bundle repeated scripts into `scripts/`
- Keep references one level deep from SKILL.md

#### Proposed Langfuse Skill Structure

Based on all research, the skill should follow this layout:
```
langfuse-tracing/
  SKILL.md                    # Core instructions (<500 lines)
  references/
    sdk-patterns.md           # @observe, context managers, flush
    integrations.md           # LangChain, LangGraph, OpenAI
    cost-tracking.md          # Token counting, pricing, optimization
    evaluation.md             # Scores, experiments, LLM-as-Judge
    troubleshooting.md        # Common pitfalls, debug mode
  scripts/
    check_langfuse_setup.py   # Verify env vars, connectivity
    trace_cost_report.py      # Query cost data via API
  assets/
    quickstart-template.py    # Minimal setup boilerplate
    fastapi-template.py       # FastAPI + Langfuse integration
```

The SKILL.md description should front-load: "Instruments LLM applications with Langfuse tracing, debugs missing/slow traces, analyzes token costs, manages prompt versions, and runs evaluations. Use when adding observability, investigating production issues, tracking costs, or evaluating output quality."
