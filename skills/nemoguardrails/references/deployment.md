# Deployment

Run NeMo Guardrails as a FastAPI server, in Docker, or as the production
microservice.
Source: `docs/deployment/`, `docs/run-rails/using-fastapi-server/`,
`docs/reference/cli/index.md`.

## FastAPI server

### Single config

```bash
nemoguardrails server --config ./config --port 8000
```

### Multi-config server

Point at a directory containing multiple config subdirectories. Each subdirectory
becomes a `config_id`:

```
configs/
├── content_safety/
│   ├── config.yml
│   └── rails/
│       └── input.co
├── customer_support/
│   ├── config.yml
│   ├── actions.py
│   └── kb/
│       └── policies.md
└── general/
    └── config.yml
```

```bash
nemoguardrails server --config ./configs --port 8000
```

### API endpoints

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/v1/chat/completions` | POST | Chat completion with guardrails |
| `/v1/rails/configs` | GET | List available guardrail configs |
| `/v1/rails/configs/{config_id}` | GET | Get specific config details |
| `/v1/models` | GET | List available models |

### Chat completions request

```bash
curl -X POST http://localhost:8000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "config_id": "content_safety",
    "messages": [{"role": "user", "content": "Hello!"}]
  }'
```

### Streaming via API

```bash
curl -X POST http://localhost:8000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "config_id": "content_safety",
    "messages": [{"role": "user", "content": "Tell me a story."}],
    "stream": true
  }'
```

### Generation options via API

```bash
curl -X POST http://localhost:8000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "config_id": "content_safety",
    "messages": [{"role": "user", "content": "Hello!"}],
    "options": {
      "rails": ["input", "output"],
      "log": {"activated_rails": true}
    }
  }'
```

### Actions server

Run custom actions on a separate server for horizontal scaling:

```bash
nemoguardrails actions-server --port 8001
```

Configure in `config.yml`:

```yaml
actions_server_url: "http://localhost:8001"
```

Actions with `is_system_action=True` bypass the actions server and run locally.
This is important for actions that need special parameters (context, llm, etc.).

## Interactive CLI chat

```bash
nemoguardrails chat --config ./config

# With streaming
nemoguardrails chat --config ./config --streaming

# Verbose mode
nemoguardrails chat --config ./config --verbose
```

## Docker

### Basic Dockerfile

```dockerfile
FROM python:3.11-slim

WORKDIR /app
RUN pip install --no-cache-dir nemoguardrails[nvidia,server]

COPY config/ ./config/
EXPOSE 8000

CMD ["nemoguardrails", "server", "--config", "./config", "--port", "8000"]
```

### With custom actions

```dockerfile
FROM python:3.11-slim

WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY config/ ./config/
EXPOSE 8000

CMD ["nemoguardrails", "server", "--config", "./config", "--port", "8000"]
```

### Docker Compose with NIM safety model

```yaml
version: "3.8"
services:
  guardrails:
    build: .
    ports:
      - "8000:8000"
    environment:
      - OPENAI_API_KEY=${OPENAI_API_KEY}
    depends_on:
      - safety-model

  safety-model:
    image: nvcr.io/nim/nvidia/llama-3.1-nemotron-safety-guard-8b-v3:latest
    ports:
      - "8080:8000"
    deploy:
      resources:
        reservations:
          devices:
            - capabilities: [gpu]
```

### NVIDIA production container

```bash
docker pull nvcr.io/nvidia/nemo-guardrails:latest
docker run -p 8000:8000 -v ./config:/config \
  nvcr.io/nvidia/nemo-guardrails:latest \
  nemoguardrails server --config /config --port 8000
```

## CLI reference

| Command | Description |
|---------|-------------|
| `nemoguardrails server` | Start FastAPI server |
| `nemoguardrails chat` | Interactive CLI chat |
| `nemoguardrails eval` | Run evaluation suite |
| `nemoguardrails convert` | Convert between Colang versions |
| `nemoguardrails actions-server` | Start actions server |

### Common flags

| Flag | Description |
|------|-------------|
| `--config PATH` | Config directory path |
| `--port N` | Server port (default 8000) |
| `--verbose` | Enable verbose logging |
| `--prefix PREFIX` | URL prefix for server |
| `--streaming` | Enable streaming (chat command) |

## NeMo Guardrails Microservice

Production-grade container image for Kubernetes deployment with Helm charts.
Configurations are portable — develop locally with the library, deploy to
production with the microservice.

| Aspect | Library | Microservice |
|--------|---------|-------------|
| Distribution | PyPI (`pip install`) | Container image |
| Deployment | Self-managed Python | Kubernetes + Helm |
| Scaling | Application-level | Orchestrator-managed |
| Configuration | YAML + Colang | Same format |

## External async token generators

Stream tokens from any source through guardrails:

```python
from typing import AsyncIterator

async def openai_streaming_generator(messages) -> AsyncIterator[str]:
    """Use OpenAI's streaming API as an external generator."""
    import openai
    stream = await openai.ChatCompletion.create(
        model="gpt-4o", messages=messages, stream=True
    )
    async for chunk in stream:
        if chunk.choices[0].delta.content:
            yield chunk.choices[0].delta.content

config = RailsConfig.from_path("config/with_output_rails")
app = LLMRails(config)

async for chunk in app.stream_async(
    messages=[{"role": "user", "content": "Tell me a story"}],
    generator=openai_streaming_generator(messages)
):
    # Output rails still apply to the external generator's tokens
    print(chunk, end="", flush=True)
```

When using an external generator:
- Internal LLM generation is completely bypassed
- Output rails are still applied to the tokens
- Generator should yield string tokens
