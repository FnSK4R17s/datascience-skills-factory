---
name: factory-branding
description: >
  Generate branded logos and README headers for Data Science Skills Factory
  skills and repos. Uses the Fluent 3D emoji composition system — a base mark
  plus per-skill suffix emojis rendered as transparent PNGs via Pillow.
  Use when creating a new skill, when a skill README is missing a logo,
  when the user asks about branding, or when you need to generate a logo.png.
  Triggers on: "logo", "branding", "generate logo", "add logo", "skill logo",
  "brand", "README header".
---

# Factory Branding Skill

Generate logos and branded README headers for skills in the Data Science
Skills Factory ecosystem.

## Design System

### Base Mark

Every skill and repo in the factory ecosystem uses the same base emoji —
the **Factory signature**:

| Emoji | Name | Role |
|-------|------|------|
| 🏭 | Factory | The brand anchor — "built in the factory" |

### Skill Suffix

Each skill appends one or two emojis that represent its purpose:

| Skill | Suffix | Full Mark | Reasoning |
|-------|--------|-----------|-----------|
| **datascience-skills-factory** | 📊🔬✨ | 📊🔬✨🏭 | Bar chart + microscope + sparkles — data science, research, magic (repo-level, 4 emoji) |
| **auto-format** | 🎨 | 🏭🎨 | Art palette — styling, formatting |
| **langfuse-tracing** | 📡 | 🏭📡 | Satellite dish — signals, telemetry, observability |
| **prd-karpathy-style** | 📋 | 🏭📋 | Clipboard — specs, documents, planning |
| **qmd-search** | 🔍 | 🏭🔍 | Magnifying glass — search, discovery |
| **factory-branding** | 🎪 | 🏭🎪 | Circus tent — the showroom, presentation |

### Adding a New Skill

When a new skill is created, pick a suffix emoji that:
1. Represents the skill's primary function at a glance
2. Is distinct from existing suffixes (no duplicates)
3. Exists in Microsoft Fluent 3D emoji set
4. Is a single emoji (two max for repo-level logos)

Add the new entry to the suffix table above.

## How to Generate a Logo

### Method: Pillow Composite

Use `scripts/generate-logo.sh` which wraps the Pillow compositing script:

```bash
# Generate for a specific skill
./scripts/generate-logo.sh --skill qmd-search

# Generate for all skills missing a logo
./scripts/generate-logo.sh --all

# Generate the repo-level logo
./scripts/generate-logo.sh --repo
```

### Manual Method (Pillow script directly)

```bash
python scripts/compose_logo.py --emojis "🏭🔍" --output skills/qmd-search/logo.png
```

### Source Assets

- **Font**: Microsoft Fluent Emoji 3D — [GitHub repo](https://github.com/microsoft/fluentui-emoji)
- **Method**: Download individual emoji PNGs from the Fluent repo, composite side-by-side at equal height
- **Background**: Transparent PNG (RGBA)
- **Output**: `logo.png` in the skill directory

### Finding Fluent 3D Emoji PNGs

Fluent emoji assets live at paths like:
```
fluentui-emoji/assets/<Emoji Name>/3D/<emoji_name>_3d.png
```

Map Unicode emoji to folder names:
| Emoji | Folder name |
|-------|-------------|
| 🏭 | Factory |
| 🔍 | Magnifying glass tilted left |
| 🎨 | Artist palette |
| 📡 | Satellite antenna |
| 📋 | Clipboard |
| 📊 | Bar chart |
| 🔬 | Microscope |
| ✨ | Sparkles |
| 🎪 | Circus tent |

## Display Sizes

| Emoji count | README height | Example |
|-------------|---------------|---------|
| 2 (base + suffix) | `height="88"` | Most skills |
| 3+ (repo-level) | `height="97"` | datascience-skills-factory |

## README Template

### Skill-level README header

```html
<p align="center">
  <img src="logo.png" alt="<Skill Name>" height="88">
</p>

<h1 align="center"><Skill Name></h1>

<p align="center">
  <strong><One-line tagline></strong><br>
  <sub>Part of <a href="../../">Data Science Skills Factory</a></sub>
</p>

---
```

### Repo-level README header

```html
<p align="center">
  <img src="logo.png" alt="Data Science Skills Factory" height="97">
</p>

<h1 align="center">Data Science Skills Factory</h1>

<p align="center">
  <strong><Tagline></strong><br>
  <em><Subtitle></em><br>
  <sub><Footnote></sub>
</p>
```

## Rules

- **Always include the factory emoji** (🏭) — it's the brand anchor
- **One suffix emoji per skill** (two max for repo-level)
- **Factory emoji goes first** for skills, last for the repo-level logo
- **Use Fluent 3D style only** — no Twemoji, no Apple emoji, no flat icons
- **Transparent background** — works on light and dark themes
- **No text in the logo** — the skill/repo name goes in the `<h1>` below it
- **Logo file**: always `logo.png` at the skill or repo root

## Cross-Reference: CommandClaw Conventions

This system mirrors the [CommandClaw logo conventions](https://github.com/FnSK4R17s/commandclaw/blob/main/guiding_docs/LOGO_CONVENTIONS.md)
but uses 🏭 as the base mark instead of ⚓🦞. The generation method, display
sizes, README patterns, and rules are intentionally parallel.

## Additional Resources

- `scripts/compose_logo.py` — Pillow script for compositing emoji PNGs
- `scripts/generate-logo.sh` — Shell wrapper for common logo generation tasks
- `references/fluent-emoji-map.md` — Common emoji to Fluent folder name mappings
