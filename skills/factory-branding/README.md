<h1 align="center">🏭🎪 factory-branding</h1>

<p align="center">
  <strong>Config-driven logo generation for any emoji-branded ecosystem.</strong><br>
  <sub>Part of <a href="../../">Data Science Skills Factory</a></sub>
</p>

---

Generate branded logos for skills and repos using the Fluent 3D emoji
composition system. Define your base mark and per-skill suffixes in
`branding.yml`, run the generator, get transparent PNG logos.

## Quick Start

```bash
# First time? Bootstrap creates branding.yml + LOGO_CONVENTIONS.md
# See BOOTSTRAP.md for the full setup flow.

# Generate logo for a specific skill
./scripts/generate-logo.sh --config ../../branding.yml --skill qmd-search

# Generate all missing logos
./scripts/generate-logo.sh --config ../../branding.yml --all

# Regenerate the repo-level logo
./scripts/generate-logo.sh --config ../../branding.yml --repo
```

## Design System

All branding is defined in `branding.yml` at the repo root — the skill
itself is ecosystem-agnostic.

| Element | Rule |
|---------|------|
| Config | `branding.yml` at repo root — single source of truth |
| Base mark | Defined in config, appears in every logo |
| Suffix | One emoji per skill, defined in config |
| Source | Microsoft Fluent 3D emoji PNGs |
| Background | Transparent (RGBA) |
| Text | None — name goes in `<h1>` below |

## File Structure

```
factory-branding/
├── SKILL.md                          # Runtime usage — schema, decision tree, rules
├── BOOTSTRAP.md                      # First-time setup — create config, generate logos
├── README.md                         # This file
├── scripts/
│   ├── compose_logo.py               # Pillow compositing script
│   └── generate-logo.sh              # Config-driven generator (reads branding.yml)
├── references/
│   └── fluent-emoji-map.md           # Emoji → Fluent folder name mappings
└── assets/
    ├── branding.yml                  # Template — copy to repo root and customize
    └── LOGO_CONVENTIONS.md           # Template — copy to repo root or guiding_docs/
```
