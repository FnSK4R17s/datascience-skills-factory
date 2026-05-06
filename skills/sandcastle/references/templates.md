# Templates

Sandcastle ships five scaffolding templates via `sandcastle init`.

## blank

Empty `main.ts`. Manual setup.

## simple-loop

Single agent, multiple iterations. The agent runs in a loop until it emits
the completion signal or hits `maxIterations`.

## sequential-reviewer

Two-phase pipeline on the same branch:

1. **Implementer** — fixes the issue, writes tests, commits.
2. **Reviewer** — reviews the diff for clarity, consistency, correctness.
   Makes direct fixes if needed.

Both agents see the same branch and sandbox.

## parallel-planner

Fan-out pipeline:

1. **Planner** — reads backlog, emits `<plan>` JSON of unblocked issues.
2. **Implementer** (N instances) — one per plan item, own sandbox, own
   branch.
3. **Merger** — merges all branches back to main.

## parallel-planner-with-review

The most elaborate template. Fan-out / fan-in with review:

1. **Planner** — reads backlog, builds dependency graph, emits `<plan>` JSON
   of unblocked issues with branch names (`sandcastle/issue-{id}-{slug}`).
2. **Implementer** (N instances) — one per plan item, own sandbox, own
   branch. Uses RGR (Red-Green-Refactor) cycle. Commits with structured
   messages including task reference.
3. **Reviewer** (N instances) — runs after each implementer that produced
   commits. Feeds the diff via `` !`git diff {{SOURCE_BRANCH}}...{{BRANCH}}` ``.
   Can use a different model for adversarial review (e.g. Codex reviewing
   Claude output).
4. **Merger** — takes all branches + originating issues, merges to main with
   LLM-powered conflict resolution.

### Failure isolation

Per-issue isolation means a single implementer failure does not abort the run.
The merger only sees branches that produced commits.

### Cost shape

```
cost ~ planner + N * implementer + N * reviewer + merger
```

With higher-effort reviewer models, review cost can dominate. The template
makes that knob explicit (a single line in `main.ts`).

### Example planner output

```xml
<plan>
{"issues": [
  {"id": "42", "title": "Fix auth bug", "branch": "sandcastle/issue-42-fix-auth-bug"},
  {"id": "57", "title": "Add search", "branch": "sandcastle/issue-57-add-search"}
]}
</plan>
```

### Example review prompt pattern

```markdown
## Branch diff
!`git diff {{SOURCE_BRANCH}}...{{BRANCH}}`

## Commits on this branch
!`git log {{SOURCE_BRANCH}}..{{BRANCH}} --oneline`
```

## Backlog managers

Templates that read from a backlog support:
- **GitHub Issues** — filtered by the `sandcastle` label.
- **Beads** — alternative task format.
