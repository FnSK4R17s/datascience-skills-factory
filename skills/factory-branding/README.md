<h1 align="center">🏭🎪 factory-branding</h1>

<p align="center">
  <strong>Logo generation and branding for the Skills Factory ecosystem.</strong><br>
  <sub>Part of <a href="../../">Data Science Skills Factory</a></sub>
</p>

---

Generate branded logos for skills and repos using the Fluent 3D emoji
composition system. Every skill gets a `logo.png` — factory emoji base mark
plus a skill-specific suffix, composited via Pillow.

## Quick Start

```bash
# Generate logo for a specific skill
./scripts/generate-logo.sh --skill qmd-search

# Generate all missing logos
./scripts/generate-logo.sh --all

# Regenerate the repo-level logo
./scripts/generate-logo.sh --repo
```

## Design System

| Element | Rule |
|---------|------|
| Base mark | 🏭 (always first for skills, last for repo) |
| Suffix | One emoji per skill, two max for repo |
| Source | Microsoft Fluent 3D emoji PNGs |
| Background | Transparent (RGBA) |
| Text | None — name goes in `<h1>` below |

## File Structure

```
factory-branding/
├── SKILL.md                          # Full design system + decision tree
├── README.md                         # This file
├── scripts/
│   ├── compose_logo.py               # Pillow compositing script
│   └── generate-logo.sh              # Shell wrapper with emoji mappings
└── references/
    └── fluent-emoji-map.md           # Emoji → Fluent folder name mappings
```
