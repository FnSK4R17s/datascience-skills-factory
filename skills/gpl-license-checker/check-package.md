# How to check a package's license

This file tells you what to check and where to look. It does not dictate
how. Solve it with whatever tool you have at hand — `curl | jq`, a Python
snippet, an HTTP client in your runtime, a dedicated ecosystem linter,
whatever fits the moment and the constraints.

## The problem

For a given `(ecosystem, name[, version])` triple, return one of
**ALLOW**, **WARN**, **DENY**, or **ERROR** with the SPDX identifier and
the class it falls under. Block downstream dep-addition on `DENY`.

## Where to look

| Ecosystem | Authoritative source |
|-----------|----------------------|
| `pypi` | `https://pypi.org/pypi/<name>/json` (or `.../pypi/<name>/<version>/json`) |
| `npm` | `https://registry.npmjs.org/<name>` |
| `crates` | `https://crates.io/api/v1/crates/<name>` |
| `github` | `https://api.github.com/repos/<owner>/<repo>/license` |
| `go` | resolve to a hosting site (usually `github.com/<owner>/<repo>`) then use the host's license API |

If the native registry returns no usable license, fall back to the
repository host (almost always GitHub). `$GITHUB_TOKEN` raises the
GitHub rate limit from 60 req/h to 5000 req/h.

## What to read

In each response body, the license can live in multiple fields with
different shapes. Read [references/known-quirks.md](references/known-quirks.md)
for the empirical catalogue — which fields, in what order, and the
weird-string cases you'll hit on real packages (filename in the license
field, full license text pasted in, legacy GNU notation, dual-licenses).

The policy for classifying a canonical SPDX id is in
[references/policy.md](references/policy.md). That file is the source of
truth — extend it when a new license shows up.

## Verdict classes

| Bucket | Examples | Verdict |
|--------|----------|---------|
| Permissive | MIT, Apache-2.0, BSD-*, ISC, CC0, PSF, Zlib | ALLOW |
| Weak / lesser copyleft | MPL-2.0, LGPL-*, EPL-2.0, CDDL | WARN |
| Strong / network copyleft | GPL-*, AGPL-*, SSPL | DENY |
| Source-available | BUSL-1.1, Elastic-2.0, Commons-Clause | DENY |
| Docs copyleft | GFDL-* | DENY |
| Share-alike | CC-BY-SA-* | DENY |
| Missing / unresolvable | NOASSERTION, UNKNOWN, NONE, no-match | DENY |

WARN means safe for dynamic import and standard `pip` / `npm` / `cargo`
install. Vendoring, forking, or modifying a WARN-class library converts
it to DENY for your distribution — the library's copyleft obligations
attach to your fork. The skill cannot tell which mode you're in; the
human using the WARN verdict decides.

Unknown SPDX id → DENY. Absence of a match = absence of a grant.

## Project-local overrides

If a downstream repo has a legitimate exception (e.g. a GPL tool invoked
only as a subprocess, never imported), it carries its own
`license-overrides.yml` next to the manifest:

```yaml
overrides:
  - package: somegpl-tool
    ecosystem: pypi
    justification: "Invoked as subprocess only; not linked or imported."
    approved_by: <name>
    spdx: GPL-3.0
```

An override downgrades DENY to OVERRIDE (exit 0). Keep the file next to
the manifest it covers — the audit trail travels with the repo.

## Exit-code / output contract

If you expose this as a CLI, the convention is:

| Verdict | Exit code |
|---------|-----------|
| ALLOW   | 0 |
| WARN    | 1 |
| DENY    | 2 |
| ERROR   | 3 |

and one tab-separated line on stdout:

```
<VERDICT>\t<name>\t<spdx>\t<class>\t<note?>
```

Tab-separated so it pipes cleanly into `awk` / `cut`, and so a bulk
scanner can exit with the worst verdict across all packages. The CLI
shape is a suggestion; honour it if you expect to compose with other
tools, ignore it otherwise.

## Worked examples

Ground-truth answers for spot-checking that whatever you build gets the
tricky cases right.

| Input | Expected | What makes it tricky |
|-------|----------|----------------------|
| `pypi bashlex` | DENY, GPL-3.0-or-later | Legacy `GPLv3+` in the `license` field — needs normalization |
| `pypi langgraph` | ALLOW, MIT | Clean metadata, no surprises |
| `pypi python-telegram-bot` | WARN, LGPL-3.0-only | PyPI says LGPL; GitHub says GPL (repo has both `LICENSE` and `LICENSE.lesser`); library is actually LGPL |
| `pypi nemoguardrails` | ALLOW, Apache-2.0 | `license` field is literally `"LICENSE.md"` (filename); recovered from classifiers |
| `pypi detect-secrets` | ALLOW, Apache-2.0 | Clean |
| `crates serde` | ALLOW, MIT (from `MIT OR Apache-2.0`) | Dual-licensed; most permissive half wins |
| `github idank/bashlex` | DENY, GPL-3.0 | Direct GitHub SPDX, no normalization |
| `npm express` | ALLOW, MIT | Clean |

## Bulk scanning

For a whole manifest, existing ecosystem tools are already maintained
and robust. Pipe their output through [references/policy.md](references/policy.md):

- Python: `pip-licenses --format=json`
- npm: `license-checker --production --json`
- Rust: `cargo deny check licenses`
- Go: `go-licenses report ./...`

Don't reinvent the parsers. The policy file is the part that's yours.

## What this skill does not try to answer

- Transitive-dep resolution — use the bulk tools above.
- Replacement-library suggestions — the prose in SKILL.md links to
  options but does not algorithmically recommend.
- Vendor-vs-import inference — WARN surfaces the question; the human
  answers it.
