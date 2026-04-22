#!/usr/bin/env python3
"""Check the license of a single package against the skill's policy.

Usage:
    check_package.py <ecosystem> <name> [<version>]

Ecosystems:
    pypi     PyPI (Python)          name is case-insensitive
    npm      npm registry           scoped names OK: @scope/name
    crates   crates.io (Rust)
    github   GitHub repo            name is "owner/repo"

Exit codes:
    0 ALLOW   permissive
    1 WARN    weak/lesser copyleft — dynamic-link OK, do not vendor
    2 DENY    strong/network copyleft, source-available, or unknown
    3 ERROR   network or parse failure

Output: single tab-separated line to stdout:
    VERDICT<TAB>name<TAB>spdx<TAB>class<TAB>note
"""

from __future__ import annotations

import json
import os
import re
import sys
import urllib.error
import urllib.request
from pathlib import Path

POLICY_PATH = Path(__file__).resolve().parent.parent / "references" / "policy.md"


def _parse_policy() -> dict[str, tuple[str, str]]:
    """Parse policy.md into {spdx_upper: (verdict, class)}."""
    text = POLICY_PATH.read_text(encoding="utf-8")
    sections: list[tuple[str, str, list[str]]] = []
    current_verdict: str | None = None
    current_class = ""
    buf: list[str] = []

    section_re = re.compile(r"^## (Allow|Warn|Deny)", re.IGNORECASE)
    subsec_re = re.compile(r"^### (.+)$")
    code_block_re = re.compile(r"^```")

    in_code = False
    for line in text.splitlines():
        if section_re.match(line):
            if current_verdict is not None:
                sections.append((current_verdict, current_class, buf))
                buf = []
            v = section_re.match(line).group(1).upper()
            current_verdict = {"ALLOW": "ALLOW", "WARN": "WARN", "DENY": "DENY"}[v]
            current_class = "permissive" if v == "ALLOW" else (
                "lesser_copyleft" if v == "WARN" else "strong_copyleft"
            )
            continue
        if subsec_re.match(line):
            title = subsec_re.match(line).group(1).lower()
            if "network" in title:
                current_class = "network_copyleft"
            elif "strong" in title:
                current_class = "strong_copyleft"
            elif "lesser" in title or "weak" in title:
                current_class = "lesser_copyleft"
            elif "classpath" in title:
                current_class = "classpath_exception"
            elif "source-available" in title or "not open" in title:
                current_class = "source_available"
            elif "documentation" in title:
                current_class = "docs_copyleft"
            elif "share-alike" in title or "creative commons" in title:
                current_class = "share_alike"
            elif "missing" in title or "unresolvable" in title:
                current_class = "unknown"
            continue
        if code_block_re.match(line):
            if in_code and current_verdict is not None:
                sections.append((current_verdict, current_class, buf))
                buf = []
            in_code = not in_code
            continue
        if in_code and line.strip():
            buf.append(line.strip())

    table: dict[str, tuple[str, str]] = {}
    for verdict, klass, ids in sections:
        for spdx in ids:
            table[spdx.upper()] = (verdict, klass)
    return table


# Map of common non-SPDX license strings seen in legacy PyPI metadata
# and free-form fields to their canonical SPDX identifiers.
_NON_SPDX_ALIASES = {
    "GPLV1": "GPL-1.0",
    "GPLV1+": "GPL-1.0-or-later",
    "GPLV2": "GPL-2.0",
    "GPLV2+": "GPL-2.0-or-later",
    "GPLV3": "GPL-3.0",
    "GPLV3+": "GPL-3.0-or-later",
    "GPL V3": "GPL-3.0",
    "GPL-V3": "GPL-3.0",
    "GNU GPL V3": "GPL-3.0",
    "GNU GPLV3": "GPL-3.0",
    "LGPLV2": "LGPL-2.0",
    "LGPLV2+": "LGPL-2.0-or-later",
    "LGPLV2.1": "LGPL-2.1",
    "LGPLV2.1+": "LGPL-2.1-or-later",
    "LGPLV3": "LGPL-3.0",
    "LGPLV3+": "LGPL-3.0-or-later",
    "AGPLV3": "AGPL-3.0",
    "AGPLV3+": "AGPL-3.0-or-later",
    "APACHE 2.0": "Apache-2.0",
    "APACHE 2": "Apache-2.0",
    "APACHE-2": "Apache-2.0",
    "APACHE LICENSE 2.0": "Apache-2.0",
    "APACHE LICENSE, VERSION 2.0": "Apache-2.0",
    "APACHE SOFTWARE LICENSE": "Apache-2.0",
    "ASL 2.0": "Apache-2.0",
    "MIT LICENSE": "MIT",
    "MIT LICENCE": "MIT",
    "THE MIT LICENSE": "MIT",
    "BSD": "BSD-3-Clause",
    "BSD LICENSE": "BSD-3-Clause",
    "NEW BSD": "BSD-3-Clause",
    "NEW BSD LICENSE": "BSD-3-Clause",
    "BSD 3-CLAUSE": "BSD-3-Clause",
    "BSD-3": "BSD-3-Clause",
    "BSD 2-CLAUSE": "BSD-2-Clause",
    "BSD-2": "BSD-2-Clause",
    "MOZILLA PUBLIC LICENSE 2.0": "MPL-2.0",
    "MOZILLA PUBLIC LICENSE 2.0 (MPL 2.0)": "MPL-2.0",
    "PSF": "PSF-2.0",
    "PSFL": "PSF-2.0",
    "PYTHON SOFTWARE FOUNDATION LICENSE": "PSF-2.0",
    "PYTHON LICENSE": "Python-2.0",
    "ISC LICENSE": "ISC",
    "PUBLIC DOMAIN": "CC0-1.0",
    "CC0": "CC0-1.0",
    "THE UNLICENSE": "Unlicense",
}


def _normalize_spdx(raw: str) -> str:
    """Coerce a legacy or non-SPDX license string into a canonical SPDX id.

    Returns '' if the input is clearly garbage (filename, license text dump,
    >80 chars with no recognizable token) — the caller should then fall back
    to a GitHub lookup.
    """
    if not raw:
        return ""
    s = raw.strip().strip(".")

    # Garbage filter: LICENSE file paths, multi-line dumps, huge blobs.
    lower = s.lower()
    if lower.endswith((".md", ".txt", ".rst")) or lower.startswith("license"):
        # But tolerate "license: MIT" one-liners
        m = re.match(r"^license[:\s]+(.+)$", s, flags=re.IGNORECASE)
        if m:
            return _normalize_spdx(m.group(1))
        return ""
    if "\n" in s or len(s) > 120:
        return ""

    up = s.upper()
    if up in _NON_SPDX_ALIASES:
        return _NON_SPDX_ALIASES[up]
    # Trailing " License" is noise: "MIT License" → already handled above.
    return s


def _classify(spdx: str, policy: dict[str, tuple[str, str]]) -> tuple[str, str, str]:
    """Return (verdict, class, note) for a given SPDX id (or expression)."""
    if not spdx or spdx.upper() in ("NOASSERTION", "UNKNOWN", "NONE", "?"):
        return "DENY", "unknown", "no license assertion — treat as all-rights-reserved"

    # Handle simple OR expressions: pick most permissive.
    if " OR " in spdx.upper():
        parts = [p.strip() for p in re.split(r"\s+OR\s+", spdx, flags=re.IGNORECASE)]
        verdicts = [_classify(p, policy) for p in parts]
        rank = {"ALLOW": 0, "WARN": 1, "DENY": 2, "ERROR": 3}
        best = min(verdicts, key=lambda v: rank[v[0]])
        chosen = parts[verdicts.index(best)]
        return best[0], best[1], f"multi-license; chose {chosen}"

    # WITH exceptions (e.g. GPL-2.0 WITH Classpath-exception-2.0)
    if " WITH " in spdx.upper():
        hit = policy.get(spdx.upper())
        if hit:
            return hit[0], hit[1], "license with exception"
        # fall through to base license
        base = spdx.split(" WITH ")[0].strip()
        return _classify(base, policy)

    hit = policy.get(spdx.upper())
    if hit:
        return hit[0], hit[1], ""
    # Unknown SPDX id — conservative deny.
    return "DENY", "unknown", f"SPDX id {spdx!r} not in policy"


def _fetch_json(url: str, timeout: float = 10.0) -> dict | None:
    req = urllib.request.Request(url, headers={"User-Agent": "gpl-license-checker/1"})
    token = os.environ.get("GITHUB_TOKEN")
    if token and "api.github.com" in url:
        req.add_header("Authorization", f"Bearer {token}")
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            return json.load(resp)
    except (urllib.error.URLError, urllib.error.HTTPError, TimeoutError, json.JSONDecodeError):
        return None


def _lookup_pypi(name: str, version: str | None) -> tuple[str, str | None]:
    """Return (spdx, github_slug) for a PyPI package."""
    url = f"https://pypi.org/pypi/{name}/json" if not version else f"https://pypi.org/pypi/{name}/{version}/json"
    data = _fetch_json(url)
    if not data:
        return "", None
    info = data.get("info", {})
    classifiers = info.get("classifiers", []) or []
    # Prefer PEP 639 license-expression; then the free-form license field; then classifiers.
    spdx = (
        info.get("license_expression")
        or info.get("license-expression")
        or (info.get("license") or "").strip()
    )
    # If the free-form field is garbage (e.g. "LICENSE.md" or a full license text),
    # fall through to classifiers — they are more reliable in practice.
    if _normalize_spdx(spdx) == "":
        spdx = _spdx_from_classifiers(classifiers) or spdx
    # Always try to extract a GitHub slug for fallback lookups, even when
    # we have a local SPDX — some packages lie in metadata.
    gh = (
        _github_slug_from_url(info.get("home_page") or "")
        or _github_slug_from_url(info.get("project_url") or "")
        or _github_slug_from_urls(info.get("project_urls") or {})
    )
    return spdx or "", gh


def _spdx_from_classifiers(classifiers: list[str]) -> str:
    """Rough map from Trove classifiers to SPDX."""
    m = {
        "License :: OSI Approved :: MIT License": "MIT",
        "License :: OSI Approved :: Apache Software License": "Apache-2.0",
        "License :: OSI Approved :: BSD License": "BSD-3-Clause",
        "License :: OSI Approved :: ISC License (ISCL)": "ISC",
        "License :: OSI Approved :: Python Software Foundation License": "PSF-2.0",
        "License :: OSI Approved :: Mozilla Public License 2.0 (MPL 2.0)": "MPL-2.0",
        "License :: OSI Approved :: GNU Lesser General Public License v2 (LGPLv2)": "LGPL-2.0",
        "License :: OSI Approved :: GNU Lesser General Public License v2 or later (LGPLv2+)": "LGPL-2.0-or-later",
        "License :: OSI Approved :: GNU Lesser General Public License v3 (LGPLv3)": "LGPL-3.0",
        "License :: OSI Approved :: GNU Lesser General Public License v3 or later (LGPLv3+)": "LGPL-3.0-or-later",
        "License :: OSI Approved :: GNU General Public License v2 (GPLv2)": "GPL-2.0",
        "License :: OSI Approved :: GNU General Public License v2 or later (GPLv2+)": "GPL-2.0-or-later",
        "License :: OSI Approved :: GNU General Public License v3 (GPLv3)": "GPL-3.0",
        "License :: OSI Approved :: GNU General Public License v3 or later (GPLv3+)": "GPL-3.0-or-later",
        "License :: OSI Approved :: GNU Affero General Public License v3": "AGPL-3.0",
        "License :: OSI Approved :: GNU Affero General Public License v3 or later (AGPLv3+)": "AGPL-3.0-or-later",
        "License :: CC0 1.0 Universal (CC0 1.0) Public Domain Dedication": "CC0-1.0",
        "License :: Public Domain": "Unlicense",
    }
    for c in classifiers:
        if c in m:
            return m[c]
    return ""


def _github_slug_from_url(url: str) -> str | None:
    if not url:
        return None
    m = re.match(r"https?://github\.com/([^/]+/[^/]+?)(?:/|\.git|#|$)", url)
    return m.group(1) if m else None


def _github_slug_from_urls(urls: dict) -> str | None:
    for v in urls.values():
        slug = _github_slug_from_url(v)
        if slug:
            return slug
    return None


def _lookup_npm(name: str, version: str | None) -> tuple[str, str | None]:
    url = f"https://registry.npmjs.org/{name}"
    data = _fetch_json(url)
    if not data:
        return "", None
    v = version or data.get("dist-tags", {}).get("latest")
    manifest = data.get("versions", {}).get(v, {}) if v else {}
    lic = manifest.get("license") or data.get("license") or ""
    if isinstance(lic, dict):
        lic = lic.get("type", "") or ""
    repo = manifest.get("repository") or data.get("repository") or {}
    repo_url = repo.get("url", "") if isinstance(repo, dict) else str(repo)
    gh = _github_slug_from_url(repo_url.replace("git+", "").replace(".git", ""))
    return lic, gh


def _lookup_crates(name: str, version: str | None) -> tuple[str, str | None]:
    url = f"https://crates.io/api/v1/crates/{name}"
    data = _fetch_json(url)
    if not data:
        return "", None
    crate = data.get("crate", {})
    versions = data.get("versions", [])
    v = None
    if version:
        v = next((x for x in versions if x.get("num") == version), None)
    if v is None and versions:
        v = versions[0]
    lic = (v or {}).get("license", "") or ""
    gh = _github_slug_from_url(crate.get("repository", "") or "")
    return lic, gh


def _lookup_github(slug: str) -> str:
    data = _fetch_json(f"https://api.github.com/repos/{slug}/license")
    if not data:
        return ""
    lic = (data.get("license") or {}).get("spdx_id", "") or ""
    return "" if lic.upper() == "NOASSERTION" else lic


def check(ecosystem: str, name: str, version: str | None = None) -> tuple[str, str, str, str, str]:
    """Return (verdict, name, spdx, class, note)."""
    policy = _parse_policy()
    spdx = ""
    gh_slug: str | None = None

    if ecosystem == "pypi":
        spdx, gh_slug = _lookup_pypi(name, version)
    elif ecosystem == "npm":
        spdx, gh_slug = _lookup_npm(name, version)
    elif ecosystem == "crates":
        spdx, gh_slug = _lookup_crates(name, version)
    elif ecosystem == "github":
        spdx = _lookup_github(name)
    else:
        return "ERROR", name, "", "unsupported", f"ecosystem {ecosystem!r} not supported"

    spdx = _normalize_spdx(spdx)

    # Fallback to GitHub if registry didn't give us a usable SPDX
    if (not spdx or spdx.upper() in ("UNKNOWN", "NONE", "NOASSERTION")) and gh_slug:
        gh_spdx = _lookup_github(gh_slug)
        if gh_spdx:
            spdx = _normalize_spdx(gh_spdx) or gh_spdx

    if not spdx:
        return "DENY", name, "", "unknown", "no license information found in registry or GitHub"

    verdict, klass, note = _classify(spdx, policy)
    return verdict, name, spdx, klass, note


def main(argv: list[str]) -> int:
    if len(argv) < 3 or argv[1] in ("-h", "--help"):
        print(__doc__, file=sys.stderr)
        return 3
    ecosystem = argv[1]
    name = argv[2]
    version = argv[3] if len(argv) > 3 else None
    verdict, name_out, spdx, klass, note = check(ecosystem, name, version)
    tail = f"\t{note}" if note else ""
    print(f"{verdict}\t{name_out}\t{spdx or '?'}\t{klass}{tail}")
    exit_map = {"ALLOW": 0, "WARN": 1, "DENY": 2, "ERROR": 3}
    return exit_map.get(verdict, 3)


if __name__ == "__main__":
    sys.exit(main(sys.argv))
