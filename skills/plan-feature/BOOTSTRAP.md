# BOOTSTRAP.md — First-Time plan-feature Setup

One-time setup per repository. After these steps, delete or ignore this file
and use `SKILL.md` for day-to-day feature planning.

## Steps

### 1. Confirm target repo root

The `plan/` folder lives at the **codebase root** — the same directory that
contains the main `.git`, `package.json`, `pyproject.toml`, or equivalent.
Confirm with the user which repo is being set up before writing any files.

### 2. Create the `plan/` folder

```bash
mkdir -p plan
```

Abort if `plan/` already exists and is non-empty — ask the user whether to
reuse it (skip to step 5) or pick a different location.

### 3. Install `PLAN.md` from template

Copy `templates/PLAN.md` from this skill into `plan/PLAN.md`. The file
contains an empty feature-by-stage table. Do not edit it yet — `SKILL.md`
appends rows as features are planned.

### 4. Install `.planconfig` from template

Copy `templates/.planconfig` from this skill into `plan/.planconfig`. Then
ask the user about three settings and edit in place:

1. **qmd collection name.** If the repo has a qmd collection registered
   (check with `qmd status` if available), ask for its name or set
   `qmd_collection: auto`. If the repo has no qmd collection, set both
   `qmd_stage1` and `qmd_stage3` to `false`.
2. **Web fetch in Deep Research.** Default `true`. Set to `false` if the
   user works offline or in a security-restricted context.
3. **Status column style.** Default `freeform`. Switch to `enum` only if the
   user wants strict values (draft / v1-ready / v1-done / archived).

### 5. Verify

Confirm the following exist and are readable:

- `plan/PLAN.md`
- `plan/.planconfig`

Show the user the resulting `.planconfig` and ask for a final OK.

### 6. Optional — add to `.gitignore`

Ask whether `plan/` should be committed. Two common choices:

- **Commit it** — plans become part of the repo history. Recommended for
  team repos where backlog items are shared artifacts.
- **Ignore it** — add `plan/` to `.gitignore`. Recommended for private
  scratch work.

Do not decide for the user.

## Done

Setup is complete. Future invocations of the `plan-feature` skill will
detect `plan/PLAN.md` and start at Stage 1 for a new feature, or resume an
existing one. This BOOTSTRAP file is not needed again.
