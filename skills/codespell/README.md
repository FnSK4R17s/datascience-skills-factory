<p align="center">
  <img src="logo.png" alt="codespell" height="88">
</p>

<h1 align="center">codespell</h1>

<p align="center">
  <strong>Typo-free source code, automatically.</strong><br>
  <sub>Part of <a href="../../">Data Science Skills Factory</a></sub>
</p>

---

Wires the [codespell](https://github.com/codespell-project/codespell) CLI into three layers so typos never reach a commit:

1. **Slash command `/codespell`** — run a sweep on demand.
2. **Claude PostToolUse hook** — auto-fix typos on every file write.
3. **pre-commit hook** (via the [pre-commit](https://pre-commit.com) package) — block typos at commit time.

All three share one config pair (`.codespellrc` + `.codespell-ignore-words.txt`), so rules stay consistent across the developer loop.

## Installation

```bash
npx skills add FnSK4R17s/datascience-skills-factory --skill codespell
```

Or invoke directly if the skill is already loaded:

```
/codespell
```

Claude will detect the repo, install `codespell` (and optionally `pre-commit`), generate config if absent, wire the PostToolUse hook, and run an initial sweep.

## Licensing

`codespell` ships under **GPL-2.0-only**. Invoked only as a CLI subprocess (all three integrations below do this), it does not propagate copyleft obligations to your code. Keep it in a dev-only dependency group — never import `codespell` as a library.

## How it works

### Setup (`/codespell`)

1. **Detect** whether the repo wants just the sweep or also a pre-commit hook (via the presence of `.pre-commit-config.yaml` or user request).
2. **Install** `codespell` via `uv tool install` (fallback: `pipx`, then `pip --user`). Optionally install `pre-commit` too.
3. **Generate** `.codespellrc` and `.codespell-ignore-words.txt` from the bundled templates if missing.
4. **Register** a `PostToolUse` hook pointing at `scripts/codespell-hook.sh`.
5. **Wire** a pre-commit entry from `assets/pre-commit-snippet.yaml` and run `pre-commit install` so the hook fires on every `git commit`.

### Runtime (`codespell-hook.sh`)

No LLM involvement. The hook:

- Reads the edited file path from the tool event JSON.
- Skips binary extensions and missing files.
- Runs `codespell --write-changes --quiet-level=2` scoped to the file, from the repo root so `.codespellrc` applies.
- Always exits 0, so a flaky spell-check never blocks an edit.

### pre-commit integration

The bundled snippet pins `codespell-project/codespell` at `v2.4.1` and reuses the repo's `.codespellrc`. It runs in **report** mode at commit time — failing commits force a deliberate `codespell -w` before retry, which makes the fix auditable.

## File structure

```
codespell/
├── SKILL.md                             # Skill entry point (decision tree for Claude)
├── README.md                            # This file
├── logo.png                             # 🏭🧙‍♂️
├── scripts/
│   ├── codespell-hook.sh                # PostToolUse hook — runs after every Edit/Write
│   └── install-codespell.sh             # Installs codespell (and optionally pre-commit)
├── assets/
│   ├── .codespellrc                     # Main config template
│   ├── .codespell-ignore-words.txt      # Ignore-list template, pre-seeded
│   └── pre-commit-snippet.yaml          # Paste into .pre-commit-config.yaml
└── references/
    └── ignore-patterns.md               # Managing false positives (inline, file, regex, skip)
```

## Extending the ignore list

See [references/ignore-patterns.md](references/ignore-patterns.md) for the five mechanisms (inline comment, CLI flag, ignore-words file, skip glob, ignore-regex) and common false-positive domains (ML jargon, Rust `crate`, hashes, legal text).
