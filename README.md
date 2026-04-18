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
| [factory-branding](skills/factory-branding/) | Generate branded logos for skills using Fluent 3D emoji composition — base mark + suffix, transparent PNGs via Pillow | `npx skills add FnSK4R17s/datascience-skills-factory --skill factory-branding` |

## Skill Structure

Each skill follows progressive disclosure — minimal context cost, deep references on demand:

```
skills/<skill-name>/
├── SKILL.md          # Decision tree (~100 lines, loaded when skill triggers)
├── references/       # Deep-dive docs (loaded on demand, <300 lines each)
├── scripts/          # Executable utilities (run, not loaded into context)
└── assets/           # Code templates and boilerplate
```

## Contributing

1. Create `skills/<skill-name>/SKILL.md` with YAML frontmatter (`name`, `description`)
2. Add `references/` for detailed patterns
3. Add `scripts/` for executable utilities
4. Add `assets/` for code templates
5. PR it
