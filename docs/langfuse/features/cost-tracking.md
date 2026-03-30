<!-- Source: https://langfuse.com/docs/observability/features/token-and-cost-tracking -->
<!-- Fetched: 2026-03-30 -->
<!-- Langfuse Python SDK v4.0.4 -->

# Token and Cost Tracking

## Model Usage and Cost Tracking

Langfuse tracks the usage and costs of your LLM generations and provides breakdowns by usage types. Usage and cost can be tracked on observations of type `generation` and `embedding`.

- **Usage details**: number of units consumed per usage type
- **Cost details**: USD cost per usage type

Usage types can be arbitrary strings and differ by LLM provider. At the highest level, they can be simply `input` and `output`. As LLMs grow more sophisticated, additional usage types are necessary, such as `cached_tokens`, `audio_tokens`, `image_tokens`.

In the UI, Langfuse summarizes all usage types that include the string `input` as input usage types, similarly `output` as output usage types. If no `total` usage type is ingested, Langfuse sums up all usage type units to a total.

Both usage details and cost details can be either:

- **Ingested** via API, SDKs or integrations
- **Inferred** based on the `model` parameter of the generation. Langfuse comes with a list of predefined popular models and their tokenizers including OpenAI, Anthropic, and Google models. You can also add your own custom model definitions or request official support for new models via GitHub.

Ingested usage and cost are prioritized over inferred usage and cost.

Via the **Metrics API**, you can retrieve aggregated usage and cost metrics from Langfuse for downstream use in analytics, billing, and rate-limiting. The API allows you to filter by application type, user, or tags.

## Ingest Usage and/or Cost

If available in the LLM response, ingesting usage and/or cost is the most accurate and robust way to track usage in Langfuse.

Many of the Langfuse integrations automatically capture usage details and cost details data from the LLM response.

### Python SDK Examples

**When using the `@observe()` decorator:**

```python
from langfuse import observe, get_client
import anthropic

langfuse = get_client()
anthropic_client = anthropic.Anthropic()

@observe(as_type="generation")
def anthropic_completion(**kwargs):
  kwargs_clone = kwargs.copy()
  input = kwargs_clone.pop('messages', None)
  model = kwargs_clone.pop('model', None)
  langfuse.update_current_generation(
      input=input,
      model=model,
      metadata=kwargs_clone
  )

  response = anthropic_client.messages.create(**kwargs)

  langfuse.update_current_generation(
      usage_details={
          "input": response.usage.input_tokens,
          "output": response.usage.output_tokens,
          "cache_read_input_tokens": response.usage.cache_read_input_tokens
        },
      cost_details={
          "input": 1,
          "cache_read_input_tokens": 0.5,
          "output": 1,
      }
  )

  return response.content[0].text

@observe()
def main():
  return anthropic_completion(
      model="claude-3-opus-20240229",
      max_tokens=1024,
      messages=[
          {"role": "user", "content": "Hello, Claude"}
      ]
  )

main()
```

**When creating manual generations:**

```python
from langfuse import get_client
import anthropic

langfuse = get_client()
anthropic_client = anthropic.Anthropic()

with langfuse.start_as_current_observation(
    as_type="generation",
    name="anthropic-completion",
    model="claude-3-opus-20240229",
    input=[{"role": "user", "content": "Hello, Claude"}]
) as generation:
    response = anthropic_client.messages.create(
        model="claude-3-opus-20240229",
        max_tokens=1024,
        messages=[{"role": "user", "content": "Hello, Claude"}]
    )

    generation.update(
        output=response.content[0].text,
        usage_details={
            "input": response.usage.input_tokens,
            "output": response.usage.output_tokens,
            "cache_read_input_tokens": response.usage.cache_read_input_tokens
        },
        cost_details={
            "input": 1,
            "cache_read_input_tokens": 0.5,
            "output": 1,
        }
    )
```

### JavaScript/TypeScript SDK Examples

**When using the context manager:**

```typescript
import {
  startActiveObservation,
  startObservation,
  updateActiveObservation,
} from "@langfuse/tracing";

await startActiveObservation("context-manager", async (span) => {
  span.update({
    input: { query: "What is the capital of France?" },
  });

  const generation = startObservation(
    "llm-call",
    {
      model: "gpt-4",
      input: [{ role: "user", content: "What is the capital of France?" }],
    },
    { asType: "generation" }
  );

  generation.update({
    usageDetails: {
      input: 10,
      output: 5,
      cache_read_input_tokens: 2,
      some_other_token_count: 10,
      total: 17,
    },
    costDetails: {
      input: 1,
      output: 1,
      cache_read_input_tokens: 0.5,
      some_other_token_count: 1,
      total: 3.5,
    },
    output: { content: "The capital of France is Paris." },
  });

  generation.end();
});
```

### Compatibility with OpenAI

For increased compatibility with OpenAI, you can also use the OpenAI Usage schema. `prompt_tokens` will be mapped to `input`, `completion_tokens` will be mapped to `output`, and `total_tokens` will be mapped to `total`. The keys nested in `prompt_tokens_details` will be flattened with an `input_` prefix and `completion_tokens_details` will be flattened with an `output_` prefix.

**Python SDK:**

```python
from langfuse import get_client

langfuse = get_client()

with langfuse.start_as_current_observation(
    as_type="generation",
    name="openai-style-generation",
    model="gpt-4o"
) as generation:
    generation.update(
        usage_details={
            "prompt_tokens": 10,
            "completion_tokens": 25,
            "total_tokens": 35,
            "prompt_tokens_details": {
                "cached_tokens": 5,
                "audio_tokens": 2,
            },
            "completion_tokens_details": {
                "reasoning_tokens": 15,
            },
        }
    )
```

## Infer Usage and/or Cost

If either usage or cost are not ingested, Langfuse will attempt to infer the missing values based on the `model` parameter of the generation at the time of ingestion. This is especially useful for some model providers or self-hosted models which do not include usage or cost in the response.

### Usage

If a tokenizer is specified for the model, Langfuse automatically calculates token amounts for ingested generations.

Supported tokenizers:

| Model | Tokenizer | Used Package | Comment |
|-------|-----------|--------------|---------|
| `gpt-4o` | `o200k_base` | `tiktoken` | |
| `gpt*` | `cl100k_base` | `tiktoken` | |
| `claude*` | `claude` | `@anthropic-ai/tokenizer` | Not accurate for Claude 3 models. If possible, send tokens from API response. |

### Cost

Model definitions include prices per usage type. Usage types must match exactly with the keys in the `usage_details` object of the generation.

Langfuse automatically calculates cost for ingested generations at the time of ingestion if (1) usage is ingested or inferred, and (2) a matching model definition includes prices.

### Pricing Tiers

Some model providers charge different rates depending on the number of input tokens used. For example, Anthropic's Claude Sonnet 4.5 and Google's Gemini 2.5 Pro apply higher pricing when more than 200K input tokens are used.

Langfuse supports pricing tiers for models, enabling accurate cost calculation for these context-dependent pricing structures.

#### How Tier Matching Works

Each model can have multiple pricing tiers, each with:

- **Name**: A descriptive name (e.g., "Standard", "Large Context")
- **Priority**: Evaluation order (0 is reserved for default tier)
- **Conditions**: Rules that determine when the tier applies
- **Prices**: Cost per usage type for this tier

When calculating cost, Langfuse evaluates tiers in priority order (excluding the default tier). The first tier whose conditions are satisfied is used. If no conditional tier matches, the default tier is applied.

**Condition format:**

- `usageDetailPattern`: A regex pattern to match usage detail keys (e.g., `input` matches `input_tokens`, `input_cached_tokens`, etc.)
- `operator`: Comparison operator (`gt`, `gte`, `lt`, `lte`, `eq`, `neq`)
- `value`: The threshold value to compare against
- `caseSensitive`: Whether the pattern matching is case-sensitive (default: false)

### Custom Model Definitions

You can flexibly add your own model definitions (including pricing tiers) to Langfuse. This is especially useful for self-hosted or fine-tuned models.

#### Via Langfuse UI

Navigate to **Project Settings > Models** to add a new model definition. Add the prices per token type and save. All new traces with this model will have the correct token usage and cost inferred.

#### Via API

Model definitions can be managed programmatically:

```
GET    /api/public/models
POST   /api/public/models
GET    /api/public/models/{id}
DELETE /api/public/models/{id}
```

### Model Matching

Models are matched to generations based on:

| Generation Attribute | Model Attribute | Notes |
|----------------------|-----------------|-------|
| `model` | `match_pattern` | Uses regular expressions, e.g. `(?i)^(gpt-4-0125-preview)$` |

User-defined models take priority over models maintained by Langfuse.

### Cost Inference for Reasoning Models

Cost inference by tokenizing the LLM input and output is **not supported** for reasoning models such as the OpenAI o1 model family. Reasoning models take multiple steps to arrive at a response, generating reasoning tokens that are billed as output tokens. Since Langfuse does not have visibility into the reasoning tokens, it cannot infer the correct cost for generations that have no token usage provided.

To benefit from Langfuse cost tracking, provide the token usage when ingesting o1 model generations. When utilizing the Langfuse OpenAI wrapper or integrations such as LangChain, LlamaIndex or LiteLLM, token usage is collected automatically.

## Troubleshooting

- If you change the model definition, the updated costs will only be applied to new generations logged to Langfuse
- Only observations of type `generation` and `embedding` can track costs and usage
- If you use OpenRouter, Langfuse can directly capture the OpenRouter cost information
- If you use LiteLLM, Langfuse directly captures the cost information returned in each LiteLLM response
