<p align="center">
  <img src="logo.png" alt="gpl-license-checker" height="88">
</p>

<h1 align="center">gpl-license-checker</h1>

<p align="center">
  <strong>Keep copyleft out of your MIT / Apache-2.0 repos.</strong><br>
  <sub>Part of <a href="../../">Data Science Skills Factory</a></sub>
</p>

---

One GPL dependency contaminates a permissive codebase. This skill gives an
agent the knowledge to catch it **before** the commit: the authoritative
sources to query, the empirical traps registry metadata will throw at it,
and an SPDX-keyed allow / warn / deny policy that produces the verdict.

The skill is a problem statement plus reference data — not an implementation.
The agent invoking it generates whatever code fits the moment (a `curl | jq`
pipeline, a short Python snippet, an ecosystem linter), consults the policy,
and returns a verdict. No 400-line utility to rot the moment PyPI changes a
field.

## Install

```bash
npx skills add FnSK4R17s/datascience-skills-factory --skill gpl-license-checker
```

## How it works

```
            ┌─────────────────────────────────────────────────┐
            │   "can I add `bashlex` to pyproject.toml?"      │
            └──────────────────────┬──────────────────────────┘
                                   ▼
              ┌──────────────────────────────────────────┐
              │   check-package.md  — problem + sources  │
              │                                          │
              │   pypi  → pypi.org/pypi/<name>/json      │
              │   npm   → registry.npmjs.org/<name>      │
              │   crates→ crates.io/api/v1/crates/<name> │
              │   github→ api.github.com/repos/.../license│
              └──────────────────────┬───────────────────┘
                                     ▼
              ┌──────────────────────────────────────────┐
              │   references/known-quirks.md             │
              │   garbage-field heuristics, legacy GNU   │
              │   notation, Trove classifier map,        │
              │   cross-source disagreement              │
              └──────────────────────┬───────────────────┘
                                     ▼
              ┌──────────────────────────────────────────┐
              │   references/policy.md                   │
              │   ALLOW / WARN / DENY SPDX lists         │
              └──────────────────────┬───────────────────┘
                                     ▼
                         VERDICT + SPDX + class
```

## Verdicts

| Bucket | Examples | Verdict |
|--------|----------|---------|
| Permissive | MIT, Apache-2.0, BSD-*, ISC, CC0, PSF, Zlib | **ALLOW** |
| Weak / lesser copyleft | MPL-2.0, LGPL-*, EPL-2.0, CDDL | **WARN** |
| Strong copyleft | GPL-*, AGPL-*, SSPL | **DENY** |
| Source-available | BUSL-1.1, Elastic-2.0, Commons-Clause | **DENY** |
| Docs copyleft | GFDL-* | **DENY** |
| Share-alike | CC-BY-SA-* | **DENY** |
| Missing / unresolvable | NOASSERTION, UNKNOWN, NONE, no match | **DENY** |

**WARN** is the LGPL escape hatch: dynamic import and standard `pip` /
`npm` / `cargo` installs stay safe; vendoring, forking, modifying, or
statically linking converts WARN → DENY.

## Ground-truth spot-checks

| Input | Expected |
|-------|----------|
| `pypi bashlex` | DENY · GPL-3.0-or-later |
| `pypi langgraph` | ALLOW · MIT |
| `pypi python-telegram-bot` | WARN · LGPL-3.0-only |
| `pypi nemoguardrails` | ALLOW · Apache-2.0 *(from classifier fallback; `license` field is the literal string `"LICENSE.md"`)* |
| `crates serde` | ALLOW · MIT · *(dual-licensed `MIT OR Apache-2.0`; most permissive wins)* |
| `github idank/bashlex` | DENY · GPL-3.0 |

## Project-local overrides

Legitimate exceptions (e.g. a GPL CLI tool invoked as a subprocess, never
imported) carry an `license-overrides.yml` next to the manifest:

```yaml
overrides:
  - package: somegpl-tool
    ecosystem: pypi
    justification: "Invoked as subprocess only; not linked or imported."
    approved_by: <name>
    spdx: GPL-3.0
```

Downgrades that package's DENY to OVERRIDE. File travels with the repo so
the audit trail stays attached to the manifest it protects.

## Layout

```
skills/gpl-license-checker/
├── SKILL.md                    trigger, verdict summary, file map
├── check-package.md            the problem, the sources, the contract
├── README.md                   this file
├── logo.png                    factory + water buffalo (GNU stand-in)
└── references/
    ├── policy.md               SPDX allow / warn / deny lists
    └── known-quirks.md         empirical metadata quirks seen in the wild
```

No scripts. No hooks. No frozen Python. The skill is durable because the
agent is smart.

## Why a water buffalo

GNU (the OS) and the gnu (the antelope) share a name and a logo. The
water buffalo is the closest-looking relative in the Unicode Fluent 3D
set — stocky, horned, gate-keeping. The mark says: "copyleft stops here
unless someone decides otherwise on purpose."
