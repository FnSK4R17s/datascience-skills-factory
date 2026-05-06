<p align="center">
  <img src="logo.png" alt="Sandcastle" height="88">
</p>

<h1 align="center">Sandcastle</h1>

<p align="center">
  <strong>Orchestrate sandboxed AFK coding agents in TypeScript.</strong><br>
  <em>Covers the full @ai-hero/sandcastle API — run, createSandbox, createWorktree, providers, templates.</em>
</p>

---

## Install

```bash
npx skills add FnSK4R17s/datascience-skills-factory --skill sandcastle
```

## What this skill covers

- **Three entry points:** `run()` (one-shot), `createSandbox()` (long-lived), `createWorktree()` (worktree-first)
- **Agent providers:** Claude Code, Codex, pi, opencode — with model and effort options
- **Sandbox providers:** Docker, Podman, Vercel Firecracker microVMs, noSandbox, custom providers
- **Branch strategies:** head, merge-to-head, branch — defaults, constraints, when-to-use
- **Prompt system:** inline vs. file, `{{KEY}}` substitution, `` !`command` `` shell expansion, built-in placeholders
- **Hooks:** host and sandbox scopes, ordering, timeouts, sudo
- **Templates:** blank, simple-loop, sequential-reviewer, parallel-planner, parallel-planner-with-review
- **Multi-agent workflows:** the four-role parallel-planner-with-review pattern (planner -> N implementers -> N reviewers -> merger)
- **Session capture/resume, cancellation, env merge rules, gotchas**

## References

Deep-dive docs in `references/`:

| File | Topic |
|------|-------|
| [domain-language.md](references/domain-language.md) | Canonical terminology and disambiguation rules |
| [api-surface.md](references/api-surface.md) | Full type exports and interfaces |
| [branch-strategies.md](references/branch-strategies.md) | Detailed branch strategy guide |
| [prompt-system.md](references/prompt-system.md) | Prompt substitution and shell expansion |
| [sandbox-providers.md](references/sandbox-providers.md) | Provider types and custom providers |
| [templates.md](references/templates.md) | Template prompts and workflow shapes |
| [adrs.md](references/adrs.md) | Architecture decision records summary |

## Source

- **Repo:** [mattpocock/sandcastle](https://github.com/mattpocock/sandcastle)
- **Package:** `@ai-hero/sandcastle` on npm
- **Author:** Matt Pocock (AI Hero)
- **License:** MIT
