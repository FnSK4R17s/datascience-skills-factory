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
| [mcp-python-sdk](skills/mcp-python-sdk/) | Build MCP servers and clients in Python — FastMCP (v1 stable) and MCPServer (v2 pre-alpha) decorator APIs, low-level Server, transports, OAuth 2.1, experimental tasks, and in-process testing | `npx skills add FnSK4R17s/datascience-skills-factory --skill mcp-python-sdk` |
| [langchain](skills/langchain/) | Guide agents writing LangChain v1 Python code — `create_agent`, `@tool` + `ToolRuntime`, middleware, models, memory, multi-agent patterns, RAG, MCP integration, human-in-the-loop, streaming, structured output, and observability | `npx skills add FnSK4R17s/datascience-skills-factory --skill langchain` |
| [langgraph](skills/langgraph/) | Build stateful, long-running agent workflows with LangGraph v1 — StateGraph + Functional API, checkpointers, interrupts, streaming, durable execution, subgraphs, time travel, cross-thread memory, Pregel runtime, observability, deployment, and testing | `npx skills add FnSK4R17s/datascience-skills-factory --skill langgraph` |
| [python-telegram-bot](skills/python-telegram-bot/) | Build Telegram bots with python-telegram-bot v21+ — Application lifecycle, handlers + filters, ConversationHandler states, JobQueue, webhooks, persistence, rate limiting, payments, polls, deep linking, Mini Apps, and error handling | `npx skills add FnSK4R17s/datascience-skills-factory --skill python-telegram-bot` |
| [nemoguardrails](skills/nemoguardrails/) | Add programmable guardrails to LLM apps with NVIDIA NeMo Guardrails — config.yml + Colang flows, custom actions, RunnableRails / LangGraph integration, built-in guardrail catalog (content safety, jailbreak, PII, topic control, fact checking), deployment, and observability | `npx skills add FnSK4R17s/datascience-skills-factory --skill nemoguardrails` |
| [multica](skills/multica/) | Work with the Multica platform — agents, issues, daemon, CLI, self-hosting, skills, autopilots, auth, and the full architecture. 25 reference docs from the official Multica documentation | `npx skills add FnSK4R17s/datascience-skills-factory --skill multica` |
| [sandcastle](skills/sandcastle/) | Orchestrate sandboxed AFK coding agents with Sandcastle (@ai-hero/sandcastle) — run/createSandbox/createWorktree API, agent and sandbox providers, branch strategies, prompt substitution, hooks, templates, and multi-agent workflows | `npx skills add FnSK4R17s/datascience-skills-factory --skill sandcastle` |
| [voicebox](skills/voicebox/) | Local-first AI voice studio — TTS, voice cloning, dictation, and MCP server for agent voice I/O. Engines, voice profiles, personalities, transcription, stories editor, GPU acceleration, and deployment | `npx skills add FnSK4R17s/datascience-skills-factory --skill voicebox` |

## Third-Party Skills

Excellent skills from the community that are worth installing alongside ours.
Each has a dedicated folder under `skills/` with a README and branding, but
the actual skill code lives in the third-party repo — install from there.

| Skill | What it does | Install |
|-------|-------------|---------|
| [opentui](skills/opentui/) | Build rich terminal UIs on a native Zig core — flexbox layout, React/Solid bindings, animation, keyboard management. By [Anomaly](https://anomaly.co) | `npx skills add anomalyco/opentui --skill opentui --global` |

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
| [mattpocock/skills — grill-with-docs](https://github.com/mattpocock/skills/tree/main/skills/engineering/grill-with-docs) (MIT) | A relentless interview to sharpen a plan or design, which also creates docs (ADRs and glossary) as it goes | Upstream — [skills/engineering/grill-with-docs/](https://github.com/mattpocock/skills/tree/main/skills/engineering/grill-with-docs) |
| [mattpocock/skills — handoff](https://github.com/mattpocock/skills/tree/main/skills/productivity/handoff) (MIT) | Compact the current conversation into a handoff document so another agent can continue the work, with a suggested-skills section and secret redaction | Upstream — [skills/productivity/handoff/](https://github.com/mattpocock/skills/tree/main/skills/productivity/handoff) |
| [mattpocock/skills — teach](https://github.com/mattpocock/skills/tree/main/skills/productivity/teach) (MIT) | Teach the user a new skill or concept over multiple sessions, using the current directory as a stateful teaching workspace | Upstream — [skills/productivity/teach/](https://github.com/mattpocock/skills/tree/main/skills/productivity/teach) |

Found a skill we should learn from? Open a PR adding the row.
