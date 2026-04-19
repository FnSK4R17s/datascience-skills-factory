<p align="center">
  <img src="logo.png" alt="repo-best-practices" height="88">
</p>

<h1 align="center">repo-best-practices</h1>

<p align="center">
  <strong>Repo-level conventions, anti-patterns, and skill-extraction prompts for AI-agent-driven projects.</strong><br>
  <sub>Part of <a href="../../">Data Science Skills Factory</a></sub>
</p>

---

Bootstrap a `CLAUDE.md` (symlinked to `AGENTS.md`) and an `ANTIPATTERNS.md`,
then keep them alive: log every user correction as a structured anti-pattern
and surface repeated tasks as candidates for skill + subagent extraction.

## What This Skill Does

| Trigger | Action |
|---------|--------|
| Repo init / "set up CLAUDE.md" | Run `BOOTSTRAP.md` — creates `CLAUDE.md`, symlinks `AGENTS.md → CLAUDE.md`, creates `ANTIPATTERNS.md`, optionally installs SessionStart hook |
| User corrects agent ("don't do X again", "always Y") | Append entry to `ANTIPATTERNS.md` via `scripts/log-antipattern.sh` |
| User repeats a multi-step task ≥2 times | Suggest lifting it into a skill (+ subagent for unattended monotonous work) |

## Why CLAUDE.md ↔ AGENTS.md Symlink

Different agents look for different filenames. Claude Code reads `CLAUDE.md`,
some tools read `AGENTS.md`. A symlink means one source of truth, no drift.

## Why ANTIPATTERNS.md (vs. cramming it into CLAUDE.md)

- **Progressive disclosure** — `CLAUDE.md` stays short and is loaded every
  session; `ANTIPATTERNS.md` is read on demand by the agent (or auto-injected
  via the optional SessionStart hook).
- **Append-only** — date-stamped, newest-first. Easy to audit and prune.
- **Machine-writeable** — `scripts/log-antipattern.sh` keeps the format
  consistent without the agent having to free-form edit.

## Optional Hook

`scripts/install-hook.sh` adds a `SessionStart` entry to
`<repo>/.claude/settings.json` that injects the top N anti-patterns as a
system reminder at session start. Off by default — opt in during bootstrap.
See [`references/hook-config.md`](references/hook-config.md).

## Installation

```bash
npx skills add FnSK4R17s/datascience-skills-factory --skill repo-best-practices
```

Then invoke once per repo to bootstrap:

```
/repo-best-practices
```

(Or follow `BOOTSTRAP.md` manually.)

## File Structure

```
repo-best-practices/
├── SKILL.md                          # Runtime trigger logic
├── BOOTSTRAP.md                      # First-run setup flow
├── README.md                         # This file
├── assets/
│   ├── CLAUDE.md                     # Repo-level instruction template
│   └── ANTIPATTERNS.md               # Empty anti-pattern file template
├── scripts/
│   ├── bootstrap.sh                  # Creates files + symlink
│   ├── log-antipattern.sh            # Appends a new anti-pattern
│   ├── load-antipatterns.sh          # SessionStart hook (optional)
│   └── install-hook.sh               # Merges hook into .claude/settings.json
└── references/
    ├── antipattern-format.md         # Entry format + good/bad examples
    ├── skill-extraction.md           # When and how to lift a task into a skill
    └── hook-config.md                # SessionStart hook details
```

## Pairs Well With

- [`skill-creator`](https://github.com/anthropics/skills) — invoke when
  extracting a repeated task into a skill.
- [`plan-feature`](../plan-feature/) — `CLAUDE.md` and `plan/PLAN.md` cover
  different time horizons (conventions vs. backlog).
- [`auto-format`](../auto-format/) — another PostToolUse hook in the same
  `.claude/settings.json`. The install scripts merge cleanly.
