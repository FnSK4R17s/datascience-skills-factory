# Prompt Management and Evaluation

## Prompt Types and Syntax

Two types (fixed at creation, cannot change):
- **Text prompts**: return a string
- **Chat prompts**: return `[{role, content}]` message arrays

Template syntax: `{{variable}}` (double braces).

```python
from langfuse import get_client

langfuse = get_client()

# Create text prompt
langfuse.create_prompt(
    name="movie-critic",
    type="text",
    prompt="As a {{criticlevel}} movie critic, do you like {{movie}}?",
    labels=["production"]
)

# Create chat prompt
langfuse.create_prompt(
    name="movie-critic-chat",
    type="chat",
    prompt=[
        {"role": "system", "content": "You are an {{criticlevel}} movie critic"},
        {"role": "user", "content": "Do you like {{movie}}?"},
    ],
    labels=["production"]
)
```

Prompts with duplicate names automatically create new versions.

---

## get_prompt() and compile()

```python
langfuse = get_client()

# Fetch by label (default: production)
prompt = langfuse.get_prompt("movie-critic")

# Fetch specific version
prompt = langfuse.get_prompt("movie-critic", version=3)

# Fetch by custom label
prompt = langfuse.get_prompt("movie-critic", label="staging")

# Fetch chat type
chat_prompt = langfuse.get_prompt("movie-critic-chat", type="chat")

# Compile with variables
compiled = prompt.compile(criticlevel="expert", movie="Dune 2")
# => "As an expert movie critic, do you like Dune 2?"

compiled_chat = chat_prompt.compile(criticlevel="expert", movie="Dune 2")
# => [{"role": "system", "content": "You are an expert movie critic"}, ...]
```

### Version control

- **latest**: Auto-tracks the newest version
- **production**: Default label served by `get_prompt()` with no label arg
- **Custom labels**: staging, canary, tenant-specific -- enable multi-environment promotion
- **Promotion/rollback**: Move the `production` label to any version via UI or API

### Caching and guaranteed availability

Prompts are cached client-side (zero added latency). `get_prompt()` throws only when no local cache exists AND the network request fails.

Mitigation strategies:
1. Pre-fetch on startup with fail-fast
2. Provide a fallback prompt

```python
prompt = langfuse.get_prompt("movie-critic", fallback="Rate this movie: {{movie}}")
if prompt.is_fallback:
    log.warning("Using fallback prompt -- Langfuse unavailable")
```

---

## LangChain Integration

`get_langchain_prompt()` converts `{{}}` syntax to LangChain's `{}` format:

```python
from langfuse import get_client
from langchain_core.prompts import ChatPromptTemplate

langfuse = get_client()

# Text prompt -> LangChain template
lf_prompt = langfuse.get_prompt("movie-critic")
lc_prompt = ChatPromptTemplate.from_template(lf_prompt.get_langchain_prompt())

# Chat prompt -> LangChain messages
lf_chat = langfuse.get_prompt("movie-critic-chat", type="chat")
lc_chat = ChatPromptTemplate.from_messages(lf_chat.get_langchain_prompt())
```

---

## Evaluation Methods Overview

| Method | Best For |
|--------|----------|
| LLM-as-a-Judge | Subjective assessments at scale (tone, accuracy, helpfulness) |
| UI Scoring | Quick manual quality checks |
| Annotation Queues | Ground truth building, team collaboration |
| SDK Scores | Custom pipelines, deterministic checks, user feedback |

---

## create_score() API

Three data types: **Numeric** (float), **Categorical** (string), **Boolean** (0 or 1).

```python
from langfuse import get_client

langfuse = get_client()

# Numeric score on a trace
langfuse.create_score(
    name="correctness",
    value=0.9,
    trace_id="trace_id_here",
    observation_id="observation_id_here",  # optional
    data_type="NUMERIC",
    comment="Factually correct"
)

# Categorical score
langfuse.create_score(
    name="accuracy",
    value="partially correct",
    trace_id="trace_id_here",
    data_type="CATEGORICAL",
    comment="Some factual errors"
)

# Boolean score
langfuse.create_score(
    name="helpfulness",
    value=1,  # 0 or 1
    trace_id="trace_id_here",
    data_type="BOOLEAN"
)

# Session-level score (no trace_id needed)
langfuse.create_score(
    name="session_quality",
    value=0.85,
    session_id="session_id_here",
    data_type="NUMERIC"
)
```

### Context-based scoring

```python
with langfuse.start_as_current_observation(as_type="span", name="my-op") as span:
    span.score(name="correctness", value=0.9, data_type="NUMERIC")
    span.score_trace(name="overall_quality", value=0.95, data_type="NUMERIC")
```

Also available: `langfuse.score_current_span()` and `langfuse.score_current_trace()` for scoring without a direct span reference.

### Idempotency (prevent duplicates)

Pass `score_id=f"{trace_id}-{score_name}"` as an idempotency key. Calling again with the same `score_id` updates instead of creating a duplicate.

---

## LLM-as-a-Judge

### Evaluation targets

- **Observations** (recommended): Individual LLM calls, executes in seconds
- **Traces**: Complete workflows, takes minutes
- **Experiments**: Controlled datasets with ground truth

### Template variables

Map via JSONPath: `{{input}}`, `{{output}}`, `{{ground_truth}}`

### Managed evaluators

Built-in evaluators (developed with RAGAS):
- Hallucination detection
- Context relevance
- Toxicity
- Helpfulness
- SQL semantic equivalence

Custom evaluators use user-defined prompt templates with the same variable system.

### Configuration

- Sampling rate controls what percentage of traces/observations are evaluated
- Evaluation executions create their own traces filterable by `langfuse-llm-as-a-judge` environment
- Execution tracing captures the exact prompt sent to the judge model, its response, and token consumption

---

## Datasets and Experiments

### Create datasets

```python
langfuse = get_client()

# Create dataset
langfuse.create_dataset(name="qa-benchmark")

# Add items (input required, expected_output optional)
langfuse.create_dataset_item(
    dataset_name="qa-benchmark",
    input={"question": "What is the capital of France?"},
    expected_output={"answer": "Paris"},
    metadata={"difficulty": "easy"}
)
```

JSON Schema validation is supported for dataset items.

### run_experiment()

```python
from langfuse import get_client
from langfuse.evaluation import Evaluation

langfuse = get_client()

def my_task(*, item, **kwargs):
    """Execute application logic on each dataset item."""
    return call_llm(item.input["question"])

def accuracy_eval(*, input, output, expected_output, **kwargs):
    """Item-level evaluator: receives input, output, expected_output, metadata."""
    return Evaluation(
        name="accuracy",
        value=1.0 if expected_output["answer"].lower() in output.lower() else 0.0
    )

def aggregate_eval(*, item_results, **kwargs):
    """Run-level evaluator: receives all item results for aggregate metrics."""
    scores = [r.evaluations[0].value for r in item_results if r.evaluations]
    avg = sum(scores) / len(scores) if scores else 0
    return Evaluation(name="avg_accuracy", value=avg)

dataset = langfuse.get_dataset("qa-benchmark")
result = dataset.run_experiment(
    name="Model v2",
    task=my_task,
    evaluators=[accuracy_eval],
    run_evaluators=[aggregate_eval],
    max_concurrency=10
)
```

Features:
- Concurrent task execution with configurable limits
- Automatic trace generation for observability
- Failure isolation preventing cascade errors
- Results visible in Langfuse UI for comparison across runs

### CI/CD integration

```python
# In pytest
def test_model_accuracy():
    dataset = get_client().get_dataset("qa-benchmark")
    result = dataset.run_experiment(
        name="CI-run",
        task=my_task,
        evaluators=[accuracy_eval],
        run_evaluators=[aggregate_eval]
    )
    avg_accuracy = next(
        e.value for e in result.run_evaluations if e.name == "avg_accuracy"
    )
    assert avg_accuracy >= 0.8, f"Below threshold: {avg_accuracy}"
```

### The evaluation loop

1. **Offline**: Run experiments on fixed datasets before deployment
2. **Deploy**: Push changes to production
3. **Online**: Score live production traces (LLM-as-Judge, annotation queues)
4. **Discover**: Find edge cases in production traces
5. **Expand**: Add new edge cases back to datasets
6. **Repeat**: Run experiments again to prevent regressions
