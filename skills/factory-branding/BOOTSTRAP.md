# BOOTSTRAP.md — First-Time Branding Setup

One-time setup for logo generation in a new ecosystem. Creates the config
files, generates initial logos, and wires up the README headers.

## Steps

### 1. Check Prerequisites

```bash
python3 -c "from PIL import Image; print('Pillow OK')"
python3 -c "import yaml; print('PyYAML OK')"
curl --version
```

If missing:
```bash
pip install Pillow PyYAML
```

### 2. Create `branding.yml`

Copy the template to the repo root:

```bash
cp assets/branding.yml <repo-root>/branding.yml
```

Edit it to define:
- `brand.name` and `brand.tagline`
- `base_mark` — one or more emojis that form the brand signature
- `repo.emojis` — the full emoji sequence for the repo-level logo
- `skills.<name>` — one entry per skill or sub-repo that needs a logo

### 3. Create `LOGO_CONVENTIONS.md`

Copy the template to the repo's docs or guiding docs directory:

```bash
cp assets/LOGO_CONVENTIONS.md <repo-root>/LOGO_CONVENTIONS.md
```

Update the template placeholders:
- Replace the base mark table with your actual base mark emoji(s)
- Fill in the suffix table with your skills/sub-repos
- Update the generation script path to match your skill install location

### 4. Generate Logos

```bash
# Repo-level logo first
./scripts/generate-logo.sh --config <repo-root>/branding.yml --repo

# All skill logos
./scripts/generate-logo.sh --config <repo-root>/branding.yml --all
```

First run downloads Fluent 3D emoji PNGs to `~/.cache/factory-branding/fluent-emoji/`.

### 5. Add README Headers

For each skill that got a `logo.png`, add this header to its README:

```html
<p align="center">
  <img src="logo.png" alt="<Skill Name>" height="88">
</p>

<h1 align="center"><Skill Name></h1>

<p align="center">
  <strong><Tagline></strong><br>
  <sub>Part of <a href="../../"><Brand Name></a></sub>
</p>

---
```

Heights come from `branding.yml` — use `display.with_suffix.height` for
skills and `display.repo_level.height` for the repo README.

### 6. Verify

- Each skill directory has a `logo.png`
- Repo root has a `logo.png`
- READMEs render correctly on GitHub (push and check)
- `LOGO_CONVENTIONS.md` suffix table matches `branding.yml`

## Done

After setup, use SKILL.md for ongoing logo generation (new skills, updates).
Keep `branding.yml` and `LOGO_CONVENTIONS.md` in sync when adding new entries.
