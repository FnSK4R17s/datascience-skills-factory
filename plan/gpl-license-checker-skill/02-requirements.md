# gpl-license-checker — Requirements

## Must

1. Given `<ecosystem> <package>`, return one of `ALLOW | WARN | DENY | ERROR`
   with the SPDX identifier and a human-readable class.
2. Support ecosystems: `pypi`, `npm`, `crates`, `github`.
3. Scan a manifest file (`pyproject.toml`, `requirements*.txt`,
   `package.json`, `Cargo.toml`, `go.mod`) and report per-dep verdicts.
4. Correctly classify:
   - `bashlex` (pypi) → DENY (GPL-3.0-or-later)
   - `python-telegram-bot` (pypi) → WARN (LGPL-3.0-only)
   - `nemoguardrails` (pypi, license field garbage) → ALLOW via classifier fallback
   - `serde` (crates, dual-licensed) → ALLOW picking the MIT half
5. Exit code maps to verdict severity (0 / 1 / 2 / 3) so the tool
   composes into pipelines and hooks.
6. Zero external runtime deps. Python stdlib only.

## Should

- Fallback to GitHub repo LICENSE lookup when the registry metadata is
  empty or garbage (common on older PyPI uploads).
- Honor `GITHUB_TOKEN` for the higher rate limit.
- Handle SPDX OR expressions — pick the most permissive.
- Ship a PreToolUse hook script for Claude Code that blocks manifest
  writes containing new DENY-class deps.
- Support a per-project `license-overrides.yml` for legitimate
  exceptions (e.g. GPL tool invoked as subprocess only).

## Won't

- Transitive dep resolution. Out of scope — use `pip-licenses`,
  `license-checker`, `cargo-deny` for full SBOM.
- Rewriting your code. The skill reports; humans replace.
- Suggesting replacement libraries. Link to options in the SKILL.md
  prose, don't try to be an AI librarian.

## Non-goals

- SPDX expression parser correctness for pathological cases
  (`(GPL-2.0 OR MIT) AND LGPL-3.0`). Simple `OR` is enough.
- Caching. Registry lookups are fast enough and freshness matters.
