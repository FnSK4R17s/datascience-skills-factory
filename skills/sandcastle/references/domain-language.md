# Sandcastle Domain Language

Canonical terminology for the Sandcastle project. When writing code or
documentation that uses Sandcastle, use these terms exactly.

Source: `CONTEXT.md` in the Sandcastle repo.

## Core concepts

| Term | Definition | Avoid |
|------|-----------|-------|
| **Sandcastle** | The TypeScript CLI/library that orchestrates an agent inside a sandbox | "the tool", "the CLI", "RALPH" |
| **Sandbox** | The isolation boundary (container, VM) constraining the agent's access | "container" (too specific), "workspace" |
| **Host** | The developer's machine where Sandcastle runs and the real git repo lives | "local" (ambiguous) |
| **Agent** | The AI coding tool invoked inside the sandbox (Claude Code, Codex, etc.) | "RALPH", "the bot", "Claude" (too specific) |

## Providers

| Term | Definition | Avoid |
|------|-----------|-------|
| **Sandbox provider** | Pluggable implementation that creates/manages a sandbox | "backend", "runtime" |
| **Bind-mount sandbox provider** | Provider where host filesystem is mounted into the environment | "local provider", "mount provider" |
| **Isolated sandbox provider** | Provider with its own filesystem, requiring sync | "remote provider", "sync provider" |
| **No-sandbox provider** | Provider where the agent runs directly on the host | "local provider", "none provider" |
| **Agent provider** | Pluggable implementation that builds commands and parses output for a specific agent | "agent adapter", "agent driver" |

## Branching

| Term | Definition | Avoid |
|------|-----------|-------|
| **Branch strategy** | Configuration controlling how changes relate to branches | "worktree mode" (old name), "branch mode" |
| **Head** | Agent works directly in host working dir. No worktree | `"none"` (old name), "direct" |
| **Merge-to-head** | Temp branch, agent works on it, merged back to HEAD | `"temp-branch"` (old name) |
| **Branch** | Commits land on explicitly named branch | "named-branch" |
| **Worktree** | Git worktree in `.sandcastle/worktrees/` on the host | "workspace", "branch copy", "clone" |
| **Source branch** | The branch the agent works on | "working branch", "agent branch" |
| **Target branch** | The host's active branch at `run()` time | "base branch", "destination branch" |

## Execution

| Term | Definition | Avoid |
|------|-----------|-------|
| **Iteration** | A single invocation of the agent inside the sandbox | "run" (ambiguous with `run()`), "cycle" |
| **Completion signal** | `<promise>COMPLETE</promise>` marker indicating tasks finished | "done flag", "exit signal" |
| **Structured output** | Schema-validated JSON payload emitted by the agent inside an XML tag | "output payload", "result" |

## Prompts

| Term | Definition | Avoid |
|------|-----------|-------|
| **Inline prompt** | `prompt:` string, passed as-is. No substitution | "dynamic prompt", "string prompt" |
| **Prompt template** | `promptFile:` with `{{KEY}}` and `` !`cmd` `` support | "prompt file" (that's the option name) |
| **Prompt argument** | Runtime value substituting a `{{KEY}}` placeholder | "prompt variable" (ambiguous with env vars) |
| **Prompt argument substitution** | Replacing `{{KEY}}` placeholders with values | "interpolation", "variable substitution" |
| **Prompt expansion** | Evaluating `` !`command` `` shell expressions in the sandbox | "prompt preprocessing" (too generic) |
| **Shell expression** | `` !`command` `` marker evaluated inside the sandbox | "command" (overloaded), "inline command" |
| **Built-in prompt argument** | Auto-injected by Sandcastle (`SOURCE_BRANCH`, `TARGET_BRANCH`). Cannot be overridden | "default prompt argument" |

## Hooks

| Term | Definition | Avoid |
|------|-----------|-------|
| **Host hook** | Runs on the host. `{ command }` — no `sudo`, no `cwd` | "local hook" |
| **Sandbox hook** | Runs inside the sandbox. `{ command, sudo? }` | "container hook", "remote hook" |

## Infrastructure

| Term | Definition | Avoid |
|------|-----------|-------|
| **Config directory** | `.sandcastle/` in the host repo | ".sandcastle folder" |
| **Backlog manager** | Pluggable task source (GitHub Issues, Beads) | "task source", "issue tracker" |
| **Agent session** | Persisted conversation record (`.jsonl` per iteration) | "chat history", "transcript" |

## Display

| Term | Definition | Avoid |
|------|-----------|-------|
| **Log-to-file mode** | Writes to `.sandcastle/logs/`. Default for `run()` | "file mode", "quiet mode" |
| **Terminal mode** | Interactive UI with spinners. Use via `logging: { type: 'stdout' }` | "stdout mode", "interactive mode" |
| **Agent stream event** | Single item in agent output (text chunk or tool call) | "log event", "display entry" |

## Key relationships

- `run()` accepts bind-mount and isolated providers. Not no-sandbox.
- `interactive()` accepts all three provider types.
- `createSandbox()` does not accept no-sandbox.
- No-sandbox provider does NOT pass `dangerouslySkipPermissions` to the agent.
- Sandbox providers are imported from subpaths (`sandcastle/sandboxes/docker`), not from the main entry point.
- Lifecycle ordering: `copyToWorktree` -> `host.onWorktreeReady` (sequential) -> sandbox created -> `host.onSandboxReady` + `sandbox.onSandboxReady` (parallel).
- Prompt argument substitution runs on the host BEFORE prompt expansion runs in the sandbox.
- Built-in prompt arguments cannot be overridden — passing them in `promptArgs` is an error.
- Unused prompt arguments produce a warning; missing ones produce an error in `run()`, a prompt in `interactive()`.

## Common ambiguities

- **"Provider"** — always qualify: agent provider or sandbox provider.
- **"Run"** — `run()` function or one iteration? Use "iteration" for single agent invocation.
- **"Local"** — ambiguous. Use "host" for the developer's machine.
- **"Container"** — Docker/Podman primitive. Use "sandbox" for the abstraction.
- **"Variable"** — prompt arguments are not env vars. Say "prompt argument" or "env var".
- **"Workspace"** — retired term. Use "worktree" or "sandbox".
