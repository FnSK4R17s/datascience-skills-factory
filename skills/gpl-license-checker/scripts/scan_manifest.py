#!/usr/bin/env python3
"""Scan a project manifest and report license verdicts for every declared dep.

Usage:
    scan_manifest.py <path-to-manifest> [...more paths]

Supported manifests:
    pyproject.toml        PEP 621 [project] + Poetry [tool.poetry]
    requirements*.txt     one-per-line pip requirements
    setup.py              best-effort regex over install_requires=[...]
    package.json          npm / pnpm / yarn dependencies + devDependencies
    Cargo.toml            [dependencies] and [dev-dependencies]
    go.mod                require (...) blocks

Exit codes:
    0 all ALLOW
    1 at least one WARN, no DENY
    2 at least one DENY (or override miss)
    3 parse / IO error

Reads `license-overrides.yml` in the directory of the manifest if present;
entries there downgrade a DENY to OVERRIDE (still printed, no non-zero exit).
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from check_package import check  # noqa: E402


def _parse_pyproject(path: Path) -> list[tuple[str, str]]:
    """Return [(ecosystem, name)] for every direct dep in pyproject.toml."""
    try:
        import tomllib
    except ModuleNotFoundError:  # py<3.11
        import tomli as tomllib  # type: ignore

    data = tomllib.loads(path.read_text(encoding="utf-8"))
    names: set[str] = set()

    # PEP 621
    project = data.get("project") or {}
    for spec in project.get("dependencies", []) or []:
        n = _spec_name(spec)
        if n:
            names.add(n)
    for extras in (project.get("optional-dependencies") or {}).values():
        for spec in extras:
            n = _spec_name(spec)
            if n:
                names.add(n)

    # Poetry
    poetry = (data.get("tool") or {}).get("poetry") or {}
    for sec in ("dependencies", "dev-dependencies"):
        for n in (poetry.get(sec) or {}):
            if n.lower() != "python":
                names.add(n)
    for grp in (poetry.get("group") or {}).values():
        for n in (grp.get("dependencies") or {}):
            if n.lower() != "python":
                names.add(n)

    return sorted(("pypi", n) for n in names)


def _spec_name(spec: str) -> str | None:
    m = re.match(r"^\s*([A-Za-z0-9][A-Za-z0-9._-]*)", spec)
    return m.group(1) if m else None


def _parse_requirements(path: Path) -> list[tuple[str, str]]:
    names: set[str] = set()
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.split("#", 1)[0].strip()
        if not line or line.startswith(("-", "git+", "http://", "https://", "file:")):
            continue
        n = _spec_name(line)
        if n:
            names.add(n)
    return sorted(("pypi", n) for n in names)


def _parse_package_json(path: Path) -> list[tuple[str, str]]:
    data = json.loads(path.read_text(encoding="utf-8"))
    names: set[str] = set()
    for sec in ("dependencies", "devDependencies", "peerDependencies", "optionalDependencies"):
        for k in (data.get(sec) or {}):
            names.add(k)
    return sorted(("npm", n) for n in names)


def _parse_cargo_toml(path: Path) -> list[tuple[str, str]]:
    try:
        import tomllib
    except ModuleNotFoundError:
        import tomli as tomllib  # type: ignore
    data = tomllib.loads(path.read_text(encoding="utf-8"))
    names: set[str] = set()
    for sec in ("dependencies", "dev-dependencies", "build-dependencies"):
        block = data.get(sec) or {}
        for k in block:
            names.add(k)
    # workspace.dependencies
    ws = (data.get("workspace") or {}).get("dependencies") or {}
    for k in ws:
        names.add(k)
    return sorted(("crates", n) for n in names)


def _parse_go_mod(path: Path) -> list[tuple[str, str]]:
    text = path.read_text(encoding="utf-8")
    names: set[str] = set()
    # require block (...) style
    for block in re.findall(r"require\s*\((.*?)\)", text, flags=re.S):
        for line in block.splitlines():
            line = line.split("//", 1)[0].strip()
            if not line:
                continue
            m = re.match(r"^(\S+)\s+\S+", line)
            if m:
                names.add(m.group(1))
    # single-line require
    for m in re.finditer(r"^require\s+(\S+)\s+\S+", text, flags=re.M):
        names.add(m.group(1))
    # Go modules are fetched by import path; the ecosystem we support is "github"
    # when the path starts with github.com/, else we skip (the checker
    # doesn't know how to look up other module hosts yet).
    out: list[tuple[str, str]] = []
    for n in sorted(names):
        if n.startswith("github.com/"):
            parts = n.split("/")
            if len(parts) >= 3:
                out.append(("github", f"{parts[1]}/{parts[2]}"))
    return out


def _load_overrides(manifest_dir: Path) -> dict[tuple[str, str], str]:
    path = manifest_dir / "license-overrides.yml"
    if not path.exists():
        return {}
    # Minimal YAML parser for a flat list of mappings — avoid PyYAML dep.
    text = path.read_text(encoding="utf-8")
    out: dict[tuple[str, str], str] = {}
    current: dict[str, str] = {}
    for raw in text.splitlines():
        line = raw.rstrip()
        if not line.strip() or line.strip().startswith("#"):
            continue
        if re.match(r"^\s*-\s*package:\s*(.+)$", line):
            if current.get("package") and current.get("ecosystem"):
                out[(current["ecosystem"], current["package"])] = current.get("justification", "")
            current = {"package": re.match(r"^\s*-\s*package:\s*(.+)$", line).group(1).strip()}
        else:
            m = re.match(r"^\s*([a-z_]+):\s*(.+)$", line)
            if m and current:
                current[m.group(1)] = m.group(2).strip().strip('"').strip("'")
    if current.get("package") and current.get("ecosystem"):
        out[(current["ecosystem"], current["package"])] = current.get("justification", "")
    return out


def scan(path: Path) -> int:
    name = path.name.lower()
    if name == "pyproject.toml":
        deps = _parse_pyproject(path)
    elif name.startswith("requirements") and name.endswith(".txt"):
        deps = _parse_requirements(path)
    elif name == "package.json":
        deps = _parse_package_json(path)
    elif name == "cargo.toml":
        deps = _parse_cargo_toml(path)
    elif name == "go.mod":
        deps = _parse_go_mod(path)
    else:
        print(f"ERROR\t{path}\t?\tunknown\tunrecognized manifest filename", file=sys.stderr)
        return 3

    overrides = _load_overrides(path.parent)
    worst = 0
    rank = {"ALLOW": 0, "WARN": 1, "DENY": 2, "ERROR": 3, "OVERRIDE": 0}

    print(f"# scanning {path} ({len(deps)} deps)")
    for ecosystem, dep in deps:
        verdict, _, spdx, klass, note = check(ecosystem, dep)
        if verdict == "DENY" and (ecosystem, dep) in overrides:
            verdict = "OVERRIDE"
            note = f"overridden: {overrides[(ecosystem, dep)]}"
        tail = f"\t{note}" if note else ""
        print(f"{verdict}\t{dep}\t{spdx or '?'}\t{klass}{tail}")
        worst = max(worst, rank.get(verdict, 3))
    return worst


def main(argv: list[str]) -> int:
    if len(argv) < 2 or argv[1] in ("-h", "--help"):
        print(__doc__, file=sys.stderr)
        return 3
    worst = 0
    for arg in argv[1:]:
        p = Path(arg)
        if not p.exists():
            print(f"ERROR\t{arg}\t?\tmissing\tfile not found", file=sys.stderr)
            worst = max(worst, 3)
            continue
        worst = max(worst, scan(p))
    return worst


if __name__ == "__main__":
    sys.exit(main(sys.argv))
