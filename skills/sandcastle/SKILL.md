---
name: sandcastle
description: >
  Orchestrate sandboxed AFK coding agents in TypeScript with Sandcastle
  (@ai-hero/sandcastle). Covers the run/createSandbox/createWorktree API,
  agent and sandbox providers, branch strategies, prompt substitution,
  hooks, templates, and multi-agent workflows. Invoke when code imports
  @ai-hero/sandcastle, when scaffolding a new Sandcastle project, or when
  designing multi-agent orchestration pipelines.
triggers:
  - sandcastle
  - "@ai-hero/sandcastle"
  - sandcastle.run
  - createSandbox
  - createWorktree
  - sandboxed agent
  - afk agent orchestration
skip:
  - Claude Code usage without Sandcastle orchestration
  - Docker/Podman config unrelated to Sandcastle
  - Vercel deployment unrelated to Vercel sandbox provider
  - General git worktree usage without Sandcastle
---

# Sandcastle

**Sandcastle** is a TypeScript library by Matt Pocock (AI Hero) for
orchestrating coding agents inside isolated sandboxes. It is
provider-agnostic on both axes: agents (Claude Code, Codex, pi, opencode)
and sandboxes (Docker, Podman, Vercel Firecracker microVMs) are pluggable.

- **Repo:** `github.com/mattpocock/sandcastle`
- **Package:** `@ai-hero/sandcastle` on npm
- **License:** MIT
- **Build:** tsgo + vitest

## Terminology

Use these terms precisely — ambiguity causes bugs in agent-generated code.

- **Sandbox** = the isolation boundary (container or VM), not "container" or "workspace".
- **Host** = the developer's machine, not "local" (the sandbox also has a local filesystem).
- **Agent** = the AI coding tool (Claude Code, Codex, etc.), not "Claude" (agent is swappable).
- **Iteration** = one invocation of the agent, not "run" (ambiguous with `run()`).
- **Worktree** = git worktree in `.sandcastle/worktrees/`, not "workspace" (retired term).
- **Prompt argument** = `{{KEY}}` value from `promptArgs`, not "variable" (that's env vars).
- **Source branch** = branch the agent works on. **Target branch** = host's branch at `run()` time. Never say "base branch".
- Always qualify "provider" — say **agent provider** or **sandbox provider**, never bare "provider".

Full glossary: [references/domain-language.md](references/domain-language.md).

## Three entry points

Sandcastle exposes three top-level primitives. Pick the one that matches the
use case:

### `run()` — one-shot agent run

The simplest call. Creates a worktree (unless `head` strategy), starts a
sandbox, runs the agent, and tears everything down.

```typescript
import { run, claudeCode } from "@ai-hero/sandcastle";
import { docker } from "@ai-hero/sandcastle/sandboxes/docker";

const result = await run({
  agent: claudeCode("claude-opus-4-6"),
  sandbox: docker(),
  prompt: "Fix the failing tests",
});
```

Returns `{ iterations, completionSignal, stdout, commits, branch, logFilePath?, preservedWorktreePath? }`.

### `createSandbox()` — long-lived sandbox

Opens a sandbox once and accepts repeated `.run()` calls on the same branch.
Avoids repeat container startup cost for implement-then-review pipelines.

```typescript
import { createSandbox, claudeCode } from "@ai-hero/sandcastle";
import { docker } from "@ai-hero/sandcastle/sandboxes/docker";

const sb = await createSandbox({
  branch: "agent/feature-x",
  sandbox: docker(),
});
await sb.run({ agent: claudeCode("claude-opus-4-6"), prompt: "Implement" });
await sb.run({ agent: claudeCode("claude-opus-4-6"), prompt: "Review" });
await sb.close();
```

`close()` tears down both the container and the worktree. Supports
`await using` for automatic cleanup.

### `createWorktree()` — worktree-first

Independent worktree handle. Interactive session first, then hand the same
worktree to a sandboxed AFK agent.

```typescript
import { createWorktree, claudeCode } from "@ai-hero/sandcastle";
import { docker } from "@ai-hero/sandcastle/sandboxes/docker";

const wt = await createWorktree({
  branchStrategy: { type: "branch", branch: "agent/fix-42" },
});
await wt.interactive({ agent: claudeCode("claude-opus-4-6") });
const sb = await wt.createSandbox({ sandbox: docker() });
await sb.run({ agent: claudeCode("claude-opus-4-6"), prompt: "..." });
await sb.close();  // container only
await wt.close();  // worktree (preserved if dirty)
```

Only accepts `branch` or `merge-to-head` — `head` is a compile-time type
error because it means no worktree.

## Agent providers

All imported from `@ai-hero/sandcastle`.

| Factory | Model example | Key options |
|---------|--------------|-------------|
| `claudeCode(model, opts?)` | `"claude-opus-4-6"` | `effort: "low"\|"medium"\|"high"\|"max"`, `captureSessions: boolean` |
| `codex(model, opts?)` | `"gpt-5.4"` | `effort: "low"\|"medium"\|"high"\|"xhigh"` |
| `pi(model, opts?)` | — | `env: Record<string, string>` |
| `opencode(model, opts?)` | — | `env: Record<string, string>` |

Default model: `claude-opus-4-6`. `max` effort is Opus-only.

All providers accept an `env` option for injecting environment variables.

## Sandbox providers

| Provider | Import | Kind |
|----------|--------|------|
| `docker(opts?)` | `@ai-hero/sandcastle/sandboxes/docker` | bind-mount |
| `podman(opts?)` | `@ai-hero/sandcastle/sandboxes/podman` | bind-mount |
| `vercel(opts?)` | `@ai-hero/sandcastle/sandboxes/vercel` | isolated |
| `noSandbox()` | `@ai-hero/sandcastle` | none (host, interactive only) |

**Bind-mount:** host worktree mounted into container. Agent writes directly
to host filesystem. No file sync needed. Faster.

**Isolated:** own filesystem inside a Firecracker microVM. Must use
`copyIn`/`copyFileOut` for file transfer. Stronger isolation.

**No-sandbox:** agent runs directly on the host. No container. Sandcastle
does NOT pass `--dangerously-skip-permissions` to the agent — normal
permission prompts stay active. Use for interactive sessions where a human
is present.

Sandbox providers are imported from **subpaths** — the main
`@ai-hero/sandcastle` entry point does not re-export any sandbox provider
(except `noSandbox()`).

### Which functions accept which providers

| Function | bind-mount | isolated | no-sandbox |
|----------|-----------|----------|------------|
| `run()` | yes | yes | **no** (type error) |
| `interactive()` | yes | yes | yes |
| `createSandbox()` | yes | yes | **no** (type error) |
| `createWorktree().run()` | yes | yes | — |
| `createWorktree().interactive()` | yes | yes | yes (default) |

`run()` rejects no-sandbox because AFK means unsupervised — you need real
isolation.

Custom providers: `createBindMountSandboxProvider(config)` and
`createIsolatedSandboxProvider(config)`.

Docker provider accepts `network: string | string[]` to attach the container
to specific Docker networks.

## Branch strategies

Configured per `run()` call, not per provider.

| Strategy | Behavior | Default for |
|----------|----------|-------------|
| `{ type: "head" }` | Agent writes directly to host working dir. No worktree. Bind-mount only. | bind-mount providers |
| `{ type: "merge-to-head" }` | Temp branch in worktree, merged back to HEAD when done. | isolated providers |
| `{ type: "branch", branch: "name" }` | Explicit named branch in worktree. For PRs or multi-agent orchestration. | never (always explicit) |

When to use each:
- **head** — fast local dev iteration, no PR workflow.
- **merge-to-head** — safe default for CI/unattended. Throwaway branch
  protects HEAD from failed runs.
- **branch** — when commits need a stable name (PRs, parallel-planner).

## Prompt system

**Inline `prompt:`** is literal. No substitution, no shell expansion. Passing
`promptArgs` with an inline prompt is an error.

**`promptFile:`** enables substitution:

- `{{KEY}}` — filled from `promptArgs`. Missing key = error in `run()`, but
  in `interactive()` Sandcastle prompts the user to type the value. Unused = warning.
- `` !`command` `` — replaced by stdout. Commands run **inside the sandbox**
  in parallel after `sandbox.onSandboxReady` hooks. Non-zero exit fails the run.
- `{{SOURCE_BRANCH}}` and `{{TARGET_BRANCH}}` — auto-injected built-ins.
  Passing them in `promptArgs` is an error.
- `` !`...` `` patterns inside arg *values* are inert text (safe for user content).
- Expansion order: `{{KEY}}` first (host-side), then `` !`...` `` (sandbox-side).

## Iteration and completion

```typescript
await run({
  agent: claudeCode("claude-opus-4-6"),
  sandbox: docker(),
  promptFile: ".sandcastle/prompt.md",
  maxIterations: 3,                             // default: 1
  completionSignal: "<promise>COMPLETE</promise>", // default
  idleTimeoutSeconds: 600,                      // default; resets per output event
});
```

The agent emits `completionSignal` in its output to end the loop early.
Sandcastle never injects it — tell the agent about it in the prompt.

**Completion signal vs. structured output:** The completion signal
(`<promise>COMPLETE</promise>`) is a pure termination marker — it carries no
payload. Structured output is a separate concept: a schema-validated JSON
payload emitted by the agent inside a caller-specified XML tag and returned to
the caller. A run can use either, both, or neither.

## Logging modes

- **Log-to-file mode** (default for `run()`): writes to `.sandcastle/logs/`,
  prints a `tail -f` hint to the console. Callers can pass
  `onAgentStreamEvent` on the `logging` option to receive each agent stream
  event (text chunk or tool call) for external observability. The callback is
  fire-and-forget; thrown errors are swallowed.
- **Terminal mode** (`logging: { type: 'stdout' }`): interactive UI with
  spinners and styled status messages.

## Hooks

Two scopes, grouped under a `hooks` key:

```typescript
await run({
  // ...
  hooks: {
    host: {
      onWorktreeReady: [{ command: "npm install", timeoutMs: 120_000 }],
      onSandboxReady: [{ command: "echo ready" }],
    },
    sandbox: {
      onSandboxReady: [
        { command: "apt-get install -y ripgrep", sudo: true },
      ],
    },
  },
});
```

Lifecycle ordering:
1. `copyToWorktree`
2. `host.onWorktreeReady` (sequential)
3. Sandbox created
4. `host.onSandboxReady` + `sandbox.onSandboxReady` (parallel)

- Default timeout: 60s per hook. Override with `timeoutMs`.
- `host.*` runs on the developer machine (no `sudo`).
- `sandbox.*` runs inside the container (`sudo: true` allowed).

## Session capture and resume

Claude Code sessions are captured to
`~/.claude/projects/<encoded>/sessions/<id>.jsonl` with `cwd` rewritten so
`claude --resume` works from the host.

```typescript
await run({
  // ...
  resumeSession: "abc-123", // incompatible with maxIterations > 1
});
```

Opt out: `claudeCode(model, { captureSessions: false })`.

## Cancellation

All `run()`, `interactive()`, and sandbox `.run()` accept
`signal: AbortSignal`. Aborting kills the agent subprocess, cancels
in-flight hooks, preserves the worktree on disk, and rejects with
`signal.reason`. The `Sandbox` and `Worktree` handles remain usable after
abort — call `.run()` again with a fresh signal, or `.close()` to tear down.

## Scaffolding (`sandcastle init`)

Scaffolds `.sandcastle/` (Dockerfile, prompt.md, .env.example, .gitignore)
and a `main.ts`/`main.mts`. Choices:

- **Sandbox provider:** Docker, Podman, Vercel
- **Agent:** Claude Code, Codex, pi, opencode
- **Backlog manager:** GitHub Issues (`sandcastle` label) or Beads
- **Template:** `blank`, `simple-loop`, `sequential-reviewer`,
  `parallel-planner`, `parallel-planner-with-review`

### Default Dockerfile

Node.js 22, system deps (git, curl, jq), GitHub CLI, Claude Code CLI.
Non-root `agent` user required — Claude refuses to run as root.

## Templates

| Template | Shape |
|----------|-------|
| `blank` | Empty main.ts |
| `simple-loop` | Single agent, multiple iterations |
| `sequential-reviewer` | Implementer then reviewer, same branch |
| `parallel-planner` | Planner fans out to N implementers |
| `parallel-planner-with-review` | Planner -> N implementers -> N reviewers -> merger |

### Parallel planner with review

The most elaborate template. Four agent roles:

1. **Planner** — reads backlog, emits `<plan>` JSON of unblocked issues.
2. **Implementer** (N instances) — one per plan item, own sandbox, own branch
   (`sandcastle/issue-{id}-{slug}`).
3. **Reviewer** (N instances) — runs after each implementer that produced
   commits. Uses `` !`git diff` `` to feed the diff. Can use a different model
   for adversarial review.
4. **Merger** — merges all branches back to main with LLM-powered conflict
   resolution.

Per-issue isolation means a single implementer failure does not abort the run.

## Environment variables

- Agent-provider env and sandbox-provider env must not overlap — overlap
  throws at `run()` time.
- Both override `.sandcastle/.env` resolver output.
- `.env` resolution order: repo root `.env` -> `.sandcastle/.env` ->
  `process.env` (only for keys declared in a `.env` file).

## Key constraints and gotchas

- `head` strategy + isolated provider = runtime error (agent can't see host
  filesystem).
- `copyToWorktree` + `head` strategy = runtime error (no worktree in head
  mode).
- `resumeSession` + `maxIterations > 1` = runtime error.
- `promptArgs` + inline `prompt:` = runtime error (switch to `promptFile:`).
- `{{SOURCE_BRANCH}}`/`{{TARGET_BRANCH}}` in `promptArgs` = runtime error
  (they're auto-injected).
- The Dockerfile must have a non-root user — Claude refuses root.

## References

See [references/](references/) for extracted documentation on specific topics:

- [references/domain-language.md](references/domain-language.md) — canonical terminology and disambiguation rules
- [references/api-surface.md](references/api-surface.md) — full type exports
- [references/branch-strategies.md](references/branch-strategies.md) — detailed branch strategy guide
- [references/prompt-system.md](references/prompt-system.md) — prompt substitution and shell expansion
- [references/sandbox-providers.md](references/sandbox-providers.md) — provider types, custom providers
- [references/templates.md](references/templates.md) — template prompts and workflow shapes
- [references/adrs.md](references/adrs.md) — architecture decision records summary
