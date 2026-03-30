# Data Science Skills Factory

Skills for AI coding agents. Built for Claude Code, compatible with any agent that reads SKILL.md files.

Install into your project:

```bash
npx skills add FnSK4R17s/datascience-skills-factory
```

## Skills

| Skill | Description |
|-------|-------------|
| [langfuse-tracing](skills/langfuse-tracing/) | Instrument LLM apps with Langfuse v4 — tracing, debugging, cost tracking, prompt management, evaluation |

## Skill Structure

Each skill is a self-contained directory:

```
skills/<skill-name>/
├── SKILL.md          # Instructions (loaded when skill triggers)
├── references/       # Deep-dive docs (loaded on demand)
├── scripts/          # Executable utilities (run, not loaded into context)
└── assets/           # Code templates and boilerplate
```

## Contributing

Add a new skill:

1. Create `skills/<skill-name>/SKILL.md` with YAML frontmatter (`name`, `description`)
2. Add `references/` for detailed patterns (keep each file under 300 lines)
3. Add `scripts/` for executable utilities
4. Add `assets/` for code templates
5. PR it
