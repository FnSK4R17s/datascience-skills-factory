<!-- Source: https://langfuse.com/docs/evaluation/evaluation-methods/scores-via-sdk -->
<!-- Fetched: 2026-03-30 -->
<!-- Langfuse Python SDK v4.0.4 -->

# Scores via API/SDK

## Overview

You can use the Langfuse SDKs or API to add scores to traces, observations, sessions and dataset runs. This enables custom evaluation workflows and extends Langfuse's scoring capabilities.

## Common Use Cases

- **Collecting user feedback**: Capture in-app feedback on application quality or performance via the Browser SDK
- **Custom evaluation data pipeline**: Continuously monitor quality by fetching traces, running evaluations, and ingesting scores back
- **Guardrails and security checks**: Verify output contains certain keywords, adheres to formats, or meets length requirements
- **Custom internal workflow tooling**: Build tools for human-in-the-loop workflows with custom schema references
- **Custom run-time evaluations**: Track whether generated SQL works or structured output is valid JSON
- **Session-level quality tracking**: Score full conversations by attaching scores via `sessionId`

## Ingesting Scores via API/SDKs

Scores can attach at different granularity levels: individual traces, specific observations, or full sessions.

Scores support three data types: **Numeric**, **Categorical**, or **Boolean**.

> **Important**: When ingesting scores manually using `trace_id`, you don't need to wait for trace creation. The score will appear in the scores table and link to the trace once created.

### Trace or Observation-level Scores

For trace and observation scores, `trace_id`/`traceId` is required; `observation_id`/`observationId` is optional. When attaching to an observation, provide both the observation ID and corresponding trace ID.

#### Python SDK Examples

**Numeric scores** (float values):

```python
from langfuse import get_client
langfuse = get_client()

# Method 1: Low-level method
langfuse.create_score(
    name="correctness",
    value=0.9,
    trace_id="trace_id_here",
    observation_id="observation_id_here",
    data_type="NUMERIC",
    comment="Factually correct"
)

# Method 2: Score within context
with langfuse.start_as_current_observation(as_type="span", name="my-operation") as span:
    span.score(
        name="correctness",
        value=0.9,
        data_type="NUMERIC",
        comment="Factually correct"
    )
    span.score_trace(
        name="overall_quality",
        value=0.95,
        data_type="NUMERIC"
    )

# Method 3: Score via current context
with langfuse.start_as_current_observation(as_type="span", name="my-operation"):
    langfuse.score_current_span(
        name="correctness",
        value=0.9,
        data_type="NUMERIC",
        comment="Factually correct"
    )
    langfuse.score_current_trace(
        name="overall_quality",
        value=0.95,
        data_type="NUMERIC"
    )
```

**Categorical scores** (string values):

```python
from langfuse import get_client
langfuse = get_client()

langfuse.create_score(
    name="accuracy",
    value="partially correct",
    trace_id="trace_id_here",
    data_type="CATEGORICAL",
    comment="Some factual errors"
)

with langfuse.start_as_current_observation(as_type="span", name="my-operation") as span:
    span.score(
        name="accuracy",
        value="partially correct",
        data_type="CATEGORICAL",
        comment="Some factual errors"
    )
```

**Boolean scores** (0 or 1 as float):

```python
from langfuse import get_client
langfuse = get_client()

langfuse.create_score(
    name="helpfulness",
    value=0,
    trace_id="trace_id_here",
    data_type="BOOLEAN",
    comment="Incorrect answer"
)

with langfuse.start_as_current_observation(as_type="span", name="my-operation") as span:
    span.score(
        name="helpfulness",
        value=1,
        data_type="BOOLEAN",
        comment="Very helpful response"
    )
```

#### JavaScript/TypeScript SDK Examples

**Numeric scores**:

```typescript
import { LangfuseClient } from "@langfuse/client";

const langfuse = new LangfuseClient();

langfuse.score.create({
  id: "unique_id",
  traceId: message.traceId,
  observationId: message.generationId,
  name: "correctness",
  value: 0.9,
  dataType: "NUMERIC",
  comment: "Factually correct"
});

await langfuse.flush();
```

**Categorical scores**:

```typescript
langfuse.score.create({
  id: "unique_id",
  traceId: message.traceId,
  name: "accuracy",
  value: "partially correct",
  dataType: "CATEGORICAL",
  comment: "Factually correct"
});

await langfuse.flush();
```

**Boolean scores**:

```typescript
langfuse.score.create({
  id: "unique_id",
  traceId: message.traceId,
  name: "helpfulness",
  value: 0,
  dataType: "BOOLEAN",
  comment: "Incorrect answer"
});

await langfuse.flush();
```

#### REST API Examples

**Numeric score**:

```bash
curl -X POST https://cloud.langfuse.com/api/public/scores \
  -u "pk-lf-...":"sk-lf-..." \
  -H "Content-Type: application/json" \
  -d '{
    "traceId": "trace_id_here",
    "observationId": "observation_id_here",
    "name": "correctness",
    "value": 0.9,
    "dataType": "NUMERIC",
    "comment": "Factually correct"
  }'
```

**Categorical score**:

```bash
curl -X POST https://cloud.langfuse.com/api/public/scores \
  -u "pk-lf-...":"sk-lf-..." \
  -H "Content-Type: application/json" \
  -d '{
    "traceId": "trace_id_here",
    "name": "accuracy",
    "value": "partially correct",
    "dataType": "CATEGORICAL",
    "comment": "Some factual errors"
  }'
```

**Boolean score**:

```bash
curl -X POST https://cloud.langfuse.com/api/public/scores \
  -u "pk-lf-...":"sk-lf-..." \
  -H "Content-Type: application/json" \
  -d '{
    "traceId": "trace_id_here",
    "name": "helpfulness",
    "value": 0,
    "dataType": "BOOLEAN",
    "comment": "Incorrect answer"
  }'
```

### Session-level Scores

To score an entire session without attaching to a trace or observation, provide only `session_id` (Python) or `sessionId` (JS/TS and API).

**Python**:

```python
from langfuse import get_client
langfuse = get_client()

langfuse.create_score(
    name="session_quality",
    value=0.85,
    session_id="session_id_here",
    data_type="NUMERIC",
    comment="Overall conversation quality"
)
```

**JavaScript/TypeScript**:

```typescript
import { LangfuseClient } from "@langfuse/client";

const langfuse = new LangfuseClient();

langfuse.score.create({
  name: "session_quality",
  value: 0.85,
  sessionId: "session_id_here",
  dataType: "NUMERIC",
  comment: "Overall conversation quality"
});

await langfuse.flush();
```

**REST API**:

```bash
curl -X POST https://cloud.langfuse.com/api/public/scores \
  -u "pk-lf-...":"sk-lf-..." \
  -H "Content-Type: application/json" \
  -d '{
    "sessionId": "session_id_here",
    "name": "session_quality",
    "value": 0.85,
    "dataType": "NUMERIC",
    "comment": "Overall conversation quality"
  }'
```

## Advanced Features

### Preventing Duplicate Scores

By default, Langfuse allows multiple scores with the same name on the same trace. This tracks score evolution or multiple feedback instances.

To prevent duplicates or update existing scores, create an **idempotency key** using `id` (JS/TS) or `score_id` (Python), such as `<trace_id>-<score_name>`.

### Enforcing a Score Config

Score configs standardize scores for analysis. Provide `configId` when creating a score to reference a previously created `ScoreConfig`.

Validation rules:

- **Score Name**: Must equal config's name
- **Score Data Type**: When provided, must match config's data type
- **Numeric Values**: Must fall within config's min/max range (optional min/max assumed as -infinity and +infinity)
- **Categorical Values**: Must match one of config's defined categories
- **Boolean Values**: Must equal `0` or `1`

#### Python SDK with Score Config

**Numeric scores**:

```python
from langfuse import get_client
langfuse = get_client()

langfuse.create_score(
    trace_id="trace_id_here",
    name="accuracy",
    value=0.9,
    comment="Factually correct",
    score_id="unique_id",
    config_id="78545-6565-3453654-43543",
    data_type="NUMERIC"
)

with langfuse.start_as_current_observation(as_type="span", name="my-operation") as span:
    span.score(
        name="accuracy",
        value=0.9,
        comment="Factually correct",
        config_id="78545-6565-3453654-43543",
        data_type="NUMERIC"
    )
```

**Categorical scores**:

```python
langfuse.create_score(
    trace_id="trace_id_here",
    name="correctness",
    value="correct",
    comment="Factually correct",
    score_id="unique_id",
    config_id="12345-6565-3453654-43543",
    data_type="CATEGORICAL"
)
```

**Boolean scores**:

```python
langfuse.create_score(
    trace_id="trace_id_here",
    name="helpfulness",
    value=1,
    comment="Factually correct",
    score_id="unique_id",
    config_id="93547-6565-3453654-43543",
    data_type="BOOLEAN"
)
```

### Inferred Score Properties

- If data type is not provided, it will be inferred from input
- For boolean and categorical scores, the system provides values in both numerical and string formats where applicable
- For boolean score reads, both numerical and string representations return (e.g., both `1` and `True`)
- For categorical scores, string representation always appears; numerical mapping only occurs with a `ScoreConfig`

## Updating Existing Scores

When creating a score, provide an optional `id` (JS/TS) or `score_id` (Python) parameter to update existing scores within your project. Set your own `id` as an idempotency key during initial score creation to update without fetching existing scores from Langfuse first.
