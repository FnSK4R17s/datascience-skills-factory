# BOOTSTRAP.md — First-Time Branding Setup

One-time setup for logo generation in a new ecosystem. Creates the config
files, generates initial logos, and wires up the README headers.

> **This flow is interactive by default.** Ask the user at each decision
> point before proceeding. Do not silently pick emojis, names, or config
> values — the user's taste drives the brand. If the user explicitly says
> "just do it" or "non-interactive", then make reasonable defaults and
> proceed without asking.

## Steps

### 1. Check Prerequisites

```bash
python3 -c "from PIL import Image; print('Pillow OK')"
python3 -c "import yaml; print('PyYAML OK')"
curl --version
```

If missing, install them. This step does not need user input.

### 2. Brand Identity

**Ask the user:**

> What's the name of this project/ecosystem?
> Give me a one-line tagline for it.

Use their answers for `brand.name` and `brand.tagline` in the config.

### 3. Base Mark

**Ask the user:**

> What emoji(s) should be the base mark — the signature that appears in
> every logo? This can be a single emoji (e.g. 🏭) or a pair (e.g. ⚓🦞).
> It should represent the core identity of the project.

If the user is unsure, suggest 2-3 options based on the project name and
purpose. Explain that the base mark is permanent and appears in every
skill and sub-repo logo.

### 4. Repo-Level Logo

**Ask the user:**

> What emoji sequence should the repo-level logo use? This appears on the
> main README. Convention is to put the base mark last and lead with
> descriptive emojis (e.g. 📊🔬✨🏭). Or it can just be the base mark alone.

### 5. Scan for Skills, Sub-Repos, and Siblings

Scan for three distinct scopes:

1. **Skills** — directories under `skills/` in this repo
2. **Sub-repos** — repos nested inside this repo (git submodules, or
   directories at repo root that are themselves separate repos)
3. **Siblings** — repos adjacent on disk, outside this repo
   (e.g. sharing the same parent workspace dir). Ask the user to
   confirm the workspace layout before scanning.

**Ask the user for workspace layout if siblings are in play:**

> Where do sibling repos live relative to this repo's root?
> Default is the parent directory (`..`). Confirm or provide a custom
> `siblings_base_path`.

**Show the user what was found and ask:**

> I found these skills: [list].
> Candidate sub-repos: [list].
> Candidate siblings: [list].
> Which ones should get a logo? For each, what suffix emoji fits?

For each entry, collect:
- A suffix emoji (suggest one based on purpose if possible)
- The reasoning
- Optional `path:` override if the dir name on disk doesn't match the key

If there are many, present a proposed table grouped by scope and ask
for approval or edits rather than asking one-by-one. Ensure suffixes
are unique **across all three scopes**.

### 6. Where to Put LOGO_CONVENTIONS.md

**Ask the user:**

> Where should LOGO_CONVENTIONS.md live? Common options:
> - Repo root (`./LOGO_CONVENTIONS.md`)
> - Guiding docs (`./guiding_docs/LOGO_CONVENTIONS.md`)
> - Docs folder (`./docs/LOGO_CONVENTIONS.md`)

### 7. Create Config Files

With all answers collected, create:

1. **`branding.yml`** at repo root — copy from `assets/branding.yml` template
   and fill in with the user's choices
2. **`LOGO_CONVENTIONS.md`** at the user's chosen location — copy from
   `assets/LOGO_CONVENTIONS.md` template and fill in the base mark table,
   suffix tables, and generation paths

**Show the user the generated `branding.yml` before writing it.** Let them
adjust if anything looks off.

### 8. Generate Logos

```bash
# Repo-level logo first
./scripts/generate-logo.sh --config branding.yml --repo

# All skill logos
./scripts/generate-logo.sh --config branding.yml --all

# All subrepo logos (only if `subrepos:` has entries)
./scripts/generate-logo.sh --config branding.yml --all-subrepos

# All sibling repo logos (only if `siblings:` has entries)
./scripts/generate-logo.sh --config branding.yml --all-siblings

# Or, in one shot: skills + subrepos + siblings
./scripts/generate-logo.sh --config branding.yml --everything
```

First run downloads Fluent 3D emoji PNGs to `~/.cache/brand-kit/fluent-emoji/`.

### 9. Add README Headers

For each skill / sub-repo / sibling that got a `logo.png`, add this header to its README:

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

**Ask the user** if they want the existing emoji-only headers (e.g. `# 🏭🔍 skill-name`)
replaced with the logo-based headers, or kept as-is until logos are pushed.

### 10. Verify

- Each skill directory has a `logo.png`
- Each subrepo directory listed in `subrepos:` has a `logo.png`
- Each sibling directory listed in `siblings:` has a `logo.png`
- Repo root has a `logo.png`
- `LOGO_CONVENTIONS.md` suffix table matches `branding.yml` (all three scopes)

**Ask the user** if they want to commit the generated logos and config now.
Note: sibling logos are committed to each sibling repo — ask whether
the user wants to handle those commits or have you do it.

## Done

After setup, use SKILL.md for ongoing logo generation (new skills, updates).
Keep `branding.yml` and `LOGO_CONVENTIONS.md` in sync when adding new entries.
