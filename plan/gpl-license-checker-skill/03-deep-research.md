# gpl-license-checker — Deep Research

## Key findings

### PyPI license metadata is unreliable

Three competing fields:
1. `license_expression` — PEP 639, SPDX compliant, reliable but new (PyPI
   accepts since 2024).
2. `license` — free-form string. Contents observed: valid SPDX, legacy
   `GPLv3+`, literal `"LICENSE.md"` (the filename), full license text dumps,
   `"UNKNOWN"`, empty.
3. `classifiers` — Trove classifiers like `License :: OSI Approved :: MIT
   License`. More reliable than `license` in practice — uploaders tend to
   set the classifier correctly even when they botch the `license` field.

**Design choice:** prefer `license_expression` → free-form `license` →
classifier. If free-form doesn't normalize to a known SPDX, skip it and
use classifiers. GitHub fallback is last resort.

### npm license field shapes

Three historical shapes:
- `"license": "MIT"` — modern
- `"license": {"type": "MIT", "url": "..."}` — legacy, still common
- `"licenses": [{"type": "MIT"}, ...]` — deprecated, rare but extant

Handled the first two; the third is rare enough to defer (skip → fallback
to GitHub).

### crates.io returns SPDX expressions as-is

`serde` returns `"MIT OR Apache-2.0"`. SPDX expression parser pulls out
parts and picks the most permissive. Good enough.

### GitHub API and `NOASSERTION`

GitHub matches LICENSE files against a known-template corpus. If the file
is a custom variant, it returns `"license": {"spdx_id": "NOASSERTION"}`.
Treat as DENY — absence of a clear license means no grant.

Rate limit: 60 req/hour unauthenticated. `GITHUB_TOKEN` env var bumps to
5000/hour. Important for scanning large manifests.

### LGPL is the nuanced case

LGPL-3.0 is WARN not DENY because:
- **Dynamic import** (`import foo`, `require('foo')`) → separate work.
  Your code stays under its own license.
- **Vendor / fork / modify** → combined work. Your fork falls under LGPL.

The skill can't tell which mode you're in. It surfaces WARN with a note.
The human decides.

### Legacy non-SPDX strings

Common bogus strings encountered:
- `GPLv3+`, `GPLv2`, `LGPLv2.1`, `AGPLv3+` — informal GNU notation
- `Apache 2.0`, `Apache License 2.0`, `ASL 2.0` — Apache variants
- `MIT License`, `New BSD`, `BSD` — free-form
- `Mozilla Public License 2.0 (MPL 2.0)` — ATG parenthesized

Mapped to canonical SPDX in `_NON_SPDX_ALIASES`. The list grows as we
encounter new cases — treat as a living denylist of informal strings
to canonicalize.

### "License file" false positives

PyPI packages sometimes put `"LICENSE.md"` (the filename) or a path like
`"./LICENSE"` in the license field. The normalizer detects this by: ends
with `.md/.txt/.rst`, starts with `license`, contains newline, or >120 chars.
When normalization returns empty, the caller falls through to classifier
and then GitHub.

## Risks

1. **SPDX policy drift.** New SPDX IDs (e.g. `BlueOak-1.0.0`, `PolyForm-*`)
   appear. Keep `policy.md` as canonical source, scripts parse it — easy to
   update without code changes.
2. **False-negative on a subtly denied package.** The policy list is the
   audit trail — expand it when a new copyleft or source-available license
   shows up.
3. **Hook blocks a legitimate write.** The override file
   (`license-overrides.yml`) is the escape hatch. Keep justifications
   honest.

## Decision log

- Python stdlib only → no `requests` / `tomli` imports. Use
  `urllib.request` + `tomllib` (3.11+) with `tomli` fallback.
- Policy lives in markdown, not YAML/JSON → humans edit it, scripts parse
  the fenced code blocks. Dogfoods the allow/warn/deny sections as the
  audit trail.
- DENY on unknown → conservative default. If the script can't tell,
  assume contamination risk.
