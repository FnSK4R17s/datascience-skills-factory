# BOOTSTRAP.md — First-Time `repo-best-practices` Setup

One-time setup per repository. After these steps, day-to-day work runs through
`SKILL.md` (anti-pattern logging, skill-extraction prompts).

## Steps

### 1. Confirm target repo root

Files land at the **repo root** — same dir as `.git`, `package.json`,
`pyproject.toml`, etc. Confirm with the user before writing.

### 2. Check what already exists

```bash
ls CLAUDE.md AGENTS.md ANTIPATTERNS.md 2>/dev/null
```

Decision matrix:

| State | Action |
|-------|--------|
| None exist | Run `scripts/bootstrap.sh` — creates all three. |
| `CLAUDE.md` exists, no `AGENTS.md` | Add symlink only: `ln -s CLAUDE.md AGENTS.md`. Append the "Anti-patterns" section to `CLAUDE.md` (see step 4). |
| `AGENTS.md` exists, no `CLAUDE.md` | Symlink the other way: `ln -s AGENTS.md CLAUDE.md`. Same content section append. |
| Both exist as separate files | **Stop.** Ask the user which is canonical, then symlink. Do not silently merge or delete. |
| `ANTIPATTERNS.md` exists | Leave it. Skip to step 5. |

### 3. Run the bootstrap script (if applicable)

```bash
${CLAUDE_SKILL_DIR}/scripts/bootstrap.sh
```

The script:

1. Copies `assets/CLAUDE.md` → `<repo-root>/CLAUDE.md` (skips if file exists).
2. Copies `assets/ANTIPATTERNS.md` → `<repo-root>/ANTIPATTERNS.md` (skips if exists).
3. Creates `AGENTS.md → CLAUDE.md` symlink (skips if `AGENTS.md` exists).
4. Reports what was created and what was skipped.

### 4. Customize `CLAUDE.md`

Open `CLAUDE.md` and ask the user about the four template sections:

1. **Project summary** — one paragraph: what this repo is, primary language(s), entry point.
2. **Conventions** — formatting, commit style, branch naming, test command.
3. **Anti-patterns** — leave empty; populated by `scripts/log-antipattern.sh`.
4. **Repeated-task candidates** — leave empty; populated when the user defers a skill suggestion.

Fill in (1) and (2) interactively. Leave (3) and (4) as the empty headers from the template.

### 5. Optional — install the SessionStart hook

Ask the user:

> "Want anti-patterns surfaced automatically at the start of every session?
> Tradeoff: guaranteed visibility, but they cost context tokens every turn.
> Default: no — agents will read `ANTIPATTERNS.md` on demand instead."

If yes:

```bash
${CLAUDE_SKILL_DIR}/scripts/install-hook.sh
```

The script merges a `SessionStart` hook into `<repo-root>/.claude/settings.json`
(creates the file if missing) that runs `scripts/load-antipatterns.sh` to inject
the top 10 anti-patterns as a system reminder. See
[references/hook-config.md](references/hook-config.md) for the exact JSON.

### 6. Verify

Confirm:

- `CLAUDE.md` exists and is non-empty.
- `AGENTS.md` resolves to `CLAUDE.md` (`readlink AGENTS.md` → `CLAUDE.md`).
- `ANTIPATTERNS.md` exists with the empty template header.
- (If hook installed) `.claude/settings.json` has the SessionStart entry.

Show the user the resulting `CLAUDE.md` and ask for a final OK.

### 7. Optional — commit

Ask whether to commit. Suggested message:

```
docs: add CLAUDE.md, AGENTS.md symlink, and ANTIPATTERNS.md

Establish repo-level agent conventions via repo-best-practices skill.
```

Do **not** auto-commit — let the user trigger it.

## After Bootstrap

Delete or ignore this file. Day-to-day operations live in `SKILL.md`:
- Logging new anti-patterns (`scripts/log-antipattern.sh`)
- Surfacing repeated-task → skill candidates
- Reading `ANTIPATTERNS.md` on demand
