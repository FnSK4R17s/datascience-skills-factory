---
name: codespell
description: >
  Detect and fix typos in source code, docs, and commit messages using the
  codespell CLI. Sets up config, a PostToolUse hook that auto-fixes on every
  file write, and a pre-commit hook that blocks typos at commit time. Use
  when the user wants spell-checking for a repo, mentions codespell, sees
  typos in variable names or docs, or asks to wire typo-detection into CI.
  Triggers on: "codespell", "spell check", "fix typos", "setup codespell",
  "pre-commit codespell".
---

# codespell skill

Detect and fix typos in code + docs using `codespell`. Wire it up in three
places so typos never ship:

1. **Slash command `/codespell`** — one-shot sweep on demand.
2. **PostToolUse hook** — auto-fix on every Claude file write.
3. **pre-commit hook** — block typos at commit time (installed via the
   [pre-commit](https://pre-commit.com) package).

All three reuse the same `.codespellrc` + `.codespell-ignore-words.txt`
config pair, so rules stay consistent.

## Licensing note

`codespell` is **GPL-2.0-only**. Invoked as a CLI subprocess (which is
all three integrations below do), its copyleft obligations do **not**
propagate to your code — CLI use is not linking. Keep it in a dev-only
dependency group (`requirements-dev.txt`, `[dependency-groups.dev]`,
`devDependencies`) so it never ships with a prod install. Do **not**
import `codespell` as a Python library.

## Decision tree

### 1. Detect what the project needs

- Any source tree → needs `/codespell` + PostToolUse hook.
- Project has a `.pre-commit-config.yaml` or the user wants commit-time
  enforcement → also wire a pre-commit hook.

### 2. Install `codespell`

Run `scripts/install-codespell.sh`. Prefers `uv tool install`, falls
back to `pipx`, then `pip install --user`.

### 3. Generate config (if missing)

Copy from `assets/` to the project root, only if the file is absent:

- `.codespellrc` — main config (skip globs, ignore lists, check-file
  flags).
- `.codespell-ignore-words.txt` — one lowercased word per line.
  Pre-seeded with common false positives (`nd`, `ba`, `fo`, `ue`,
  `crate`, …). Extend as needed.

Show the user the generated files and the entries seeded, and let them
adjust before committing.

### 4. Wire the PostToolUse hook

Register `scripts/codespell-hook.sh` for `Edit|Write` tool events.
Merge with existing hooks — do not overwrite. Example snippet:

```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Edit|Write",
        "hooks": [
          { "type": "command",
            "command": "${CLAUDE_SKILL_DIR}/scripts/codespell-hook.sh" }
        ]
      }
    ]
  }
}
```

The hook:
- Reads `tool_input.file_path` from stdin JSON.
- Runs `codespell --write-changes --quiet-level=2` on that one file,
  scoped to the repo's `.codespellrc`.
- Exits 0 always — a typo fix must never block an edit.

### 5. Wire the pre-commit hook

If the repo has a `.pre-commit-config.yaml`, append the codespell entry
from `assets/pre-commit-snippet.yaml`. If the file does not exist,
create it from that snippet. Then run:

```bash
pre-commit install
```

so the hook runs on every `git commit`. If `pre-commit` is not
installed, `scripts/install-codespell.sh --pre-commit` will install it.

The pre-commit entry points at the upstream `codespell-project/codespell`
mirror and reuses the repo's `.codespellrc` by default. It is set to
report (not auto-fix) at commit time — a failing commit forces a
deliberate `codespell -w` run before retry.

### 6. Verify

1. Write a file containing a deliberate typo (`teh` / `recieve`).
2. Confirm the PostToolUse hook rewrites it.
3. Stage + attempt to commit a file with a remaining typo; confirm
   pre-commit blocks.
4. Run `/codespell` manually and confirm clean output.

Report: installed version, config files written, hooks wired, any
existing typos surfaced from the initial sweep.

## Slash-command behavior (`/codespell`)

When invoked directly, prefer the repo's `.codespellrc`. Default action:
scan the whole tree, report counts grouped by file, and ask before
auto-fixing (`codespell -w`). If the user passes a path, scope to that
path. If the user passes `--fix`, skip the confirmation and apply
`-w` directly.

## Extending the ignore list

See [references/ignore-patterns.md](references/ignore-patterns.md) for:
- how `--ignore-words-list` (inline) differs from `--ignore-words` (file),
- scoped ignores via `# codespell:ignore` inline comments,
- common false-positive domains (ML jargon, chemistry, hashes, Base64
  blobs, legal text).

## Additional resources

- `scripts/codespell-hook.sh` — PostToolUse hook, runs after every Edit/Write.
- `scripts/install-codespell.sh` — installer (codespell + optional pre-commit).
- `assets/.codespellrc` — config template.
- `assets/.codespell-ignore-words.txt` — ignore-words template.
- `assets/pre-commit-snippet.yaml` — pre-commit hook entry.
- `references/ignore-patterns.md` — managing false positives.
