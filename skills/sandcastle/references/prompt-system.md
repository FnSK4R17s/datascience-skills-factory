# Prompt System

Sandcastle's prompt system has two modes: literal inline prompts and
file-based prompts with substitution.

## Inline prompts (`prompt:`)

Passed **literally** to the agent. No substitution, no shell expansion, no
built-in arg injection.

```typescript
await run({
  agent: claudeCode("claude-opus-4-6"),
  sandbox: docker(),
  prompt: "Fix the failing tests in src/auth.ts",
});
```

Passing `promptArgs` alongside an inline `prompt:` is a runtime error.

## File prompts (`promptFile:`)

Enable `{{KEY}}` substitution and `` !`command` `` shell expansion.

```typescript
await run({
  agent: claudeCode("claude-opus-4-6"),
  sandbox: docker(),
  promptFile: ".sandcastle/prompt.md",
  promptArgs: { ISSUE_NUMBER: "42" },
});
```

`promptFile` is resolved against `process.cwd()`, not the `cwd` option.

## `{{KEY}}` substitution

- Filled from `promptArgs: { KEY: "value" }`.
- Missing key = runtime error.
- Unused key = warning.
- Runs on the **host** before shell expansion.

## Shell expansion (`` !`command` ``)

Lines beginning with `` !`...` `` are replaced by the command's stdout.

- Commands run **inside the sandbox** in parallel.
- Execute after `sandbox.onSandboxReady` hooks complete.
- Non-zero exit fails the run immediately.
- `{{KEY}}` placeholders inside `` !`...` `` blocks are filled first.

```markdown
# Recent commits
!`git log -n 10 --format="%H %s"`

# Current test output
!`npm test 2>&1 | tail -50`

# Issue body
!`gh issue view {{ISSUE_NUMBER}} --json body -q .body`
```

## Built-in placeholders

| Placeholder | Value | Source |
|-------------|-------|--------|
| `{{SOURCE_BRANCH}}` | Branch the agent works on | Branch strategy |
| `{{TARGET_BRANCH}}` | Host's active branch at `run()` time | `git` |

Both are **auto-injected**. Passing them via `promptArgs` is a runtime error.

## Safety

`` !`...` `` patterns inside argument *values* are treated as inert text —
they are NOT executed. Safe to pipe user-authored content (issue titles, PR
bodies) through `promptArgs`.

## Expansion order

1. `{{KEY}}` substitution (host-side)
2. `` !`command` `` expansion (sandbox-side, in parallel)

## Completion signal

The agent's `<promise>COMPLETE</promise>` (or override via `completionSignal`)
is a convention you tell the agent about in the prompt. Sandcastle watches
for the substring in agent output but never injects it.

```markdown
Once complete, output <promise>COMPLETE</promise>.
```
