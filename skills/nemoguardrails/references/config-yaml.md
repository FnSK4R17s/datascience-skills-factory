# config.yml Schema Reference

Full reference for the NeMo Guardrails `config.yml` file.
Source: `docs/configure-rails/configuration-reference.md`,
`nemoguardrails/rails/llm/config.py`.

## Models

```yaml
models:
  - type: main                    # Required: model identifier
    engine: openai                # Required: LLM provider
    model: gpt-4                  # Required: model name
    mode: chat                    # "chat" (default) or "text"
    api_key_env_var: OPENAI_KEY   # Env var for API key
    parameters:                   # Provider-specific params
      temperature: 0.7
      max_tokens: 1000
    cache:
      enabled: false
      maxsize: 50000
```

### Reserved model types

| Type | Purpose |
|------|---------|
| `main` | Primary application LLM |
| `embeddings` | Embedding model for KB + similarity search |
| `jailbreak_detection` | NIM jailbreak detection model |

### Common model types

| Type | Usage in flows |
|------|---------------|
| `content_safety` | `content safety check input $model=content_safety` |
| `topic_control` | `topic safety check input $model=topic_control` |
| `llama_guard` | `llama guard check input $model=llama_guard` |

Custom types: define any `type` string and reference via `$model=<type>` in flows.

### Engines

Core: `openai`, `nim` (alias: `nvidia_ai_endpoints`), `azure`, `anthropic`,
`cohere`, `vertexai`.

Self-hosted: `huggingface_hub`, `huggingface_endpoint`, `vllm_openai`,
`trt_llm`, `self_hosted`.

Embeddings: `FastEmbed` (default), `openai`, `nim`.

### Model cache configuration

```yaml
models:
  - type: content_safety
    engine: nim
    model: nvidia/llama-3.1-nemotron-safety-guard-8b-v3
    cache:
      enabled: true
      maxsize: 50000
      stats:
        enabled: true
        log_interval: 60  # Log cache stats every 60 seconds
```

## Example: Multiple models

```yaml
models:
  # Main application LLM
  - type: main
    engine: openai
    model: gpt-4
    parameters:
      temperature: 0.7

  # Dedicated safety model for input/output checks
  - type: self_check_input
    engine: openai
    model: gpt-4o-mini

  - type: self_check_output
    engine: openai
    model: gpt-4o-mini

  # NVIDIA content safety model via NIM
  - type: content_safety
    engine: nim
    parameters:
      base_url: "http://localhost:8000/v1"
      model_name: "nvidia/llama-3.1-nemotron-safety-guard-8b-v3"

  # Embedding model for knowledge base
  - type: embeddings
    engine: FastEmbed
    model: all-MiniLM-L6-v2
```

## Example: Azure OpenAI

```yaml
models:
  - type: main
    engine: azure
    model: gpt-4
    parameters:
      api_version: "2024-02-01"
      azure_deployment: "my-gpt4-deployment"
      azure_endpoint: "https://my-resource.openai.azure.com/"
    api_key_env_var: AZURE_OPENAI_API_KEY
```

## Example: Self-hosted with vLLM

```yaml
models:
  - type: main
    engine: vllm_openai
    parameters:
      openai_api_base: "http://localhost:8000/v1"
      model_name: "meta-llama/Meta-Llama-3-8B-Instruct"
```

## Rails

```yaml
rails:
  input:
    parallel: false           # Run input flows in parallel
    flows:
      - self check input
      - check jailbreak

  output:
    parallel: false
    flows:
      - self check output
    streaming:
      enabled: false
      chunk_size: 200         # Tokens per chunk
      context_size: 50        # Tokens carried from previous chunk
      stream_first: true      # Stream before applying output rails

  retrieval:
    flows:
      - check retrieval sensitive data

  dialog:
    single_call:
      enabled: false
      fallback_to_multiple_calls: true
    user_messages:
      embeddings_only: false

  actions:
    instant_actions: []

  tool_output:
    flows: []
    parallel: false

  tool_input:
    flows: []
    parallel: false
```

### Built-in input flows

| Flow | Description |
|------|-------------|
| `self check input` | LLM-based policy compliance check |
| `jailbreak detection heuristics` | Perplexity-based jailbreak detection |
| `jailbreak detection model` | NIM-based jailbreak detection |
| `mask sensitive data on input` | Mask PII in user input |
| `detect sensitive data on input` | Detect and block PII |
| `llama guard check input` | LlamaGuard content moderation |
| `content safety check input` | NVIDIA content safety model |
| `topic safety check input` | Topic control model |
| `gliner detect pii on input` | GLiNER PII detection (block) |
| `gliner mask pii on input` | GLiNER PII masking |

### Built-in output flows

| Flow | Description |
|------|-------------|
| `self check output` | LLM-based policy compliance check |
| `self check facts` | Fact verification against KB |
| `self check hallucination` | Hallucination detection |
| `mask sensitive data on output` | Mask PII in output |
| `llama guard check output` | LlamaGuard content moderation |
| `content safety check output` | NVIDIA content safety model |
| `injection detection` | SQL/code/XSS/template injection |
| `gliner detect pii on output` | GLiNER PII detection (block) |
| `gliner mask pii on output` | GLiNER PII masking |

### Dialog rails configuration

```yaml
rails:
  dialog:
    single_call:
      enabled: false               # Single LLM call for intent + response
      fallback_to_multiple_calls: true
    user_messages:
      embeddings_only: false        # Use only embeddings for intent matching
      embeddings_only_similarity_threshold: null
      embeddings_only_fallback_intent: null
```

When `single_call.enabled: true`, the dialog rails flow is simplified to a single
LLM call that predicts user intent, next step, and bot message together. Lower
latency but potentially lower quality.

## Rails config section

Per-rail configuration under `rails.config`:

### Jailbreak detection

```yaml
rails:
  config:
    jailbreak_detection:
      server_endpoint: "http://localhost:1337/heuristics"
      length_per_perplexity_threshold: 89.79
      prefix_suffix_perplexity_threshold: 1845.65
      nim_base_url: "http://localhost:8000/v1/"
      nim_server_endpoint: "classify"
      api_key_env_var: "JAILBREAK_KEY"
```

### Sensitive data detection (Presidio)

```yaml
rails:
  config:
    sensitive_data_detection:
      recognizers: []            # Custom Presidio recognizers
      input:
        entities: [PERSON, EMAIL_ADDRESS, PHONE_NUMBER, CREDIT_CARD]
        mask_token: "*"
        score_threshold: 0.2
      output:
        entities: [PERSON, EMAIL_ADDRESS]
      retrieval:
        entities: [PERSON]
```

### GLiNER PII detection

```yaml
rails:
  config:
    gliner:
      server_endpoint: http://localhost:1235/v1/extract
      threshold: 0.5
      input:
        entities: [email, phone_number, ssn, first_name, last_name]
      output:
        entities: [email, phone_number, credit_debit_card]
```

### Injection detection

```yaml
rails:
  config:
    injection_detection:
      injections: [sqli, template, code, xss]
      action: reject    # "reject" = block, "omit" = strip
      yara_path: ""     # Custom YARA rules directory
      yara_rules: {}    # Inline YARA rules
```

### Content safety multilingual

```yaml
rails:
  config:
    content_safety:
      multilingual:
        enabled: true
        refusal_messages:
          en: "Sorry, I cannot help with that."
          es: "Lo siento, no puedo ayudar con eso."
```

Supported languages: en, es, zh, de, fr, hi, ja, ar, th.

### Fact checking

```yaml
rails:
  config:
    fact_checking:
      parameters:
        endpoint: "http://localhost:5000/alignscore_large"
      fallback_to_self_check: false
```

### Third-party integrations

```yaml
# AutoAlign
rails:
  config:
    autoalign:
      parameters: {}
      input:
        guardrails_config: {}
      output:
        guardrails_config: {}

# Patronus
rails:
  config:
    patronus:
      input:
        evaluate_config:
          success_strategy: all_pass
      output:
        evaluate_config:
          success_strategy: all_pass

# Clavata
rails:
  config:
    clavata:
      server_endpoint: "https://gateway.app.clavata.ai:8443"
      label_match_logic: ANY
      input:
        policy: "policy_alias"
      output:
        policy: "policy_alias"

# Cisco AI Defense
rails:
  config:
    ai_defense:
      timeout: 30.0
      fail_open: false

# Fiddler
rails:
  config:
    fiddler:
      fiddler_endpoint: "http://localhost:8080/process/text"
      safety_threshold: 0.1
      faithfulness_threshold: 0.05

# Pangea AI Guard
rails:
  config:
    pangea:
      input:
        recipe: "recipe_key"
      output:
        recipe: "recipe_key"

# Trend Micro
rails:
  config:
    trend_micro:
      v1_url: "https://api.xdr.trendmicro.com/beta/aiSecurity/guard"
      api_key_env_var: "TREND_MICRO_API_KEY"

# GuardrailsAI
rails:
  config:
    guardrails_ai:
      input:
        validators:
          - name: toxic_language
            parameters:
              threshold: 0.5
      output:
        validators:
          - name: pii
            parameters: {}

# Private AI
rails:
  config:
    private_ai_detection:
      server_endpoint: "http://localhost:8080/process/text"
      input:
        entities: [NAME_FAMILY, EMAIL_ADDRESS]
      output:
        entities: [NAME_FAMILY]
```

## Prompts

```yaml
prompts:
  - task: self_check_input        # Task identifier
    content: |                    # Template (mutually exclusive with messages)
      Check: {{ user_input }}
      Answer [Yes/No]:
    output_parser: null           # Output parser name
    max_length: 16000             # Max prompt length (chars)
    max_tokens: null              # Max response tokens
    mode: standard
    models: null                  # Restrict to engines/models
```

### Task names

| Task | Description |
|------|-------------|
| `self_check_input` | Check user input against policy |
| `self_check_output` | Check bot output against policy |
| `self_check_facts` | Verify factual accuracy |
| `self_check_hallucination` | Detect hallucinations |
| `generate_user_intent` | Generate canonical user intent |
| `generate_next_steps` | Determine next conversation step |
| `generate_bot_message` | Generate bot response |
| `general` | General response generation (no dialog rails) |

### Model-specific prompts

```yaml
prompts:
  - task: content_safety_check_input $model=content_safety
    content: |
      Check if this content is safe: {{ user_input }}
    output_parser: nemoguard_parse_prompt_safety
    max_tokens: 50

  - task: topic_safety_check_input $model=topic_control
    content: |
      You are a customer service agent. Check if this is on-topic: {{ user_input }}
```

### Chat-format prompts

```yaml
prompts:
  - task: self_check_input
    messages:
      - type: system
        content: "You are a safety classifier."
      - type: user
        content: "Is this input safe? {{ user_input }}. Answer [Yes/No]:"
```

## Other top-level keys

### Instructions

```yaml
instructions:
  - type: general
    content: |
      You are a helpful, harmless, and honest assistant.
      You work for Acme Corp and help customers with their orders.
      You should always be polite and professional.
```

### Sample conversation

```yaml
sample_conversation: |
  user "Hello"
    express greeting
  bot express greeting
    "Hello! How can I help you today?"
  user "What can you do?"
    ask about capabilities
  bot respond about capabilities
    "I can help you with orders, returns, and product information."
```

### Knowledge base

```yaml
knowledge_base:
  folder: kb
  embedding_search_provider:
    name: default
    parameters: {}
    cache:
      enabled: false
```

### Import paths (shared configs)

```yaml
import_paths:
  - path/to/shared/safety-config
  - path/to/shared/company-prompts
```

### Passthrough mode (for tool calling)

```yaml
passthrough: true
```

Required when integrating with LangGraph or using tool-calling LLMs. Ensures
internal guardrail tasks don't interfere with tool use.

### Tracing

```yaml
tracing:
  enabled: true
  adapters:
    - name: OpenTelemetry
      parameters:
        exporter: otlp
        endpoint: "http://localhost:4317"
  span_format: opentelemetry
  enable_content_capture: true
```

## Complete example: Defense-in-depth config

```yaml
models:
  - type: main
    engine: nim
    model: meta/llama-3.1-70b-instruct
    parameters:
      temperature: 0.7

  - type: content_safety
    engine: nim
    parameters:
      base_url: "http://localhost:8000/v1"
      model_name: "nvidia/llama-3.1-nemotron-safety-guard-8b-v3"

  - type: embeddings
    engine: FastEmbed
    model: all-MiniLM-L6-v2

rails:
  input:
    parallel: true
    flows:
      - content safety check input $model=content_safety
      - jailbreak detection heuristics
      - mask sensitive data on input

  output:
    flows:
      - self check output
      - self check facts
      - mask sensitive data on output
      - injection detection
    streaming:
      enabled: true
      stream_first: true

  config:
    jailbreak_detection:
      server_endpoint: "http://localhost:1337/heuristics"
    sensitive_data_detection:
      input:
        entities: [PERSON, EMAIL_ADDRESS, CREDIT_CARD]
        mask_token: "[REDACTED]"
      output:
        entities: [PERSON, EMAIL_ADDRESS]
    injection_detection:
      injections: [sqli, code, xss]
      action: reject

prompts:
  - task: content_safety_check_input $model=content_safety
    content: |
      Check if this content is safe: {{ user_input }}
    output_parser: nemoguard_parse_prompt_safety
    max_tokens: 50

  - task: self_check_output
    content: |
      Is this output safe and appropriate? {{ bot_response }}
      Answer [Yes/No]:

  - task: self_check_facts
    content: |-
      Evidence: {{ evidence }}
      Hypothesis: {{ response }}
      Is the hypothesis grounded in the evidence? Answer [Yes/No]:

instructions:
  - type: general
    content: |
      You are a helpful, harmless, and honest assistant for Acme Corp.

knowledge_base:
  folder: kb

tracing:
  enabled: true
  adapters:
    - name: OpenTelemetry
      parameters:
        exporter: otlp
        endpoint: "http://localhost:4317"
```
