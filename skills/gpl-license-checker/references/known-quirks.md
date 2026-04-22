# Empirical license-metadata quirks

Observed in the wild while building this skill. Not prescriptive — if a
future agent sees one of these and wants to solve it differently (e.g.
ask an LLM, use a library, write fresh regex), that's fine. The value
here is the list of traps, not a canonical way to handle them.

## Registry quirks

### PyPI

- Three license fields coexist. Precedence you'll usually want: PEP 639
  `license_expression` → free-form `license` → Trove `classifiers`.
  The free-form `license` can be:
  - a valid SPDX id (`MIT`, `Apache-2.0`)
  - a legacy GNU string (`GPLv3+`, `LGPLv2.1`)
  - a prose name (`Apache 2.0`, `New BSD`)
  - a filename reference (`LICENSE.md`, `./LICENSE`)
  - the whole license text pasted in (multi-line, multi-kilobyte)
  - `UNKNOWN` / empty / a hyphen
- When the free-form string is garbage, `classifiers` is usually
  correct — check for entries like
  `License :: OSI Approved :: Apache Software License`.
- Some packages (e.g. `nemoguardrails` as of April 2026) put literally
  `"LICENSE.md"` in the `license` field. Classifier fallback recovers it.
- The `project_urls` dict (keys are arbitrary: `homepage`, `Source`,
  `repository`, `Bug Tracker`, etc.) usually contains a GitHub URL even
  when `home_page` is `None`.

### npm

- `license` can be a string (`"MIT"`) or an object (`{"type": "MIT", "url": "..."}`).
- Older packages use a deprecated `licenses` array (plural). Rare but extant.
- `repository.url` often has `git+https://...` prefix and `.git` suffix —
  strip both before extracting the GitHub slug.

### crates.io

- `license` is typically a real SPDX expression. `MIT OR Apache-2.0` is
  the overwhelming default for the Rust ecosystem.
- `versions` array is newest-first; use `versions[0]` when no version is
  pinned.
- `crate.repository` is the canonical source URL and almost always GitHub.

### GitHub

- `GET /repos/<owner>/<repo>/license` returns the detected SPDX id, or
  `NOASSERTION` if the LICENSE file doesn't match a known template.
- Rate limit: 60 req/hour unauthenticated, 5000 req/hour with
  `Authorization: Bearer $GITHUB_TOKEN`.
- **python-telegram-bot case:** the root `LICENSE` file is GPL-3.0 (which
  is what GitHub surfaces), but the library is actually governed by
  `LICENSE.lesser` (LGPL-3.0). PyPI metadata is correct; GitHub SPDX is
  misleading for this specific repo. When cross-sources disagree, prefer
  PyPI for Python packages, npm for Node packages, etc., and fall back to
  GitHub only when the native registry is silent.

### Go modules

- The module path (`github.com/owner/repo/v2`) encodes the host. For
  GitHub-hosted modules, strip any `/v2` major-version suffix and any
  subpath to get the `owner/repo` slug.
- Non-GitHub hosts (gitlab, codeberg, custom vanity domains) have no
  unified license API. Treat as a manual-lookup case — ask the human.

## License-string shapes observed

### Legacy GNU notation to canonical SPDX

Seen on PyPI, npm, and older GitHub repos. A dict like this is a fine
starting point if you need a quick normalizer; extend it when you hit
new strings.

| Seen | Canonical SPDX |
|------|----------------|
| `GPLv1`, `GPLv1+` | `GPL-1.0`, `GPL-1.0-or-later` |
| `GPLv2`, `GPLv2+` | `GPL-2.0`, `GPL-2.0-or-later` |
| `GPLv3`, `GPLv3+`, `GPL v3`, `GPL-v3`, `GNU GPL v3`, `GNU GPLv3` | `GPL-3.0`, `GPL-3.0-or-later` |
| `LGPLv2`, `LGPLv2+` | `LGPL-2.0`, `LGPL-2.0-or-later` |
| `LGPLv2.1`, `LGPLv2.1+` | `LGPL-2.1`, `LGPL-2.1-or-later` |
| `LGPLv3`, `LGPLv3+` | `LGPL-3.0`, `LGPL-3.0-or-later` |
| `AGPLv3`, `AGPLv3+` | `AGPL-3.0`, `AGPL-3.0-or-later` |

### Prose names to canonical SPDX

| Seen | Canonical SPDX |
|------|----------------|
| `Apache 2.0`, `Apache 2`, `Apache-2`, `Apache License 2.0`, `Apache License, Version 2.0`, `Apache Software License`, `ASL 2.0` | `Apache-2.0` |
| `MIT License`, `MIT Licence`, `The MIT License` | `MIT` |
| `BSD`, `BSD License`, `New BSD`, `New BSD License`, `BSD 3-Clause`, `BSD-3` | `BSD-3-Clause` |
| `BSD 2-Clause`, `BSD-2` | `BSD-2-Clause` |
| `Mozilla Public License 2.0`, `Mozilla Public License 2.0 (MPL 2.0)` | `MPL-2.0` |
| `PSF`, `PSFL`, `Python Software Foundation License` | `PSF-2.0` |
| `Python License` | `Python-2.0` |
| `ISC License` | `ISC` |
| `Public Domain`, `CC0` | `CC0-1.0` |
| `The Unlicense` | `Unlicense` |

### Trove classifier to SPDX

PyPI classifier strings seen with a direct SPDX equivalent:

| Classifier | SPDX |
|-----------|------|
| `License :: OSI Approved :: MIT License` | `MIT` |
| `License :: OSI Approved :: Apache Software License` | `Apache-2.0` |
| `License :: OSI Approved :: BSD License` | `BSD-3-Clause` |
| `License :: OSI Approved :: ISC License (ISCL)` | `ISC` |
| `License :: OSI Approved :: Python Software Foundation License` | `PSF-2.0` |
| `License :: OSI Approved :: Mozilla Public License 2.0 (MPL 2.0)` | `MPL-2.0` |
| `License :: OSI Approved :: GNU Lesser General Public License v2 (LGPLv2)` | `LGPL-2.0` |
| `License :: OSI Approved :: GNU Lesser General Public License v2 or later (LGPLv2+)` | `LGPL-2.0-or-later` |
| `License :: OSI Approved :: GNU Lesser General Public License v3 (LGPLv3)` | `LGPL-3.0` |
| `License :: OSI Approved :: GNU Lesser General Public License v3 or later (LGPLv3+)` | `LGPL-3.0-or-later` |
| `License :: OSI Approved :: GNU General Public License v2 (GPLv2)` | `GPL-2.0` |
| `License :: OSI Approved :: GNU General Public License v2 or later (GPLv2+)` | `GPL-2.0-or-later` |
| `License :: OSI Approved :: GNU General Public License v3 (GPLv3)` | `GPL-3.0` |
| `License :: OSI Approved :: GNU General Public License v3 or later (GPLv3+)` | `GPL-3.0-or-later` |
| `License :: OSI Approved :: GNU Affero General Public License v3` | `AGPL-3.0` |
| `License :: OSI Approved :: GNU Affero General Public License v3 or later (AGPLv3+)` | `AGPL-3.0-or-later` |
| `License :: CC0 1.0 Universal (CC0 1.0) Public Domain Dedication` | `CC0-1.0` |
| `License :: Public Domain` | `Unlicense` |

## Garbage-input heuristics

These are detection hints, not rules. Agent decides its own filter.

- A license field ending in `.md`, `.txt`, `.rst`, or starting with
  `license` (case-insensitive) is typically a filename reference, not a
  license name. One exception: `license: MIT`-style one-liners — parse
  the right-hand side.
- A value with a newline in it is almost certainly a paste of license
  text, not a license name.
- A value over ~120 characters and not matching any alias is almost
  certainly garbage.
- After garbage detection, fall through to the next source (classifiers,
  then GitHub) rather than returning an error.

## Expression-parsing hazards

- `MIT OR Apache-2.0` — split on ` OR `, classify each, pick the most
  permissive for the verdict. Most Rust crates use this shape.
- `GPL-2.0 WITH Classpath-exception-2.0` — common in the JVM ecosystem.
  The Classpath exception weakens the GPL obligations enough that many
  orgs treat it as WARN rather than DENY. Record the full id in the
  policy; don't silently collapse to base `GPL-2.0`.
- `LGPL-2.1+` is an informal suffix meaning "or later" — map to
  `LGPL-2.1-or-later`.
- `(A OR B) AND C` — formally a valid SPDX expression. Rare in
  practice. If encountered, surface to the human rather than
  auto-deciding.

## Cross-source disagreement

When a package's PyPI-reported license and its GitHub-reported license
disagree (see python-telegram-bot above), the native-registry answer is
usually correct for how you'll consume the package. GitHub's is the
repo-level license, which may cover more than the library portion. When
in doubt, open the actual LICENSE file and read it.
