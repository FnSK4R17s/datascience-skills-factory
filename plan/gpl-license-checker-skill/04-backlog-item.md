# gpl-license-checker

> **A license-policy guard rail that classifies every declared dep as
> ALLOW / WARN / DENY against an SPDX-keyed policy, so a permissive-licensed
> repo never silently pulls in a copyleft contaminant.**

## What changes

Today, dep files (`pyproject.toml`, `package.json`, `Cargo.toml`, `go.mod`,
`requirements*.txt`) are edited freely — a GPL-3.0 library can enter a MIT
codebase and nobody notices until a manual audit months later. **After this
skill ships, every edit to those files can (optionally) be gated by a
PreToolUse hook that queries the canonical package registry for the SPDX
identifier, classifies it against `references/policy.md`, and blocks the
write when the verdict is `DENY`.**

Independent of the hook, the skill provides two CLIs:

- `check_package.sh <ecosystem> <name> [version]` — one package, one line.
- `scan_manifest.py <path>` — full manifest, per-line verdicts.

## Touchpoints

- `skills/gpl-license-checker/SKILL.md` — trigger conditions + policy summary
- `skills/gpl-license-checker/references/policy.md` — canonical allow/warn/deny SPDX lists
- `skills/gpl-license-checker/scripts/check_package.py` — single-package lookup (PyPI, npm, crates.io, GitHub)
- `skills/gpl-license-checker/scripts/scan_manifest.py` — multi-ecosystem manifest scanner
- `skills/gpl-license-checker/scripts/hook_scan.sh` — PreToolUse hook entry point
- `README.md` — Skills table row

## Policy verdicts

- **ALLOW (exit 0):** MIT, Apache-2.0, BSD-*, ISC, CC0, Unlicense, PSF, Zlib, …
- **WARN (exit 1):** MPL-2.0, LGPL-*, EPL-2.0, CDDL-* — safe if not vendored/modified.
- **DENY (exit 2):** GPL-*, AGPL-*, SSPL, BUSL, Commons-Clause, GFDL-*, CC-BY-SA-*, NOASSERTION.

Per-project `license-overrides.yml` downgrades individual DENYs to OVERRIDE
with a written justification.

## Acceptance

- `check_package.sh pypi bashlex` returns `DENY` + exit 2.
- `check_package.sh pypi langgraph` returns `ALLOW` + exit 0.
- `check_package.sh pypi python-telegram-bot` returns `WARN` + exit 1.
- `check_package.sh pypi nemoguardrails` returns `ALLOW` + exit 0 (license field
  is garbage `"LICENSE.md"`; classifier fallback recovers it).
- `scan_manifest.py /apps/commandclaw/pyproject.toml` reports 20 deps, no DENY.
- Hook script integration: dropping a GPL dep into a watched manifest in a
  project with the PreToolUse hook installed blocks the write.
- Zero external PyPI deps. Python stdlib only.

## Status

v1 shipped. Future work: Go modproxy support (currently only GitHub-hosted
Go modules resolve), Maven `pom.xml`, pub.dev (Dart). Transitive dep
scanning deferred — out of scope per requirements.
