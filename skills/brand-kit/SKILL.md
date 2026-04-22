---
name: brand-kit
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

# Brand Kit Skill

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

# Per-skill logos — directories under skills/
skills:                                # key = directory name under skills/
  my-skill:
    suffix: ["🔍"]                     # appended after base_mark
    name: "Magnifying glass"
    reason: "Search, discovery"

# Sub-repos — repos nested INSIDE this repo (e.g. submodules)
# Output: <subrepos_base_path>/<key>/logo.png
subrepos_base_path: "."                # default: this repo's root
subrepos:
  myproject-api:
    suffix: ["🚀"]
    name: "Rocket"
    reason: "API layer, launches requests"
    # path: "services/api"             # optional per-entry override

# Sibling repos — repos OUTSIDE this repo, adjacent on disk
# (e.g. /apps/myproject-vault next to /apps/myproject)
# Output: <siblings_base_path>/<key>/logo.png
siblings_base_path: ".."               # default: parent directory
siblings:
  myproject-vault:
    suffix: ["🏠"]
    name: "House"
    reason: "Vault = home"
    # path: "/absolute/or/relative/path"  # optional per-entry override

# Optional emoji → Fluent folder override map. Only needed when an emoji
# is missing from references/emoji-folders.json (e.g. unreleased glyph)
# or when a custom folder name is intentional.
# emoji_folders:
#   "<glyph>": "<Folder Name>"
```

### Scope Semantics

| Scope       | Lives                          | Default base path | Typical path key |
|-------------|--------------------------------|-------------------|------------------|
| `skills`    | Inside `skills/` of this repo  | `skills/`         | key = dirname    |
| `subrepos`  | Nested inside this repo        | `.`               | key = dirname    |
| `siblings`  | Adjacent on disk, other repo   | `..`              | key = dirname    |

Per-entry `path:` overrides the computed path. Absolute paths are
honored as-is; relative paths resolve against the branding.yml's
repo root (not against the base path).

### Emoji Ordering Convention

- **Skill / subrepo / sibling logos**: base mark goes **first**, suffix appended after
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

## Interaction Model

> **Default: interactive.** Always ask the user before making brand
> decisions — emoji choices, names, placements. Do not silently pick
> emojis or write config without confirmation. The user's taste drives
> the brand, not defaults.
>
> **Exception:** If the user explicitly says "just do it", "non-interactive",
> "auto", or similar, make reasonable choices and proceed without asking.

## Decision Tree

### 1. Locate Config

Look for `branding.yml` at the repo root.

**If found:** read it, validate (step 2), and proceed to logo generation.

**If missing:** follow BOOTSTRAP.md for first-time setup. This is an
interactive flow — ask the user about brand name, base mark emoji(s),
repo-level logo sequence, per-skill suffixes, and where to put
LOGO_CONVENTIONS.md. Do not create the config silently.

### 2. Validate Config

Check that:
- `brand.source` is `fluent-3d` (only supported source)
- `base_mark` has at least one entry
- Each skill in `skills:` has a `suffix` array
- Each sub-repo in `subrepos:` has a `suffix` array
- Each sibling in `siblings:` has a `suffix` array
- No duplicate suffix emojis across skills, subrepos, and siblings
- For every sibling entry, the resolved target directory exists on disk
  (warn but still generate — the script creates it if missing)

If validation fails, tell the user what's wrong and ask how to fix it.

### 3. Generate Logos

Single target:
```bash
./scripts/generate-logo.sh --config <path>/branding.yml --skill    <skill-name>
./scripts/generate-logo.sh --config <path>/branding.yml --subrepo  <subrepo-name>
./scripts/generate-logo.sh --config <path>/branding.yml --sibling  <sibling-name>
```

Batch:
```bash
./scripts/generate-logo.sh --config <path>/branding.yml --all             # all skills
./scripts/generate-logo.sh --config <path>/branding.yml --all-subrepos    # all subrepos
./scripts/generate-logo.sh --config <path>/branding.yml --all-siblings    # all siblings
./scripts/generate-logo.sh --config <path>/branding.yml --everything      # skills + subrepos + siblings
```

Repo-level logo (the one defined by `repo.emojis`):
```bash
./scripts/generate-logo.sh --config <path>/branding.yml --repo
```

All batch modes skip entries that already have a `logo.png`.

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

### 5. Register New Skills, Sub-Repos, or Sibling Repos

When a new skill, sub-repo, or sibling repo is created and needs a logo:

**Ask the user:**

> What suffix emoji should represent `<name>`? It should capture its
> purpose at a glance and be distinct from existing suffixes (across
> skills, subrepos, **and** siblings).

If the user is unsure, suggest 2-3 options based on the description
and existing patterns in `branding.yml`.

Then:
1. Add entry under the correct scope (`skills:` / `subrepos:` / `siblings:`)
2. Update `LOGO_CONVENTIONS.md` suffix table
3. Run the matching generate command:
   - `--skill <name>` for skills
   - `--subrepo <name>` for nested subrepos
   - `--sibling <name>` for adjacent sibling repos
4. Add the README header
5. **Show the user the result** before committing

## Fluent 3D Emoji Source

Logos use PNGs from [Microsoft Fluent Emoji 3D](https://github.com/microsoft/fluentui-emoji).

Asset paths: `fluentui-emoji/assets/<Folder>/[<Variant>/]3D/<slug>_3d[_<variant-lower>].png`
where `<Variant>` is `Default | Light | Medium-Light | Medium | Medium-Dark | Dark`
for skin-toned emojis (absent for the rest).

### Emoji → folder lookup

The full mapping lives in `references/emoji-folders.json` — ~3145 entries
covering every glyph in the Fluent set, including all six skin-tone
variants for person emojis. Generated by `scripts/build-emoji-map.py`
from a local clone of `microsoft/fluentui-emoji`.

Refresh after Microsoft ships new emojis:

```bash
cd /tmp && git clone --depth 1 https://github.com/microsoft/fluentui-emoji
python3 skills/brand-kit/scripts/build-emoji-map.py \
  --clone /tmp/fluentui-emoji \
  --out skills/brand-kit/references/emoji-folders.json \
  --verify
```

### Per-config overrides (`emoji_folders:`)

A `branding.yml` can override the lookup for edge cases or custom
glyphs the script cannot resolve:

```yaml
emoji_folders:
  "🧙‍♂️": "Man mage"          # overrides the shipped JSON
  "<custom-glyph>": "Some folder name"
```

Override order of precedence:
1. `emoji_folders:` in branding.yml (highest)
2. `references/emoji-folders.json` (ships with skill)

Overrides resolve to the default `<Folder>/3D/<slug>_3d.png` asset
path — do not use for skin-tone-specific variants, which are already
in the shipped JSON.

## Rules

- **Always include the base mark** — defined in `branding.yml`, not optional
- **One suffix emoji per skill** (two max for repo-level)
- **Use Fluent 3D style only** — no Twemoji, no Apple emoji, no flat icons
- **Transparent background** — works on light and dark themes
- **No text in the logo** — name goes in the `<h1>` below it
- **Logo file**: always `logo.png` at skill or repo root

## Additional Resources

- `references/emoji-folders.json` — full emoji → folder + asset-path mapping (3145 entries)
- `references/fluent-emoji-map.md` — prose notes on the Fluent naming scheme
- `scripts/build-emoji-map.py` — regenerate `emoji-folders.json` from a fluentui-emoji clone
- `scripts/compose_logo.py` — Pillow compositor
- `scripts/generate-logo.sh` — shell wrapper that reads branding.yml
