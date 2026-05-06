# Sandcastle Skill

> A documentation skill that teaches agents how to use Sandcastle
> (`@ai-hero/sandcastle`) — the TypeScript library for orchestrating
> sandboxed AFK coding agents.

## What changes

Today, agents working with Sandcastle rely on training knowledge that may be
stale (the library shipped in April 2026 and iterates rapidly). After this
skill, agents have access to accurate API types, all five runtime error
conditions, correct import paths, template workflow patterns, and reference
documentation extracted from the actual source code.

**The key insight is that Sandcastle has three entry points (`run`,
`createSandbox`, `createWorktree`) with different lifecycle ownership
semantics, and the skill must make the right choice obvious.**

## Touchpoints

**`skills/sandcastle/SKILL.md`** — the main skill file. Covers all three
entry points, agent/sandbox providers, branch strategies, prompt system,
hooks, templates, env merge rules, and gotchas. Points to `references/` for
deep-dive topics.

**`skills/sandcastle/references/`** — six reference documents extracted from
the source code and docs:
- `api-surface.md` — full type exports
- `branch-strategies.md` — detailed branch strategy guide
- `prompt-system.md` — prompt substitution and shell expansion
- `sandbox-providers.md` — provider types, custom providers
- `templates.md` — template prompts and workflow shapes
- `adrs.md` — architecture decision records summary

**`plan/sandcastle-skill/docs/`** — 54 scraped source files (README, docs,
ADRs, template prompts, TypeScript source) serving as ground truth.

## Workflow

### Agent uses Sandcastle for the first time

1. Skill triggers on `@ai-hero/sandcastle` import or "sandcastle" keyword.
2. Agent reads SKILL.md for the API overview.
3. Agent consults the relevant reference doc for deep-dive specifics.

### Agent designs a multi-agent pipeline

1. Agent reads SKILL.md templates section.
2. Agent reads `references/templates.md` for the parallel-planner-with-review
   workflow pattern.
3. Agent implements using `createWorktree` + `branch` strategy per agent.

## Example

> **Scenario.** An agent is asked to set up a Sandcastle parallel-planner
> pipeline that implements GitHub issues in parallel and reviews each branch.

The agent reads the skill, picks `parallel-planner-with-review` template,
and scaffolds a `main.ts` that:
1. Fetches open issues labeled `sandcastle`.
2. Runs a planner agent to select unblocked issues.
3. Spawns N implementer sandboxes on separate branches.
4. Runs a reviewer on each branch that produced commits.
5. Merges all branches with a merger agent.

## Status

v1 done. Skill and references shipped. Plan docs scraped.
