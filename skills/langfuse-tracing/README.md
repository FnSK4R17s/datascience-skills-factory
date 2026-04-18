<p align="center">
  <img src="logo.png" alt="langfuse-tracing" height="88">
</p>

<h1 align="center">langfuse-tracing</h1>

<p align="center">
  <strong>LLM observability with Langfuse v4 — tracing, costs, prompts, evals.</strong><br>
  <sub>Part of <a href="../../">Data Science Skills Factory</a></sub>
</p>

---

Instrument LLM applications with Langfuse v4 tracing, debug missing or slow
traces, analyze token costs, manage prompt versions, and run evaluations.

## Installation

```bash
npx skills add FnSK4R17s/datascience-skills-factory --skill langfuse-tracing
```

## File Structure

```
langfuse-tracing/
├── SKILL.md                          # Skill entry point (decision tree for Claude)
├── README.md                         # This file
├── scripts/
│   ├── check_langfuse_setup.py       # Verify Langfuse connection and config
│   └── trace_cost_report.py          # Generate token cost reports
├── references/
│   ├── sdk-patterns.md               # SDK v4 usage patterns
│   ├── integrations.md               # LangChain, OpenAI, FastAPI integrations
│   ├── prompts-and-evals.md          # Prompt management and evaluation
│   └── troubleshooting.md            # Common issues and fixes
└── assets/
    ├── quickstart-template.py        # Minimal setup template
    ├── fastapi-template.py           # FastAPI integration template
    └── langchain-template.py         # LangChain integration template
```
