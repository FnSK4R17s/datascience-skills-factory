# Langfuse v3/v4 Observability Skill for Claude Code

**Author:** Background Research Agent (BEARY)
**Date:** 2026-03-30

---

## Abstract

This whitepaper provides the technical foundation for building a Claude Code skill that helps developers instrument, debug, and optimize LLM applications using Langfuse. It covers the OpenTelemetry-native architecture introduced in Langfuse v3, the current Python SDK v4 primitives (`@observe`, context managers, flush patterns), integration patterns for LangChain, LangGraph, and OpenAI, prompt management and evaluation workflows, cost and latency tracking, common pitfalls, and a concrete skill design proposal. The target audience is experienced Python developers building production LLM applications who need a reliable, code-dense reference for Langfuse instrumentation.

---

## 1. Introduction: Why a Langfuse Skill for Claude Code?

LLM observability has become a non-negotiable requirement for production applications. Without structured tracing, developers face silent failures, unexplained cost spikes, and no way to compare prompt iterations against baseline performance. Langfuse is the leading open-source observability platform for LLM applications, offering tracing, prompt management, evaluation, and cost tracking under an MIT license [37][42].

The problem is not a lack of documentation -- Langfuse has extensive docs. The problem is that instrumenting an LLM application correctly requires synthesizing knowledge from at least six different documentation pages (SDK setup, decorator patterns, framework integration, flush timing, cost tracking, evaluation), plus awareness of a dozen pitfalls that are documented only in FAQs and GitHub discussions. A developer asking Claude Code to "add Langfuse tracing to my FastAPI app" today gets generic boilerplate that misses flush calls, ignores streaming edge cases, and uses deprecated v2 APIs.

A Claude Code skill solves this by encoding the full decision tree -- from initial setup through production debugging -- in a format that Claude can apply contextually. The skill triggers when a developer mentions Langfuse, tracing, observability, or cost tracking, and provides framework-specific code templates, debugging workflows, and optimization patterns tuned to the current SDK version (v4.0.4 as of March 2026) [7].

---

## 2. Langfuse v3/v4 SDK Architecture

### 2.1 OpenTelemetry Foundation

Langfuse v3 replaced its proprietary tracing protocol with OpenTelemetry (OTEL) standards. All observations are OTEL spans with W3C Trace Context IDs (32-char lowercase hex). This means Langfuse automatically captures spans from any OTEL-instrumented library in the application stack -- database drivers, HTTP clients, framework middleware -- which can increase ingestion volume if not filtered [1][4].

The v4 SDK (released March 2026) introduced smart span filtering: the `LangfuseSpanProcessor` exports only Langfuse SDK spans, `gen_ai.*` attributed spans, and known LLM framework spans (OpenInference, LangSmith, Haystack, LiteLLM). Developers can override this with a `should_export_span` callback [2].

The client initializes as a singleton per `public_key`, managed by `LangfuseResourceManager` with double-checked locking. Multiple `Langfuse()` calls with the same key return the same instance. Missing credentials produce a `NoOpTracer` rather than raising exceptions [45].

### 2.2 The `@observe` Decorator

The `@observe` decorator is the primary instrumentation pattern. It wraps functions in OTEL spans via `start_as_current_observation()`, using `contextvars` for automatic parent-child nesting [3][47]:

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

The outermost decorated function creates a trace; inner decorated functions become child spans. The `as_type` parameter accepts `"span"` (default), `"generation"`, `"embedding"`, `"event"`, `"agent"`, and `"tool"`. Invalid types log a warning and default to `"span"` [47].

**Async support** is native: the decorator detects async functions via `asyncio.iscoroutinefunction()`. Generator functions get special handling -- the decorator captures `contextvars.Context` and replays it on each `__next__()` call via `context.run()`, keeping the span alive during lazy iteration [47].

**Input capture exclusions**: `self`/`cls` are auto-excluded from methods. Reserved kwargs (`langfuse_trace_id`, `langfuse_parent_observation_id`, `langfuse_public_key`) are stripped before capture. Generators passed as input are represented as `"<generator>"`. IO capture can be disabled per-function (`capture_input=False`) or globally via `LANGFUSE_OBSERVE_DECORATOR_IO_CAPTURE_ENABLED=false` [3][47].

**Exception handling**: The decorator captures exceptions at each nesting level independently, sets `level="ERROR"` and `status_message`, ends the observation, and re-raises the exception unchanged [47].

### 2.3 Context Managers and Manual Tracing

For cases where decorators are impractical, context managers provide equivalent functionality:

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

Context managers auto-call `.end()` unless `end_on_exit=False` is set. They compose cleanly with `@observe` -- a manual span inside a decorated function automatically becomes a child through OTEL context [45][47].

### 2.4 Attribute Propagation

The v4 SDK decomposed the former `update_current_trace()` into `propagate_attributes()` for trace-level metadata:

```python
from langfuse import propagate_attributes

with propagate_attributes(
    user_id="user_123", session_id="sess_abc",
    metadata={"experiment": "v1"}, version="1.0",
    tags=["production"]
):
    result = process_request("hello")
```

For cross-service distributed tracing, `as_baggage=True` propagates attributes via W3C Baggage HTTP headers [3]. Note that `metadata` is now restricted to `dict[str, str]` with 200-char value limits in v4 [2].

### 2.5 Flush and Shutdown

The SDK uses three background export paths [45]:
1. **OTEL spans**: `BatchSpanProcessor` -> `POST /api/public/otel/v1/traces`
2. **Scores**: Background consumer thread -> `POST /api/public/ingestion`
3. **Media**: Presigned upload (GET URL, PUT bytes, PATCH confirmation)

`flush()` blocks the calling thread until all three queues drain. `shutdown()` flushes then stops all background threads. The SDK registers an `atexit` hook, but serverless environments MUST call `flush()` explicitly -- background threads may not complete before the process exits [3][45].

**Serverless best practice**: reduce `flush_at` to 10 and `flush_interval` to 1.0 second. Do NOT call `shutdown()` in serverless -- reused execution environments need connections alive [45].

---

## 3. Integration Patterns

### 3.1 LangChain Callbacks

The v3/v4 SDK uses a singleton pattern. Initialize once, create lightweight handlers:

```python
from langfuse import Langfuse, get_client
from langfuse.langchain import CallbackHandler

Langfuse(public_key="pk-lf-...", secret_key="sk-lf-...")
langfuse_handler = CallbackHandler()
chain.invoke({"input": "..."}, config={"callbacks": [langfuse_handler]})
```

Session and user tracking via metadata keys (`langfuse_user_id`, `langfuse_session_id`, `langfuse_tags`) in the `config["metadata"]` dict, or via `propagate_attributes()` context manager [20].

Custom trace naming uses `langfuse.start_as_current_observation()` wrapping the invocation. A `CallbackHandler()` created inside this context automatically inherits the parent span [20].

### 3.2 LangGraph Agent Tracing

LangGraph uses the same `CallbackHandler` -- pass `config={"callbacks": [langfuse_handler]}` to the compiled graph's `.invoke()` or `.stream()`. Langfuse automatically captures node execution, LLM generation, tool call, and conditional-edge routing spans [21][22][23].

For persistent server deployments, bind at compile time: `graph_builder.compile().with_config({"callbacks": [langfuse_handler]})` [22].

Multi-agent architectures use a shared trace ID: `trace_id = Langfuse.create_trace_id()` with each sub-agent wrapped in `langfuse.start_as_current_observation()` using the same trace context [22].

Langfuse infers visual agent graphs from observation timing and nesting (beta feature). The graph view renders automatically when a trace contains agentic observation types [24][25].

### 3.3 OpenAI Drop-in Wrapper

A single import change enables full tracing:

```python
from langfuse.openai import openai  # replaces: import openai

completion = openai.chat.completions.create(
    model="gpt-4o",
    messages=[{"role": "user", "content": "Hello"}]
)
```

The wrapper captures prompts, completions, token usage, USD costs, latencies, function/tool calls, structured outputs, and API errors. Streaming includes TTFT measurement on the first chunk [26][27].

To group multiple OpenAI calls into one trace, wrap with `@observe()`:

```python
@observe()
def generate_poem(country):
    capital = openai.chat.completions.create(model="gpt-4o", messages=[...])
    poem = openai.chat.completions.create(model="gpt-4o", messages=[...])
    return poem
```

Both generations nest under the decorated function automatically [26][28].

### 3.4 Mixing Providers

The `@observe()` decorator is the universal glue across all integration paths. A `CallbackHandler()` created inside a decorated function inherits the decorator's trace context. This is the recommended pattern for applications that combine OpenAI, Anthropic, LangChain, and custom logic in the same request [20][28].

---

## 4. Prompt Management

### 4.1 Versioning and Labels

Langfuse supports two prompt types (fixed at creation): text prompts (return a string) and chat prompts (return `{role, content}` message arrays). Double-brace `{{variable}}` template syntax [11].

Every edit creates a new version. The `latest` label auto-tracks the newest version. The `production` label designates the default served by `get_prompt()`. Custom labels (staging, canary, tenant-specific) enable multi-environment promotion [12]:

```python
prompt = langfuse.get_prompt("movie-critic")              # production
prompt = langfuse.get_prompt("movie-critic", version=3)    # specific version
prompt = langfuse.get_prompt("movie-critic", label="staging")  # by label
```

### 4.2 `get_prompt()` and `compile()`

`compile()` performs variable substitution:

```python
compiled = prompt.compile(criticlevel="expert", movie="Dune 2")
# => "As an expert movie critic, do you like Dune 2?"
```

For LangChain, `get_langchain_prompt()` converts `{{}}` syntax to LangChain's `{}` format [11].

### 4.3 Caching and Availability

Prompts are cached client-side, adding zero latency. `get_prompt()` throws only when no local cache (fresh or stale) exists AND the network request fails. Two mitigation strategies: pre-fetch on startup with fail-fast, or provide a fallback prompt. The `is_fallback` property detects when fallback content is being served [13].

### 4.4 Linking Prompts to Traces

Prompts link to traces, enabling A/B performance comparison across versions. This closes the loop between prompt iteration and production quality measurement [11].

---

## 5. Evaluation and Experiments

### 5.1 Scores

Three data types: Numeric (float), Categorical (string), Boolean (0 or 1). Scores attach to traces, observations, sessions, or dataset runs [15]:

```python
langfuse.create_score(
    name="accuracy", value=0.95, trace_id="trace-abc",
    observation_id="obs-xyz", data_type="NUMERIC",
    comment="High factual accuracy"
)
```

Context-based convenience methods: `span.score()`, `span.score_trace()`, `langfuse.score_current_span()`, `langfuse.score_current_trace()`. Idempotency keys (`score_id`) prevent duplicates [15].

### 5.2 LLM-as-a-Judge

Evaluators run on three targets: Observations (recommended -- individual LLM calls, executes in seconds), Traces (complete workflows, takes minutes), or Experiments (controlled datasets with ground truth). Template variables `{{input}}`, `{{output}}`, `{{ground_truth}}` mapped via JSONPath [16].

Managed evaluators cover hallucination detection, context relevance, toxicity, helpfulness, and SQL semantic equivalence, developed in partnership with RAGAS [17]. Custom evaluators use user-defined prompt templates with the same variable system. Evaluation executions create their own traces filterable by `langfuse-llm-as-a-judge` environment [16].

LLM-as-a-Judge execution tracing (October 2025) captures the exact prompt sent to the judge model, its response, and token consumption, enabling debugging of evaluation failures [39].

### 5.3 Datasets and `run_experiment()`

Datasets contain items with `input`, optional `expected_output`, and optional `metadata`. JSON Schema validation supported [18]. The `run_experiment()` method handles concurrent execution, automatic trace creation, and error isolation [19]:

```python
def my_task(*, item, **kwargs):
    return call_llm(item["input"]["question"])

def accuracy_eval(*, input, output, expected_output, **kwargs):
    return Evaluation(
        name="accuracy",
        value=1.0 if expected_output.lower() in output.lower() else 0.0
    )

dataset = langfuse.get_dataset("qa-benchmark")
result = dataset.run_experiment(
    name="Model v2",
    task=my_task,
    evaluators=[accuracy_eval],
    run_evaluators=[aggregate_eval],  # run-level aggregate metrics
    max_concurrency=10
)
```

Item-level evaluators receive `input`, `output`, `expected_output`, `metadata`. Run-level evaluators receive `item_results` for aggregate metrics [19].

### 5.4 CI/CD Integration

Experiment results integrate with pytest for quality gates:

```python
avg_accuracy = next(e.value for e in result.run_evaluations if e.name == "avg_accuracy")
assert avg_accuracy >= 0.8, f"Below threshold: {avg_accuracy}"
```

The online/offline evaluation loop: offline experiments validate before deployment; online evaluation scores live production traces; issues discovered online feed back into datasets for future experiment coverage [14][19].

---

## 6. Cost and Performance

### 6.1 Token Tracking

Usage is tracked through `usage_details` with flexible keys: `input`, `output`, `total`, `cached_tokens`, `cache_read_input_tokens`, or any custom key. OpenAI schemas auto-map (`prompt_tokens` -> `input`, `completion_tokens` -> `output`). Only `generation` and `embedding` observation types support cost/usage tracking [48].

### 6.2 Cost Calculation

Langfuse uses a priority cascade [48][49]:
1. Ingested `cost_details` (USD) -- highest priority
2. Ingested `usage_details` + model pricing
3. Tokenizer-based inference + model pricing

Model definitions use POSIX regex `match_pattern` for matching. Project-scoped custom models override Langfuse-maintained defaults. Pricing tiers support context-dependent rates (e.g., Claude Sonnet 4.5 charges more above 200K input tokens), evaluated in ascending `priority` order [48][50].

```python
generation.update(
    usage_details={"input": 500, "output": 100, "cache_read_input_tokens": 200},
    cost_details={"input": 0.005, "output": 0.002, "cache_read_input_tokens": 0.001}
)
```

### 6.3 Pricing Tiers (Cloud)

Free: 50K observations/month. Core: $29/month. Pro: $199/month. Enterprise: $2,499/month. All paid tiers include unlimited users with $8/100K overage units. Self-hosted: free under MIT license [9].

### 6.4 Latency Measurement

TTFT is tracked by setting `completion_start_time` on generation observations [8][46]:

```python
with langfuse.start_as_current_observation(as_type="generation", name="llm-call") as gen:
    time.sleep(3)  # simulated wait
    gen.update(completion_start_time=datetime.datetime.now(), output="response")
```

Aggregated latency and cost are displayed at every span level in the trace timeline view, with color-coded highlighting for outlier identification [51].

### 6.5 Optimization Levers

Unit consumption varies 3-5x based on instrumentation decisions, not traffic volume. Logging every intermediate chain step costs significantly more than logging top-level traces only. Architecture choices in what to instrument yield 50-90% cost reductions [40]. Key levers:

- **Sampling**: `sample_rate=0.1` reduces volume by 90% [8].
- **Selective instrumentation**: Use `@observe` only on meaningful boundaries, not every helper function.
- **IO capture control**: Disable for large payloads to reduce ingestion size.
- **Model selection analysis**: Use cost breakdowns to identify where cheaper models suffice.

### 6.6 Metrics API

Three metric categories: Quality (scores), Cost/Latency, Volume. Filterable by trace name, user ID, tags, release version. Customizable dashboards plus programmatic Metrics API. Supports export to PostHog and Mixpanel [52].

---

## 7. Common Pitfalls

### 7.1 Missing Traces (Flush Timing)

The number-one reported issue. Langfuse sends data asynchronously in background batches. Short-lived processes -- serverless functions, scripts, notebooks -- MUST call `langfuse.flush()` or `langfuse.shutdown()` before exit, or data is silently lost. The `atexit` hook exists but is not reliable for all runtimes [29][30][45].

**Fix**: Always add `langfuse.flush()` in a `finally` block. In serverless, reduce `flush_at` and `flush_interval`. Never call `shutdown()` in serverless (breaks container reuse).

### 7.2 OTEL Context Collisions

Langfuse shares the global OTel context. Other OTel tools (Sentry, Datadog, Pydantic Logfire) can create unintended parent-child relationships or orphaned spans. A parent span from one `TracerProvider` may accidentally adopt children from another [30][31].

**Fix**: Use an isolated `TracerProvider`:
```python
from opentelemetry.sdk.trace import TracerProvider
langfuse = Langfuse(tracer_provider=TracerProvider())
```

Caveat: filtering spans may break parent-child relationships, creating orphaned observations [46].

### 7.3 ThreadPoolExecutor

`@observe` does not work with `ThreadPoolExecutor`/`ProcessPoolExecutor` because `contextvars` are not copied to new threads by default [3].

**Fix**: Use `opentelemetry.instrumentation.threading.ThreadingInstrumentor().instrument()` to patch threading [46].

### 7.4 Streaming Edge Cases

- **Premature break**: The wrapper finalizes the observation only when the stream iterator completes. Breaking early produces an incomplete observation with missing token counts [27].
- **Empty choices chunk**: When `stream_options={"include_usage": True}`, OpenAI sends a final chunk with empty `choices`. Always guard: `if chunk.choices:` [26].

### 7.5 Credential Ordering

Environment variables must be set BEFORE importing the Langfuse SDK. In Jupyter, restart the kernel after changing credentials [29].

### 7.6 Azure OpenAI Model Names

Must explicitly set `model="gpt-4o"` on `AzureChatOpenAI` even though the deployment name differs, otherwise Langfuse cannot parse token costs [20].

### 7.7 Manual Spans Without `.end()`

Forgetting to close a manual span leaves it dangling. Always prefer context managers (`with langfuse.start_as_current_observation(...)`) which auto-close [30].

### 7.8 Unsupported APIs

The OpenAI wrapper does not trace the Assistants API due to its server-side state model. Use `@observe()` to manually wrap those calls [26].

---

## 8. Skill Design

### 8.1 SKILL.md Structure

A Claude Code skill is a directory containing a `SKILL.md` file with YAML frontmatter (metadata for discovery and configuration) and Markdown body (instructions Claude follows when invoked) [32][33].

Key frontmatter fields:
- `name`: Lowercase, hyphens only, max 64 chars. Becomes the `/slash-command`. Gerund form recommended [34].
- `description`: Max 1024 chars. Claude uses this for routing via pure LLM reasoning -- there is no embedding search or classifier. Description quality is a functional correctness requirement [35].

Claude Code loads all skill descriptions into context at startup within a 15,000-character budget. When the user's message triggers the LLM to select a skill, only then is the SKILL.md body loaded. Bundled resources (`references/`, `scripts/`) are loaded on-demand when Claude reads them [34][35].

### 8.2 Progressive Disclosure

Three levels [34][35]:
1. **Metadata** (~100 words): Always in context. Name + description.
2. **SKILL.md body** (<500 lines): Loaded on trigger. Core instructions.
3. **Bundled resources** (unlimited): Loaded on demand. Zero context cost until accessed.

Scripts in `scripts/` execute without loading source code into context. References should be one level deep from SKILL.md -- deeply nested files cause Claude to `head -100` rather than reading completely [34].

### 8.3 Effective Patterns

Six empirically-identified patterns [35]:
1. **Script Automation** -- offload deterministic logic to bundled Python
2. **Read-Process-Write** -- file transformation workflows
3. **Search-Analyze-Report** -- codebase pattern detection
4. **Command Chain Execution** -- multi-step operations with dependencies
5. **Wizard-Style Workflows** -- explicit user confirmation between phases
6. **Iterative Refinement** -- progressive passes with increasing depth

A Langfuse skill primarily uses patterns 1 (setup verification scripts), 4 (multi-step instrumentation), and 5 (guided debugging workflows).

### 8.4 Evaluation-Driven Development

The official `skill-creator` meta-skill defines a rigorous iterative process [54]:
1. Capture intent and interview for edge cases
2. Write SKILL.md with progressive disclosure
3. Create 2-3 realistic test prompts in `evals/evals.json`
4. Run with-skill vs baseline comparison
5. Grade assertions, aggregate benchmarks with variance analysis
6. Iterate based on feedback

Descriptions should be "pushy" to combat underutilization: "Make sure to use this skill whenever the user mentions X, Y, or Z, even if they don't explicitly ask for it" [54].

---

## 9. Proposed Skill Structure

### 9.1 Directory Layout

```
langfuse-tracing/
  SKILL.md                       # Core instructions (<500 lines)
  references/
    sdk-patterns.md              # @observe, context managers, flush
    integrations.md              # LangChain, LangGraph, OpenAI
    cost-tracking.md             # Token counting, pricing, optimization
    evaluation.md                # Scores, experiments, LLM-as-Judge
    troubleshooting.md           # Common pitfalls, debug mode
  scripts/
    check_langfuse_setup.py      # Verify env vars, connectivity
    trace_cost_report.py         # Query cost data via Metrics API
  assets/
    quickstart-template.py       # Minimal @observe + flush boilerplate
    fastapi-template.py          # FastAPI + Langfuse integration
    langchain-template.py        # LangChain + CallbackHandler
  evals/
    evals.json                   # Test prompts for skill validation
```

### 9.2 SKILL.md Draft

```yaml
---
name: langfuse-tracing
description: >
  Instruments LLM applications with Langfuse v4 tracing, debugs missing or slow
  traces, analyzes token costs, manages prompt versions, and runs evaluations.
  Use when adding observability to LLM pipelines, investigating production issues,
  tracking costs, evaluating output quality, or setting up Langfuse for the first
  time. Triggers on mentions of Langfuse, LLM tracing, observability, token costs,
  prompt management, or evaluation experiments.
---
```

The SKILL.md body should follow a decision-tree structure:

1. **Setup**: Check for existing Langfuse installation. If none, guide through `pip install langfuse`, env var configuration, and connectivity verification via `scripts/check_langfuse_setup.py`.

2. **Instrumentation**: Based on the user's framework:
   - Pure Python: `@observe` decorator pattern from `references/sdk-patterns.md`
   - LangChain/LangGraph: `CallbackHandler` pattern from `references/integrations.md`
   - OpenAI: Drop-in import from `references/integrations.md`
   - Mixed: Universal `@observe` glue pattern

3. **Always include**: `langfuse.flush()` in appropriate location (finally block, atexit, or middleware). Flag if user's code is serverless.

4. **Debugging**: If user reports missing traces or errors, reference `references/troubleshooting.md`. Enable `debug=True`. Check credential ordering, flush timing, OTEL collisions.

5. **Cost analysis**: Reference `references/cost-tracking.md` for `usage_details`/`cost_details` patterns, custom model definitions, pricing tier configuration.

6. **Evaluation**: Reference `references/evaluation.md` for `create_score()`, `run_experiment()`, LLM-as-Judge setup, CI/CD integration.

### 9.3 Reference File Strategy

Each reference file should be self-contained with code examples, kept under 300 lines. The SKILL.md body provides routing logic ("If the user is working with LangChain, read `references/integrations.md`") without duplicating content.

`references/troubleshooting.md` should be structured as a diagnostic decision tree: symptom -> likely cause -> fix -> verification. This matches the Search-Analyze-Report pattern and leverages Claude's ability to follow structured diagnostic workflows [35].

### 9.4 Script Design

`scripts/check_langfuse_setup.py` should:
1. Check `LANGFUSE_PUBLIC_KEY`, `LANGFUSE_SECRET_KEY`, `LANGFUSE_BASE_URL` env vars
2. Attempt API health check via `GET /api/public/health`
3. Report SDK version (`langfuse.__version__`)
4. Detect common misconfigurations (EU vs US base URL, missing `sk-lf-` prefix)

`scripts/trace_cost_report.py` should:
1. Query recent traces via the Metrics API
2. Aggregate cost by model, trace name, and time period
3. Output a summary table identifying the top cost contributors

Both scripts execute without loading into context, preserving the context budget for instructions and references [34].

---

## Discussion

The Langfuse ecosystem has undergone rapid evolution -- three major SDK versions in under a year (v2 -> v3 -> v4). This velocity creates a persistent gap between what developers find in blog posts (often v2 patterns) and what the current SDK expects. The skill addresses this by encoding version-specific patterns and surfacing migration-relevant changes when it detects deprecated API usage.

The OTEL foundation is both Langfuse's greatest strength and its most common source of confusion. The automatic span capture from OTEL-instrumented libraries is powerful for comprehensive observability, but it creates unexpected interactions with other OTEL-based tools (Sentry, Datadog). The skill should always recommend an isolated `TracerProvider` when it detects other OTEL instrumentation in the project.

Cost tracking deserves special emphasis. The 3-5x variation in unit consumption based on instrumentation decisions [40] means that a skill guiding initial setup has an outsized impact on ongoing costs. The skill should default to selective instrumentation (top-level traces, key generation spans) rather than wrapping every function, and flag the cost implications when a user requests comprehensive instrumentation.

The evaluation features -- particularly `run_experiment()` with CI/CD integration -- represent an underutilized capability. Most teams instrument tracing but stop short of automated evaluation. The skill should proactively suggest evaluation setup when it detects a testing or deployment context.

---

## Conclusion

Langfuse v3/v4 provides a mature, OTEL-native observability platform for LLM applications. The Python SDK v4 offers clean primitives (`@observe`, context managers, `propagate_attributes`) that compose well across framework boundaries. However, correct instrumentation requires awareness of flush timing, OTEL context isolation, streaming edge cases, and cost-aware instrumentation choices that span multiple documentation pages.

A Claude Code skill encoding this knowledge would reduce the gap between "add tracing" intent and production-ready instrumentation. The proposed skill uses progressive disclosure to keep context costs low while providing deep reference material on demand, scripts for setup verification and cost analysis, and a decision-tree structure that routes to the right pattern based on the user's framework and use case.

Key open questions for skill development:
- How aggressively should the skill default to sampling in production setups?
- Should the skill auto-detect the user's framework from imports and skip the routing step?
- What is the right balance between prescriptive templates and flexible guidance?

These questions are best answered through the evaluation-driven development loop recommended by the skill-creator meta-skill [54]: create realistic test prompts, run with-skill vs baseline, grade, and iterate.

---

## References

See [langfuse-v3-skill-references.md](langfuse-v3-skill-references.md) for the full bibliography. In-text citations use bracketed IDs, e.g., [1], [2].
