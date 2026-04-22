---
name: gpl-license-checker
description: >
  Block copyleft licenses (GPL, AGPL, SSPL, LGPL when vendored) from entering
  projects that ship under permissive licenses (MIT, Apache-2.0, BSD).
  Classifies a package against an SPDX-keyed allow / warn / deny policy.
  Use before adding a new dependency, when reviewing a PR that touches a
  manifest, or when auditing an existing project for license contamination.
  Triggers on: "license check", "GPL check", "is <lib> MIT-compatible",
  "can I use <lib>", "license compat".
---

# GPL License Checker

Prevent accidental inclusion of copyleft (GPL / AGPL / SSPL) or ambiguous
(LGPL, GFDL) dependencies in projects that distribute under permissive
licenses. One copyleft dep contaminates the whole distribution; this
skill gives the agent the knowledge to catch it before the commit.

The skill is a problem statement plus reference data — not an
implementation. How to fetch, parse, and classify is up to the agent
invoking it. Registries change; the problem and the policy don't.

## When to invoke

- Before adding a package to `pyproject.toml`, `requirements*.txt`,
  `setup.py`, `setup.cfg`, `Pipfile`, `package.json`, `Cargo.toml`,
  `go.mod`, or `pom.xml`.
- When the user asks "can I use `<library>`?" or "is `<library>`
  MIT-compatible?".
- When reviewing a diff that touches any of the above files.

## The three files you need

1. [check-package.md](check-package.md) — the problem statement. What to
   check, which sources are authoritative, verdict classes, exit-code
   contract, worked examples.
2. [references/policy.md](references/policy.md) — the SPDX allow / warn /
   deny lists. Source of truth. Extend it when a new license appears.
3. [references/known-quirks.md](references/known-quirks.md) — empirical
   catalogue of the weird shapes license metadata actually takes in the
   wild (garbage strings, legacy notation, cross-source disagreement).
   Useful to skim before solving a case that seems "off".

Start with `check-package.md`. Reach for the others when the check
surfaces something surprising.

## Verdict summary

| Bucket | Verdict | Notes |
|--------|---------|-------|
| Permissive (MIT, Apache-2.0, BSD-*, ISC, CC0, PSF, Zlib, …) | ALLOW | Ship freely |
| Weak / lesser copyleft (MPL-2.0, LGPL-*, EPL-2.0, CDDL) | WARN | Dynamic import OK; vendoring converts to DENY |
| Strong / network copyleft (GPL-*, AGPL-*, SSPL) | DENY | Viral — blocks distribution |
| Source-available (BUSL-1.1, Elastic-2.0, Commons-Clause) | DENY | Not open source |
| Docs copyleft (GFDL-*) | DENY | Contaminates copied docs |
| Share-alike (CC-BY-SA-*) | DENY | Viral on derived works |
| Missing / unresolvable | DENY | Absence of match = absence of grant |

Full SPDX lists in [references/policy.md](references/policy.md).

## The LGPL nuance (why WARN, not DENY)

Copyleft scope for LGPL depends on how you use the library:

- **Dynamic import** (`import foo`, `require('foo')`, standard
  `pip` / `npm` / `cargo` installs): separate work. Your code keeps its
  own license.
- **Vendor / fork / statically link / modify**: combined work. Your
  fork falls under LGPL obligations (source distribution, replacement
  rights, notices).

The skill can't infer which mode you're in. When you get a WARN, ask:
*am I about to vendor or modify this?* If yes, find a permissive
replacement. If no, proceed.

## Project-local overrides

For legitimate exceptions (e.g. a GPL CLI tool invoked only as a
subprocess), a downstream repo carries `license-overrides.yml` next to
the manifest it protects. Spec in [check-package.md](check-package.md).
Keep the file with the manifest so the audit trail travels with the
repo.
