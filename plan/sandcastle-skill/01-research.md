# sandcastle-skill — Research

## Problem observed

Building multi-agent coding pipelines (planner -> implementer -> reviewer ->
merger) requires orchestrating sandboxes, git worktrees, prompt substitution,
and branch strategies. Sandcastle (`@ai-hero/sandcastle`) by Matt Pocock
ships the primitives, but there is no skill that encodes the API surface,
constraints, and template patterns so that agents can correctly use the
library without falling back to stale training knowledge.

## What exists today

- Sandcastle's GitHub repo (`mattpocock/sandcastle`) has a 1170-line README,
  a docs site (3 MDX pages), 10 ADRs, 4 internal agent docs, and 13 template
  prompt files.
- The API surface is exported from `src/index.ts`: `run`, `createSandbox`,
  `createWorktree`, `interactive`, four agent provider factories, two
  sandbox provider factory functions, and associated types.
- No existing skill in datascience-skills-factory covers Sandcastle or
  AFK agent orchestration.

## Constraint

The library is TypeScript-only (tsgo + vitest). The skill must be language-
neutral in its prose (describing the API) but all code examples are
TypeScript.

## Adjacent skills

- `mcp-python-sdk`: precedent for a library-documentation skill with
  `references/` subdirectory for extracted topic docs.
- `tdd`: precedent for a workflow skill with template patterns.
