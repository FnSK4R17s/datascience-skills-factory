# License Policy

Canonical allow / warn / deny lists keyed on SPDX identifiers. The scripts
in `../scripts/` consult this file as the source of truth.

Rationale: we ship code under **MIT** (CommandClaw core) and **Apache-2.0**
(skills, public packages). Any copyleft dep — GPL family in particular — is
incompatible because its distribution terms override ours.

## Allow (verdict: ALLOW, exit 0)

Permissive licenses with no redistribution-side constraints beyond attribution.

```
0BSD
Apache-2.0
BSD-2-Clause
BSD-2-Clause-Patent
BSD-3-Clause
BSD-3-Clause-Clear
BlueOak-1.0.0
BSL-1.0
CC0-1.0
CC-BY-4.0
ISC
MIT
MIT-0
MulanPSL-2.0
OFL-1.1
PSF-2.0
Python-2.0
Unlicense
WTFPL
Zlib
```

## Warn (verdict: WARN, exit 1)

Weak or lesser copyleft — safe **if** you do not vendor, fork, or modify.
Dynamic linking / `import` usage does not trigger copyleft obligations.

```
CDDL-1.0
CDDL-1.1
EPL-2.0
LGPL-2.1
LGPL-2.1-only
LGPL-2.1-or-later
LGPL-3.0
LGPL-3.0-only
LGPL-3.0-or-later
MPL-2.0
Ruby
```

Rule of thumb: when you see a `WARN`, answer "am I about to fork, modify,
or paste source from this?". If no, proceed. If yes, pick an `ALLOW` replacement.

### Classpath exceptions

GPL-with-Classpath-exception variants are treated as WARN, not DENY. Common
in the JVM ecosystem (OpenJDK modules):

```
GPL-2.0 WITH Classpath-exception-2.0
```

Still: do not modify the library. If you do, Classpath doesn't save you.

## Deny (verdict: DENY, exit 2)

Strong copyleft, network copyleft, source-available-not-open, or missing license.

### Strong copyleft (viral on distribution)

```
GPL-1.0
GPL-1.0-only
GPL-1.0-or-later
GPL-2.0
GPL-2.0-only
GPL-2.0-or-later
GPL-3.0
GPL-3.0-only
GPL-3.0-or-later
```

### Network copyleft (viral on network use)

```
AGPL-3.0
AGPL-3.0-only
AGPL-3.0-or-later
SSPL-1.0
```

### Source-available, not open-source

Restrict commercial use or redistribution. Treat as proprietary.

```
BUSL-1.1
Elastic-2.0
Commons-Clause
PolyForm-Noncommercial-1.0.0
PolyForm-Shield-1.0.0
Fair-Source-0.9
```

### Documentation copyleft

Affects any doc text copied into your repo.

```
GFDL-1.1
GFDL-1.1-only
GFDL-1.1-or-later
GFDL-1.2
GFDL-1.2-only
GFDL-1.2-or-later
GFDL-1.3
GFDL-1.3-only
GFDL-1.3-or-later
```

### Creative Commons Share-Alike

Viral on derived works. OK as a user, not OK as a dependency of code you ship.

```
CC-BY-SA-3.0
CC-BY-SA-4.0
```

### Missing or unresolvable

Absence of a license = all rights reserved. Never silently proceed.

```
NOASSERTION
UNKNOWN
NONE
```

## Override procedure

If you need to add a denied dep for a legitimate reason (e.g. a CLI tool
invoked as a subprocess, never imported as a library), create an override
file at the project root:

```yaml
# license-overrides.yml
overrides:
  - package: somegpl-tool
    ecosystem: pypi
    justification: "Invoked as subprocess only; not linked or imported."
    approved_by: shikhar
    spdx: GPL-3.0
```

The scanner honors `license-overrides.yml` and emits `OVERRIDE` instead of
`DENY`. Keep justifications honest — subprocess-invocation is a legitimate
carve-out for GPL tools; `import` is not.
