<p align="center">
  <img src="logo.png" alt="plan-feature" height="88">
</p>

<h1 align="center">plan-feature</h1>

<p align="center">
  <strong>Stage-gated feature planner for existing codebases.</strong><br>
  <sub>Part of <a href="../../">Data Science Skills Factory</a></sub>
</p>

---

Stage-gated planner for feature-level work in an existing codebase. Walks
the user through four stages and produces one agent-ready backlog item.

## Stages

1. **Research** — codebase + qmd scan of what already exists.
2. **Requirements** — interactive user-facing contract + acceptance criteria.
3. **Deep Research** — resolve open questions from Stage 2, surface risks.
4. **Backlog Item** — single karpathy-style handoff doc for an implementing
   agent.

Output lives at `plan/<feature-slug>/` in the target repo. A global
`plan/PLAN.md` indexes all features with their stage status.

## First-time setup

Run `BOOTSTRAP.md` once per repo. It creates `plan/PLAN.md` and
`plan/.planconfig`.

## Day-to-day use

Invoke the skill. It either creates a new feature folder and starts at
Stage 1, or resumes an existing feature at the first incomplete stage.

## Config

`plan/.planconfig` controls per-stage search toggles (qmd, WebFetch,
codebase search), slug case, and status column style. Edit the file in the
target repo — not the template in this skill.

## Files

- `SKILL.md` — orchestrator and stage prompts.
- `BOOTSTRAP.md` — one-time repo setup.
- `templates/PLAN.md` — global feature × stage index.
- `templates/.planconfig` — default config shipped to each repo.
- `templates/01-research.md` through `04-backlog-item.md` — stage scaffolds.

## Related skills

- `prd-karpathy-style` — whole-product PRDs. Use when the scope is a new
  product, not a feature in an existing codebase.
- `bugfix` — bug investigations. Use when the goal is fixing broken
  behavior, not adding new behavior.
- `qmd-search` — the semantic search backend used by Stages 1 and 3 when
  enabled in `.planconfig`.
