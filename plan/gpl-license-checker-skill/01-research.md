# gpl-license-checker — Research

## Problem observed

CommandClaw shipped with a `bashlex>=0.18` dep (GPL-3.0). Nobody caught it at
add-time. It was flagged later during a license audit of the 8 libraries in
`plan/PLAN.md` — by then the dep had been in `pyproject.toml` for weeks and
referenced in docs, whitepapers, and architecture diagrams. Rip-out cost: one
guardrail function lost its AST wrapper-bypass detection (now regex-only),
plus a tracking issue, plus doc sweeps.

## What exists today

- No license check at dep-add time in any repo in the ecosystem.
- GitHub shows SPDX license on the repo landing page, but it's one extra
  click that nobody makes when running `pip install foo`.
- The broader ecosystem (CommandClaw vault + skills-factory + commandclaw-mcp
  + …) ships under mixed MIT/Apache-2.0. One GPL dep contaminates any repo
  that imports it.
- `pip-licenses`, `license-checker` (npm), `cargo-deny` exist but are
  per-ecosystem, none wired to a hook, none opinionated about GPL specifically.

## Constraint

No external dep on PyPI packages for the skill itself — it must be
runnable by a fresh clone with only Python stdlib, because it's the
first thing installed in a new repo and you can't license-check the
license-checker's own deps before you have a license-checker.

## Adjacent skills

- `auto-format`: precedent for a skill that ships a PostToolUse hook per
  project; we mirror that shape (PreToolUse here).
- `repo-best-practices`: precedent for a skill that prevents mistakes at
  write-time.
