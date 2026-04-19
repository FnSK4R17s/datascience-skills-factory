# Anti-pattern entry format

Every entry in `ANTIPATTERNS.md` follows the same shape so future agents can
scan quickly and pattern-match.

## Required structure

```markdown
## YYYY-MM-DD — <one-line summary, ≤80 chars, imperative or descriptive>

**What went wrong:** <past-tense, concrete description of what the agent did>

**Correct approach:** <imperative — what to do instead>

**Context:** <optional — file path, command, or scenario where this applies>

---
```

The trailing `---` separates entries visually.

## Field guidance

### Summary (the `## ` line)

- ≤80 chars so it fits in a single line of the SessionStart hook injection.
- No trailing period.
- Use the imperative form for the *fix* OR descriptive for the *mistake* —
  consistent within a repo. Pick one and stick to it.

Good:
- `## 2026-04-19 — Don't auto-commit after generating files`
- `## 2026-04-19 — Always quote shell variables in bash scripts`

Bad:
- `## 2026-04-19 — bug fix` (too vague)
- `## 2026-04-19 — Sometimes I forget to quote variables in bash, which causes word splitting issues that...` (too long, narrative)

### What went wrong

Past tense, factual. No apologies, no hedging. One or two sentences.

Good:
> Ran `git commit` immediately after generating new files instead of asking the user to review first.

Bad:
> I'm sorry — I should have known better. I committed too early and didn't realize the user wanted to check things first. This was a mistake on my part…

### Correct approach

Imperative, actionable. The reader (a future agent) should be able to follow this directly.

Good:
> Generate files, run tests, then **stop and show the user a summary**. Wait for explicit "commit" before staging anything.

Bad:
> Be more careful about commits.

### Context (optional)

Include when the anti-pattern is scoped — a specific file, command, language, or workflow. Skip when the rule is repo-wide.

Good:
> **Context:** Applies to any change touching `migrations/` — production schema changes need explicit user sign-off.

## Good full example

```markdown
## 2026-04-19 — Don't bypass pre-commit hooks with --no-verify

**What went wrong:** Used `git commit --no-verify` to skip a failing lint hook
instead of fixing the lint error.

**Correct approach:** When a hook fails, read the error, fix the underlying
issue, and retry the commit. Only use `--no-verify` when the user explicitly
asks for it.

**Context:** Applies to all commits in this repo. Pre-commit hooks run
ruff + prettier + tests.

---
```

## Bad full example (don't do this)

```markdown
## 4/19 — bug

I made a mistake earlier. Sorry. I'll try to do better. Maybe we should
think about this differently next time. The thing is that sometimes commits
go wrong and that's not great so we should probably be careful.
```

Why it's bad: no date format, no summary, no actionable fix, narrative voice,
apologetic, no context. A future agent learns nothing.
