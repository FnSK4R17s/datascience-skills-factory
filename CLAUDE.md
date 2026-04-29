# Data Science Skills Factory — Agent Instructions

## Read [ANTIPATTERNS.md](ANTIPATTERNS.md) before building a new skill

Hard-won lessons from skills we shipped, broke, or threw away. The
anti-patterns there are real failures that cost time and trust — read
them first so you don't re-run the same experiments.

In particular: **never claim a skill works without an end-to-end test in
a fresh project** (AP1, AP7). Unit-level smoke tests on hand-crafted
JSON prove the script parses, not that the system enforces what the docs
claim.

When you encounter a new failure pattern that wasted real time, append
an entry to ANTIPATTERNS.md as part of the same change. Don't sanitize
the failure — future-you needs to feel the bite to remember.

## Always keep `README.md` skills table in sync

The `## Skills` table in [README.md](README.md) must list **every** subdirectory in [skills/](skills/). Whenever you add, remove, or rename a skill under `skills/`, update the table in the **same commit**.

### Table row format

```
| [<skill-name>](skills/<skill-name>/) | <one-line description, imperative voice, no trailing period> | `npx skills add FnSK4R17s/datascience-skills-factory --skill <skill-name>` |
```

### Checklist before finishing any skill-related change

1. `ls skills/` — enumerate actual skills on disk.
2. Diff against the `## Skills` table in [README.md](README.md).
3. Add missing rows, remove stale rows, fix renamed paths.
4. Keep descriptions aligned with each skill's `SKILL.md` frontmatter `description`.
5. Preserve existing row order; append new skills at the end unless there is a reason to group.

### Related conventions

- Each skill needs a branded `logo.png` — see [skills/brand-kit/](skills/brand-kit/) and [branding.yml](branding.yml).
- `SKILL.md` is the only required file per skill. `BOOTSTRAP.md`, `references/`, `scripts/`, `assets/` are optional.
- Do not invent install commands — the `npx skills add ...` form above is canonical.

## Adding third-party skills

Third-party skills are external skills worth mentioning — we don't maintain their code, only a reference folder with branding and a README.

### Steps

1. Create `skills/<skill-name>/` with three files:
   - `EXTERNAL.md` — standard marker (copy from any existing external skill).
   - `README.md` — branded description, install command, links to the upstream repo.
   - `logo.png` — pull the favicon from their homepage and convert:
     ```bash
     curl -sL https://<homepage>/favicon.svg -o skills/<skill-name>/logo.svg
     convert -background transparent -density 300 skills/<skill-name>/logo.svg -resize 168x168 skills/<skill-name>/logo.png
     ```
     If the favicon is `.ico` or `.png`, adjust accordingly. Do not create custom composite logos — use whatever the project already ships.
2. Add a row to the `## Third-Party Skills` table in [README.md](README.md). Install command points to **their** repo, not ours.
3. Do **not** add an entry to [branding.yml](branding.yml) — third-party skills use their own branding.
