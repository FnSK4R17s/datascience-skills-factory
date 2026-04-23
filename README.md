<p align="center">
  <img src="logo.png" alt="Data Science Skills Factory" height="97">
</p>

<h1 align="center">Data Science Skills Factory</h1>

<p align="center">
  <strong>Production-grade skills for AI coding agents. Data science, ML ops, observability.</strong><br>
  <em>Built for Claude Code, compatible with any agent that reads SKILL.md files.</em><br>
  <sub>Each skill is self-contained with references, scripts, and code templates.</sub>
</p>

---

> [!WARNING]
> **Beta Software** — Skills are under active development. Your feedback helps make them better!
>
> Have feedback or found a bug? Reach out at [**@_Shikh4r_** on X](https://x.com/_Shikh4r_)

## Quick Start

```bash
npx skills add FnSK4R17s/datascience-skills-factory
```

## Skills

| Skill | What it does | Install |
|-------|-------------|---------|
| [langfuse-tracing](skills/langfuse-tracing/) | Instrument LLM apps with Langfuse v4 — `@observe` tracing, LangChain/OpenAI integrations, cost tracking, prompt management, evaluation, debugging | `npx skills add FnSK4R17s/datascience-skills-factory --skill langfuse-tracing` |
| [prd-karpathy-style](skills/prd-karpathy-style/) | Generate Karpathy-style PRDs — opinionated idea docs designed to be handed to LLM agents for implementation | `npx skills add FnSK4R17s/datascience-skills-factory --skill prd-karpathy-style` |
| [auto-format](skills/auto-format/) | Detect project languages, install formatters (ruff, prettier, rustfmt), generate configs, and wire up a PostToolUse hook for automatic formatting on every file write | `npx skills add FnSK4R17s/datascience-skills-factory --skill auto-format` |
| [qmd-search](skills/qmd-search/) | Install qmd (local hybrid search — BM25 + vectors + LLM reranking), index markdown collections, and optionally wire up MCP server + PostToolUse hook for auto-reindexing | `npx skills add FnSK4R17s/datascience-skills-factory --skill qmd-search` |
| [brand-kit](skills/brand-kit/) | Config-driven logo generation using Fluent 3D emoji composition — define base mark + per-skill suffixes in `branding.yml`, interactive bootstrap walks you through brand setup | `npx skills add FnSK4R17s/datascience-skills-factory --skill brand-kit` |
| [plan-feature](skills/plan-feature/) | Walk through Research → Requirements → Deep Research → Backlog Item stages, producing a single agent-ready, Karpathy-style backlog doc per feature under `plan/<slug>/` | `npx skills add FnSK4R17s/datascience-skills-factory --skill plan-feature` |
| [repo-best-practices](skills/repo-best-practices/) | Bootstrap `CLAUDE.md` (symlinked to `AGENTS.md`) and `ANTIPATTERNS.md`, log user corrections as structured anti-patterns, and surface repeated tasks as skill + subagent extraction candidates | `npx skills add FnSK4R17s/datascience-skills-factory --skill repo-best-practices` |
| [tdd](skills/tdd/) | Red-green-refactor TDD discipline as a context injection — adapted from mattpocock/skills/tdd. Soft skill, no enforcement, no state | `npx skills add FnSK4R17s/datascience-skills-factory --skill tdd` |
| [gpl-license-checker](skills/gpl-license-checker/) | Block GPL / AGPL / SSPL / unknown-license deps from contaminating MIT or Apache-2.0 repos — SPDX-keyed policy + known-quirks reference data. Problem statement, not prescription: the invoking agent decides how to look up and classify | `npx skills add FnSK4R17s/datascience-skills-factory --skill gpl-license-checker` |
| [codespell](skills/codespell/) | Detect and fix typos in source + docs — slash command, PostToolUse hook (auto-fix on write), and pre-commit hook. Shared `.codespellrc` config across all three layers | `npx skills add FnSK4R17s/datascience-skills-factory --skill codespell` |
| [mcp-python-sdk](skills/mcp-python-sdk/) | Build MCP servers and clients in Python — FastMCP decorators, low-level Server API, stdio and Streamable HTTP transports, OAuth authorization, and in-process testing patterns | `npx skills add FnSK4R17s/datascience-skills-factory --skill mcp-python-sdk` |
| [langchain](skills/langchain/) | Guide agents writing LangChain v1 Python code — `create_agent`, `@tool` + `ToolRuntime`, middleware, messages + content blocks, structured output, and v2 streaming | `npx skills add FnSK4R17s/datascience-skills-factory --skill langchain` |
| [langgraph](skills/langgraph/) | Build stateful, long-running agent workflows with LangGraph v1 — StateGraph, nodes and edges, checkpointers, interrupt/resume patterns, stream modes, and the Functional API | `npx skills add FnSK4R17s/datascience-skills-factory --skill langgraph` |
| [python-telegram-bot](skills/python-telegram-bot/) | Build Telegram bots with python-telegram-bot v21+ — Application lifecycle, handlers + filters, ConversationHandler states, CallbackContext + JobQueue, inline callbacks, webhooks, and persistence | `npx skills add FnSK4R17s/datascience-skills-factory --skill python-telegram-bot` |

## Skill Structure

Each skill follows progressive disclosure — minimal context cost, deep references on demand:

```
skills/<skill-name>/
├── SKILL.md          # Runtime usage guide (loaded when skill triggers)
├── BOOTSTRAP.md      # One-time setup flow (interactive, run once then delete)
├── README.md         # Human-facing docs with branded logo header
├── references/       # Deep-dive docs (loaded on demand, <300 lines each)
├── scripts/          # Executable utilities (run, not loaded into context)
└── assets/           # Config templates and boilerplate
```

Not every skill needs all files — `SKILL.md` is the only required one.
`BOOTSTRAP.md` is for skills that have a setup step (installing tools,
creating config files, wiring up hooks).

## Branding

Every skill README has a branded header — a Fluent 3D emoji `logo.png`
generated from [`branding.yml`](branding.yml). See the
[brand-kit](skills/brand-kit/) skill for the full design
system and generation scripts.

## Contributing

1. Create `skills/<skill-name>/SKILL.md` with YAML frontmatter (`name`, `description`)
2. Add `BOOTSTRAP.md` if the skill has a first-time setup flow
3. Add `references/` for detailed patterns
4. Add `scripts/` for executable utilities
5. Add `assets/` for config templates
6. Add a suffix emoji to `branding.yml` and generate `logo.png`
7. PR it

## References & inspiration

Skills we've learned from, adapted, or directly built on top of. Credit where credit is due.

| Source | What we took | Where it lives |
|--------|--------------|----------------|
| [mattpocock/skills](https://github.com/mattpocock/skills) (MIT) | The whole `tdd` skill — adapted verbatim. Soft-skill discipline reminder, anti-horizontal-slice framing, deep-modules and interface-design references | [skills/tdd/](skills/tdd/) |

Found a skill we should learn from? Open a PR adding the row.
