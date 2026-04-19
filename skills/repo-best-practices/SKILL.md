---
name: repo-best-practices
description: >
  Bootstrap and maintain repo-level conventions for AI-agent-driven projects.
  Creates `CLAUDE.md` (symlinked to `AGENTS.md`) and `ANTIPATTERNS.md`, installs
  optional hooks for progressive anti-pattern loading, captures user corrections
  as anti-patterns, and watches for repeated user requests that should be lifted
  into reusable skills + subagents. Use when initializing a new repo, when the
  user corrects an agent mistake ("don't do X again", "always do Y"), or when
  the same multi-step task has been requested 2+ times in a session.
  Triggers on: "set up repo conventions", "init CLAUDE.md", "log this anti-pattern",
  "remember this", "we keep doing this", "make this a skill", "repo best practices".
---

# Repo Best Practices

Captures repo-level conventions, anti-patterns, and skill-extraction candidates
into durable files agents (and humans) read every session.

## Three Triggers

### A. Repo init / first-run setup

User says "set up CLAUDE.md", "init repo conventions", or starts a fresh repo
without any agent-instruction file.

→ Run `BOOTSTRAP.md`. It creates `CLAUDE.md`, symlinks `AGENTS.md → CLAUDE.md`,
creates an empty `ANTIPATTERNS.md`, and offers to install the SessionStart hook.

### B. User corrects agent mistake

Signals (any of):
- "don't do X again" / "never X" / "always Y instead"
- "you keep making this mistake"
- An explicit `/antipattern <description>` invocation
- User reverts a change you just made and explains why

→ Append a new entry to `ANTIPATTERNS.md` using the format in
[references/antipattern-format.md](references/antipattern-format.md). Run:

```bash
${CLAUDE_SKILL_DIR}/scripts/log-antipattern.sh "<one-line summary>" "<correct approach>"
```

The script appends a dated entry under `## Anti-patterns` and keeps the file
sorted newest-first.

After logging, briefly confirm: "Logged to `ANTIPATTERNS.md` — won't repeat."
Do **not** apologize at length or restate the mistake.

### C. Repeated task → skill candidate

If the user has asked for the same multi-step task **2+ times** in a session
(or you notice a recurring pattern across sessions in the same repo), surface it:

> "I've done `<task>` `<N>` times now — want to lift this into a skill?
> A skill + subagent combo would let you fire it with `/<skill-name>` and
> have it run unattended. See [references/skill-extraction.md](references/skill-extraction.md)
> for what that looks like."

If the user says yes, hand off to the `skill-creator` skill (or scaffold
manually). Log the candidate in `CLAUDE.md` under
`## Repeated-task candidates` either way — even if the user defers, the next
session's agent will see it.

## File Layout (after bootstrap)

```
<repo-root>/
├── CLAUDE.md           # Repo-level agent instructions (read every session)
├── AGENTS.md → CLAUDE.md   # Symlink for agents that look for AGENTS.md
└── ANTIPATTERNS.md     # Append-only list of "don't do this" entries
```

`CLAUDE.md` references `ANTIPATTERNS.md` so agents read it on demand
(progressive disclosure — full file is not loaded into every turn unless the
SessionStart hook is installed).

## Optional Hook: SessionStart anti-pattern loader

If the user wants anti-patterns surfaced **automatically** at session start
(rather than only when the agent reads the file), install the SessionStart hook
from `scripts/load-antipatterns.sh` via `BOOTSTRAP.md` step 5. The hook reads
the top N entries (default: 10) and injects them as a system reminder.

Tradeoff: guaranteed visibility vs. constant context cost. Default is **off** —
let the user opt in.

## Additional Resources

- `BOOTSTRAP.md` — first-time setup flow
- `assets/CLAUDE.md` — repo-level instruction template
- `assets/ANTIPATTERNS.md` — empty anti-pattern file template
- `scripts/bootstrap.sh` — creates files + symlink in one shot
- `scripts/log-antipattern.sh` — appends a new anti-pattern entry
- `scripts/load-antipatterns.sh` — SessionStart hook (optional)
- `scripts/install-hook.sh` — adds the SessionStart hook to `.claude/settings.json`
- `references/antipattern-format.md` — exact entry format + good/bad examples
- `references/skill-extraction.md` — when and how to lift repeated tasks into a skill
- `references/hook-config.md` — settings.json snippets for the optional hook
