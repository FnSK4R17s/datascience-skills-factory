# PLAN — Feature Planning Index

This file is the index for every planned feature in this repo. It is
maintained by the `plan-feature` skill. Every cell is a link — click through
to read the feature folder or the specific stage file. Sort rows by
most-recently-touched first. Do not hand-edit unless you know why.

## Features

> 💡 **Tip:** The ⏳ / 🚧 / ✅ glyphs in the table are **clickable links** —
> click any glyph to open that stage file. The feature name links to the
> feature folder.

| Feature | Research | Requirements | Deep Research | Backlog | Status |
|---------|----------|--------------|---------------|---------|--------|
| [langgraph-v1-skill](langgraph-v1-skill/) | [⏳](langgraph-v1-skill/01-research.md) | [⏳](langgraph-v1-skill/02-requirements.md) | [⏳](langgraph-v1-skill/03-deep-research.md) | [⏳](langgraph-v1-skill/04-backlog-item.md) | draft |
| [langchain-v1-skill](langchain-v1-skill/) | [⏳](langchain-v1-skill/01-research.md) | [⏳](langchain-v1-skill/02-requirements.md) | [⏳](langchain-v1-skill/03-deep-research.md) | [⏳](langchain-v1-skill/04-backlog-item.md) | draft |
| [mcp-python-sdk-skill](mcp-python-sdk-skill/) | [⏳](mcp-python-sdk-skill/01-research.md) | [⏳](mcp-python-sdk-skill/02-requirements.md) | [⏳](mcp-python-sdk-skill/03-deep-research.md) | [⏳](mcp-python-sdk-skill/04-backlog-item.md) | draft |
| [nemoguardrails-skill](nemoguardrails-skill/) | [⏳](nemoguardrails-skill/01-research.md) | [⏳](nemoguardrails-skill/02-requirements.md) | [⏳](nemoguardrails-skill/03-deep-research.md) | [⏳](nemoguardrails-skill/04-backlog-item.md) | draft |
| [python-telegram-bot-v21-skill](python-telegram-bot-v21-skill/) | [⏳](python-telegram-bot-v21-skill/01-research.md) | [⏳](python-telegram-bot-v21-skill/02-requirements.md) | [⏳](python-telegram-bot-v21-skill/03-deep-research.md) | [⏳](python-telegram-bot-v21-skill/04-backlog-item.md) | draft |
| [presidio-skill](presidio-skill/) | [⏳](presidio-skill/01-research.md) | [⏳](presidio-skill/02-requirements.md) | [⏳](presidio-skill/03-deep-research.md) | [⏳](presidio-skill/04-backlog-item.md) | draft |
| [detect-secrets-skill](detect-secrets-skill/) | [⏳](detect-secrets-skill/01-research.md) | [⏳](detect-secrets-skill/02-requirements.md) | [⏳](detect-secrets-skill/03-deep-research.md) | [⏳](detect-secrets-skill/04-backlog-item.md) | draft |

<!--
Example row once features exist:

| [user-sso](user-sso/) | [✅](user-sso/01-research.md) | [🚧](user-sso/02-requirements.md) | [⏳](user-sso/03-deep-research.md) | [⏳](user-sso/04-backlog-item.md) | draft |
-->

## Conventions

- **Feature column** links to the feature folder: `[<slug>](<slug>/)`.
- **Stage cells** are links to the stage file, with the status glyph as the
  link text: `[<glyph>](<slug>/0N-stage-name.md)`.
  - `⏳` not started (file exists from template, empty scaffold)
  - `🚧` in progress
  - `✅` done
- **Status column** is freeform text, not a link. It is the shipping state,
  not the planning state. A feature can be `✅` across all stages and still
  be `draft` until someone commits to building it. Typical values:
  `draft`, `v1 ready`, `v1 done`, `v2 done`, `archived`.

## Files per feature

Each `plan/<slug>/` folder contains:

- `01-research.md` — what exists in the codebase today
- `02-requirements.md` — user-facing contract, acceptance criteria
- `03-deep-research.md` — resolved open questions, risks
- `04-backlog-item.md` — handoff document for an implementing agent
