---
name: factory-branding
description: >
  Generate branded logos and README headers using a config-driven Fluent 3D
  emoji composition system. Reads branding.yml from the repo root to determine
  base mark, per-skill/per-repo suffix emojis, and display sizes. Works for
  any ecosystem that follows the config schema — not hardcoded to a specific
  brand. Use when creating a new skill or repo, when a README is missing a logo,
  when the user asks about branding, or when you need to generate a logo.png.
  Triggers on: "logo", "branding", "generate logo", "add logo", "skill logo",
  "brand", "README header", "branding.yml".
---

# Factory Branding Skill

Generate logos and branded README headers for any ecosystem that provides a
`branding.yml` config file.

## Config File: `branding.yml`

The skill reads `branding.yml` from the repo root. This file defines the
entire brand identity — base mark, suffix emojis, display sizes, and generation
defaults. The skill itself contains no hardcoded emoji mappings.

### Schema

```yaml
# Brand identity
brand:
  name: "Ecosystem Name"
  tagline: "One-line description."
  source: fluent-3d                    # emoji source (only fluent-3d supported)

# Base mark — appears in every logo
base_mark:
  - emoji: "🏭"
    name: Factory
    role: "Why this emoji represents the brand"
  # Multi-emoji base marks supported (e.g. CommandClaw uses ⚓🦞)
  # - emoji: "⚓"
  #   name: Anchor
  #   role: "Stability, control"

# Display sizes (height attr in README <img> tags)
display:
  base_only:
    height: 97
  with_suffix:
    height: 88
  repo_level:
    height: 97

# Generation defaults
defaults:
  pixel_height: 168                    # actual PNG pixel height
  gap: 8                               # pixels between emojis
  background: transparent

# Repo-level logo
repo:
  emojis: ["📊", "🔬", "✨", "🏭"]   # full emoji sequence
  output: logo.png                     # path relative to repo root

# Per-skill (or per-sub-repo) logos
skills:                                # key = directory name under skills/
  my-skill:
    suffix: ["🔍"]                     # appended after base_mark
    name: "Magnifying glass"
    reason: "Search, discovery"
```

### Emoji Ordering Convention

- **Skill logos**: base mark goes **first**, suffix appended after
- **Repo-level logo**: base mark goes **last** (suffix emojis lead)
- This is configurable — `repo.emojis` is the literal sequence used

### Multi-Emoji Base Marks

Some ecosystems use multiple emojis as their base mark. Example:

```yaml
base_mark:
  - emoji: "⚓"
    name: Anchor
    role: "Stability, control"
  - emoji: "🦞"
    name: Lobster
    role: "The Claw — core identity"
```

This produces ⚓🦞 as the base, with suffixes appended: ⚓🦞🔍

## Decision Tree

### 1. Locate Config

Look for `branding.yml` at the repo root. If missing:
- Ask the user if they want to create one
- Use the schema above as a template
- Fill in base mark and any existing skills

### 2. Validate Config

Check that:
- `brand.source` is `fluent-3d` (only supported source)
- `base_mark` has at least one entry
- Each skill in `skills:` has a `suffix` array
- No duplicate suffix emojis across skills

### 3. Generate Logos

For a specific skill:
```bash
./scripts/generate-logo.sh --config ../../branding.yml --skill <skill-name>
```

For all skills missing a logo:
```bash
./scripts/generate-logo.sh --config ../../branding.yml --all
```

For the repo-level logo:
```bash
./scripts/generate-logo.sh --config ../../branding.yml --repo
```

### 4. Update READMEs

After generating `logo.png`, ensure the skill README uses this header pattern:

```html
<p align="center">
  <img src="logo.png" alt="<Skill Name>" height="<display.with_suffix.height>">
</p>

<h1 align="center"><Skill Name></h1>

<p align="center">
  <strong><One-line tagline></strong><br>
  <sub>Part of <a href="../../"><brand.name></a></sub>
</p>

---
```

Heights come from `branding.yml`:
- Skills with suffix: `display.with_suffix.height`
- Base-only logos: `display.base_only.height`
- Repo-level: `display.repo_level.height`

### 5. Register New Skills

When a new skill is created and needs a logo:
1. Pick a suffix emoji (single emoji, must exist in Fluent 3D set, no duplicates)
2. Add entry to `branding.yml` under `skills:`
3. Run `generate-logo.sh --config branding.yml --skill <name>`
4. Add the README header

## Fluent 3D Emoji Source

Logos use PNGs from [Microsoft Fluent Emoji 3D](https://github.com/microsoft/fluentui-emoji).

Asset paths: `fluentui-emoji/assets/<Emoji Name>/3D/<emoji_name>_3d.png`

See `references/fluent-emoji-map.md` for the name → folder mapping.

## Rules

- **Always include the base mark** — defined in `branding.yml`, not optional
- **One suffix emoji per skill** (two max for repo-level)
- **Use Fluent 3D style only** — no Twemoji, no Apple emoji, no flat icons
- **Transparent background** — works on light and dark themes
- **No text in the logo** — name goes in the `<h1>` below it
- **Logo file**: always `logo.png` at skill or repo root

## Additional Resources

- `references/fluent-emoji-map.md` — emoji → Fluent folder name mappings
- `scripts/compose_logo.py` — Pillow compositor
- `scripts/generate-logo.sh` — Shell wrapper that reads branding.yml
