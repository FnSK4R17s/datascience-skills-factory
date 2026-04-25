# Observability

Tracing, logging, and debugging for NeMo Guardrails.
Source: `docs/observability/tracing/`, `docs/observability/logging/`,
`docs/run-rails/using-python-apis/generation-options.md`.

## Generation options

Pass options to `generate()` / `generate_async()` for debugging and control.

### Disable specific rail types

```python
# All rails (default)
response = rails.generate(messages=messages)

# Equivalent to default
response = rails.generate(messages=messages, options={
    "rails": ["input", "dialog", "retrieval", "output"]
})

# Input rails only — validate user input without generating a response
response = rails.generate(
    messages=[{"role": "user", "content": "Some user input."}],
    options={"rails": ["input"]}
)
# Returns the same string if allowed, or "I'm sorry..." if blocked

# Input + output rails only — validate both user input and an external response
response = rails.generate(messages=[
    {"role": "user", "content": "What's 2+2?"},
    {"role": "assistant", "content": "The answer is 4."}
], options={
    "rails": ["input", "output"]
})

# Output rails only — validate just the bot response
response = rails.generate(messages=[
    {"role": "user", "content": ""},
    {"role": "assistant", "content": "Some bot output."}
], options={
    "rails": ["output"]
})
```

### Detailed logging

```python
response = rails.generate(messages=messages, options={
    "log": {
        "activated_rails": True,    # Which rails fired
        "llm_calls": True,          # LLM call details (prompt, completion, tokens)
        "internal_events": True,    # Internal event stream
        "colang_history": True      # Conversation in Colang format
    }
})

# Print human-readable summary
response.log.print_summary()
```

Example output:

```
# General stats

- Total time: 2.85s
  - [0.56s][19.64%]: INPUT Rails
  - [1.40s][49.02%]: DIALOG Rails
  - [0.58s][20.22%]: GENERATION Rails
  - [0.31s][10.98%]: OUTPUT Rails
- 5 LLM calls, 2.74s total duration, 1641 total prompt tokens,
  103 total completion tokens, 1744 total tokens.

# Detailed stats

- [0.56s] INPUT (self check input): 1 actions (self_check_input), 1 llm calls [0.56s]
- [0.43s] DIALOG (generate user intent): 1 actions (generate_user_intent), 1 llm calls
- [0.96s] DIALOG (generate next step): 1 actions (generate_next_step), 1 llm calls
- [0.58s] GENERATION (generate bot message): 2 actions, 1 llm calls
- [0.31s] OUTPUT (self check output): 1 actions (self_check_output), 1 llm calls
```

### Inspect individual LLM calls

```python
response = rails.generate(messages=messages, options={
    "log": {"llm_calls": True}
})

for llm_call in response.log.llm_calls:
    print(f"Task: {llm_call.task}")
    print(f"Prompt tokens: {llm_call.prompt_tokens}")
    print(f"Completion tokens: {llm_call.completion_tokens}")
    print(f"Total tokens: {llm_call.total_tokens}")
    print(f"Duration: {llm_call.duration}s")
    print(f"Prompt: {llm_call.prompt[:100]}...")
    print(f"Completion: {llm_call.completion}")
    print("---")
```

### Output variables

Return context variables from the generation:

```python
response = rails.generate(messages=messages, options={
    "output_vars": ["user_intent", "bot_intent", "relevant_chunks"]
})

print(response.output_data)
# {"user_intent": "ask about weather", "bot_intent": "provide weather info", ...}

# Return all context variables
response = rails.generate(messages=messages, options={
    "output_vars": True
})
```

### Override LLM parameters

```python
response = rails.generate(messages=messages, options={
    "llm_params": {
        "temperature": 0.2,
        "max_tokens": 500
    }
})
```

### Get LLM output metadata

```python
response = rails.generate(messages=messages, options={
    "llm_output": True
})
# Returns token_usage, model_name, etc. (provider-dependent)
```

### explain() method

```python
info = rails.explain()
info.print_llm_calls_summary()
```

## Verbose mode

```python
rails = LLMRails(config, verbose=True)
```

Logs every step: intent generation, flow matching, action execution, LLM calls.
Useful during development, too noisy for production.

## Tracing

### Enable in config.yml

```yaml
tracing:
  enabled: true
  adapters:
    - name: FileSystem
      parameters:
        log_dir: ./traces
  span_format: opentelemetry
  enable_content_capture: true
```

### Built-in adapters

| Adapter | Description |
|---------|-------------|
| `FileSystem` | Write traces to local JSON files |
| `OpenTelemetry` | Export to OTLP-compatible backends (Jaeger, Grafana, etc.) |

### OpenTelemetry integration

```yaml
tracing:
  enabled: true
  adapters:
    - name: OpenTelemetry
      parameters:
        exporter: otlp
        endpoint: "http://localhost:4317"
  span_format: opentelemetry
```

Requires `pip install nemoguardrails[tracing]`.

Also supports exporting guardrails log records as OpenTelemetry log signals
alongside traces.

## Streaming with metadata

```python
async for chunk in rails.stream_async(
    messages=messages,
    include_metadata=True
):
    if isinstance(chunk, dict) and "metadata" in chunk:
        meta = chunk["metadata"]
        print(f"\nFinish reason: {meta['response_metadata']['finish_reason']}")
        print(f"Tokens: {meta['usage_metadata']}")
    else:
        text = chunk["text"] if isinstance(chunk, dict) else chunk
        print(text, end="", flush=True)
```

Final chunk with metadata:

```python
{"text": "", "metadata": {
    "response_metadata": {"finish_reason": "stop", "model_name": "gpt-4o"},
    "usage_metadata": {"input_tokens": 75, "output_tokens": 9, "total_tokens": 84}
}}
```

## LangSmith integration

Auto-integrated. Set env vars and all LLM calls (including guardrail checks)
appear as spans:

```bash
export LANGCHAIN_TRACING_V2=true
export LANGCHAIN_ENDPOINT=https://api.smith.langchain.com
export LANGCHAIN_API_KEY=<key>
export LANGCHAIN_PROJECT=<project>
```

## Debugging workflow

1. Enable `verbose=True` on `LLMRails` constructor.
2. Add `log.activated_rails: true` to generation options.
3. Check which rails fired and which blocked.
4. If a rail incorrectly blocks, inspect the prompt template and LLM response.
5. Use `output_vars` to examine `user_intent`, `bot_intent`, `relevant_chunks`.
6. For production, switch to OpenTelemetry tracing with structured export.
7. Monitor token usage — each guardrail rail is an additional LLM call.
