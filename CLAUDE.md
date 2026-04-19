# Data Science Skills Factory — Agent Instructions

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
