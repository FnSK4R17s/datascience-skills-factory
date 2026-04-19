# <PROJECT_NAME> — Agent Instructions

> Single source of agent conventions for this repo. `AGENTS.md` is a symlink to
> this file — both filenames resolve here.

## Project summary

<One paragraph: what this repo is, primary language(s), entry point, how to run.>

## Conventions

- **Formatting:** <e.g., ruff for Python, prettier for JS/TS>
- **Commits:** <e.g., Conventional Commits, ≤50 char subject, body for "why">
- **Branches:** <e.g., `main` is the trunk; feature branches via `feat/<slug>`>
- **Tests:** <e.g., `pytest` / `npm test` — must pass before commit>
- **Other:** <add as needed>

## Anti-patterns

Read [ANTIPATTERNS.md](ANTIPATTERNS.md) before starting non-trivial work in this
repo. The file is append-only — newest entries first. Each entry describes a
mistake the agent has previously made and the correct approach.

When the user corrects you, append a new entry via:

```bash
${CLAUDE_SKILL_DIR}/scripts/log-antipattern.sh "<one-line summary>" "<correct approach>"
```

(Requires the `repo-best-practices` skill.)

## Repeated-task candidates

Tasks the user has requested multiple times that may warrant lifting into a
skill or subagent. When deferred, log here so the next session sees them.

<!-- Format: -->
<!-- - **<task name>** — requested <N> times. Last seen: <YYYY-MM-DD>. Notes: <…> -->
