<p align="center">
  <img src="logo.png" alt="nemoguardrails" height="88">
</p>

<h1 align="center">nemoguardrails</h1>

<p align="center">
  <strong>Add programmable guardrails to LLM applications with NVIDIA NeMo Guardrails (Python).</strong><br>
  <sub>Part of <a href="../../">Data Science Skills Factory</a></sub>
</p>

---

NeMo Guardrails is an open-source Python library for adding programmable
guardrails to LLM-based applications. It acts as an intermediary between
application code and LLM requests/responses, running safety checks at five
stages: input, retrieval, dialog, execution, and output. Configuration is
YAML + Colang (an event-driven interaction modeling language); the runtime is
built on LangChain.

This skill covers the full API surface: `config.yml` schema (models, rails,
prompts, instructions), Colang 1.0 flow syntax, custom actions with
`@action()`, the Python SDK (`RailsConfig` + `LLMRails`), LangChain
integration (`RunnableRails`, `GuardrailsMiddleware`), LangGraph node
wrapping, the built-in guardrail catalog (self-check, content safety,
jailbreak detection, topic control, PII masking, fact checking, injection
detection), third-party integrations, deployment (FastAPI server, Docker,
microservice), and observability (tracing, OpenTelemetry, generation options).

## Install

```bash
npx skills add FnSK4R17s/datascience-skills-factory --skill nemoguardrails
```

## File structure

```
nemoguardrails/
├── SKILL.md                        # Entry point, triggers, decision tree
├── README.md                       # This file
├── logo.png                        # Brand mark
└── references/
    ├── config-yaml.md              # Full config.yml schema — models, engines, rails, prompts
    ├── colang.md                   # Colang 1.0 syntax — messages, flows, variables, branching
    ├── actions.md                  # @action() decorator, special params, output mapping
    ├── guardrail-catalog.md        # Built-in rails — self-check, content safety, jailbreak, PII
    ├── langchain-langgraph.md      # RunnableRails, middleware, LangGraph node wrapping
    ├── deployment.md               # FastAPI server, Docker, CLI, microservice
    └── observability.md            # Tracing, OpenTelemetry, logging, debugging
```

## When the skill fires

- Code imports `nemoguardrails`, constructs `RailsConfig` or `LLMRails`.
- User writes or debugs `config.yml`, Colang `.co` files, or custom actions.
- User integrates guardrails into LangChain chains or LangGraph agents.
- User configures content safety, jailbreak detection, PII masking, or other
  pre-built rails.
- User deploys or troubleshoots the guardrails FastAPI server.

## When it should NOT fire

- LangChain-only code with no `nemoguardrails` import — use the `langchain` skill.
- NVIDIA NIM deployment without guardrails wiring.
- The separate `guardrails` PyPI package (Guardrails AI) — different project.
- General prompt engineering not involving this library.
