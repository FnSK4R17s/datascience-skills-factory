---
name: gpl-license-checker
description: >
  Block copyleft licenses (GPL, AGPL, SSPL, LGPL when vendored) from entering
  projects that ship under MIT, Apache-2.0, BSD, or other permissive licenses.
  Scans Python, Node, Rust, Go, and Java manifests; queries package registries
  for SPDX identifiers; verdicts each dep as allow, warn, or deny against a
  configurable policy. Use before adding a new dependency, when reviewing a
  PR that touches a manifest, when auditing an existing project for license
  contamination, or when the user asks about license compatibility.
  Triggers on: "license check", "GPL check", "can I use <lib>", "audit
  licenses", "license compat", "is <lib> MIT compatible", "check deps",
  "license violation".
---

# GPL License Checker

Prevent accidental inclusion of copyleft (GPL / AGPL / SSPL) or ambiguous
(LGPL, GFDL) dependencies in projects that distribute under permissive
licenses (MIT, Apache-2.0, BSD-*, ISC). One GPL dep contaminates the whole
distribution — this skill catches it before you commit.

## When to run

- **Before** editing `pyproject.toml`, `requirements*.txt`, `setup.py`, `setup.cfg`, `Pipfile`, `poetry.lock`, `package.json`, `Cargo.toml`, `go.mod`, or `pom.xml` to add a dep.
- **After** cloning a repo you plan to ship, to audit what's already in there.
- **On PR review** when the diff touches any manifest file.
- **When the user asks** "can I use `<library>`?" or "is `<library>` MIT-compatible?".

## The verdict policy

Loaded from [references/policy.md](references/policy.md). Summary:

| Class | SPDX IDs | Verdict | Rationale |
|-------|----------|---------|-----------|
| **Permissive** | `MIT`, `Apache-2.0`, `BSD-2-Clause`, `BSD-3-Clause`, `ISC`, `0BSD`, `Unlicense`, `CC0-1.0`, `PSF-2.0`, `Python-2.0`, `Zlib` | **allow** | no redistribution constraints |
| **Weak copyleft** | `MPL-2.0`, `EPL-2.0`, `CDDL-1.0` | **warn** | file-level copyleft — safe if you don't modify the library |
| **Lesser copyleft** | `LGPL-2.1`, `LGPL-2.1-or-later`, `LGPL-3.0`, `LGPL-3.0-or-later` | **warn** | dynamic import OK; **never** vendor, fork, or modify |
| **Strong copyleft** | `GPL-2.0`, `GPL-2.0-or-later`, `GPL-3.0`, `GPL-3.0-or-later`, `AGPL-3.0`, `AGPL-3.0-or-later` | **deny** | viral — contaminates your distribution |
| **Network copyleft** | `AGPL-3.0`, `SSPL-1.0`, `BUSL-1.1` | **deny** | triggers on network use, not just distribution |
| **Docs copyleft** | `GFDL-1.1`, `GFDL-1.2`, `GFDL-1.3` | **deny** | affects any doc you copy from the library |
| **Unknown / no license** | `NOASSERTION`, missing | **deny** | absence of license = no grant; assume all-rights-reserved |

## Usage

### Check one package

```bash
${CLAUDE_SKILL_DIR}/scripts/check_package.sh pypi bashlex
# -> DENY  bashlex           GPL-3.0            strong_copyleft
${CLAUDE_SKILL_DIR}/scripts/check_package.sh pypi langgraph
# -> ALLOW langgraph          MIT                permissive
${CLAUDE_SKILL_DIR}/scripts/check_package.sh pypi python-telegram-bot
# -> WARN  python-telegram-bot LGPL-3.0          lesser_copyleft  (dynamic import OK; do not vendor)
${CLAUDE_SKILL_DIR}/scripts/check_package.sh npm  express
${CLAUDE_SKILL_DIR}/scripts/check_package.sh crates serde
${CLAUDE_SKILL_DIR}/scripts/check_package.sh github idank/bashlex
```

Exit code: `0` allow, `1` warn, `2` deny, `3` lookup error. Use in shell pipelines or hooks.

### Scan a whole manifest

```bash
${CLAUDE_SKILL_DIR}/scripts/scan_manifest.py pyproject.toml
${CLAUDE_SKILL_DIR}/scripts/scan_manifest.py package.json
${CLAUDE_SKILL_DIR}/scripts/scan_manifest.py requirements.txt
${CLAUDE_SKILL_DIR}/scripts/scan_manifest.py Cargo.toml
```

Output format per line: `VERDICT <pkg> <spdx> <class>`. Exit code is the **worst** verdict across all deps (2 if any deny, 1 if any warn, 0 if all allow).

### Before adding a new dep (the 80% case)

When Claude is about to run `pip install <x>`, `uv add <x>`, `npm install <x>`, `cargo add <x>`, etc., run `check_package.sh` on it first. If the verdict is **deny**, do not add it — stop and surface the finding to the user with replacement candidates.

### Explain LGPL's two modes

LGPL gets a `warn` not a `deny` because the copyleft scope depends on **how** you use the library:

- **Dynamic import (`import foo` in Python, `require('foo')` in Node)** — separate work. Your code stays under its own license. Safe.
- **Vendor / fork / statically link / modify** — combined work. Your fork falls under LGPL. You must distribute source for the LGPL portion, allow replacement, and carry the notices.

The skill cannot infer which mode you're in. When you see a `warn` for LGPL, ask: *am I vendoring this?* If no, proceed. If yes, pick a permissive replacement.

## Integration as a PreToolUse hook (optional, opinionated)

Add to your project `.claude/settings.json`:

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Edit|Write",
        "hooks": [
          {
            "type": "command",
            "command": "${CLAUDE_SKILL_DIR}/scripts/hook_scan.sh"
          }
        ]
      }
    ]
  }
}
```

The hook inspects the file path in the tool input — if it matches a known manifest, it re-scans and blocks the write on `deny` verdict. Not installed by default; opt in per project.

## Known failure modes

1. **PyPI sometimes returns `"License: UNKNOWN"`** even for properly-licensed packages because uploaders filled the legacy `license` field instead of `classifiers`. The script falls back to classifiers, then to a GitHub lookup if a `Home-page` or `Source` URL is present.
2. **GitHub API caps at 60 req/hour unauthenticated.** Set `GITHUB_TOKEN` in the environment to get 5000 req/hour. The script honors it.
3. **Monorepos with multiple licenses.** SPDX allows expressions like `Apache-2.0 OR MIT` — the script picks the most permissive. `GPL-2.0 WITH Classpath-exception-2.0` is treated as a distinct ID (warn, not deny) — see policy.md.
4. **"NOASSERTION"** from GitHub means the repo has a LICENSE file that SPDX couldn't classify. Treat as `deny` until manually resolved — absence of a clear license means no grant.

## What this skill does NOT do

- **Does not scan transitive dependencies.** It only checks what you declare in the manifest. For full SBOM coverage, use `pip-licenses`, `license-checker` (npm), `cargo-deny`, etc., and pipe into this policy.
- **Does not rewrite your code.** It reports. You decide to replace or override.
- **Does not catch dual-licensed packages where you picked the wrong half.** Some packages are `GPL-3.0 OR Commercial` — if you pick GPL mode, you still have GPL obligations.
