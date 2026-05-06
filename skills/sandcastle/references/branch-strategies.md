# Branch Strategies

Branch strategy in Sandcastle controls how the agent's commits relate to the
host repo's branches. Configured per `run()` call, not per provider.

## Three strategies

### head

```typescript
{ type: "head" }
```

Agent writes directly to the host working directory. No worktree, no branch
indirection. Fastest iteration. **Bind-mount providers only** — isolated
providers reject this because the agent has no host-filesystem access.

Default for bind-mount providers (Docker, Podman).

`copyToWorktree` is not supported under `head`.

### merge-to-head

```typescript
{ type: "merge-to-head" }
```

Sandcastle creates a temp branch in a git worktree, the agent works on the
temp branch, and Sandcastle merges back to HEAD when done. Temp branch is
cleaned up after merge.

Safe default for unattended automation — if the run goes wrong, HEAD is
untouched.

Default for isolated providers (Vercel).

### branch

```typescript
{ type: "branch", branch: "agent/fix-42", baseBranch?: "main" }
```

Commits land on an explicitly named branch in a worktree. Use when you want a
stable named branch (e.g. for a PR), or when an outer orchestrator
(parallel-planner-with-review) multiplexes many runs onto distinct branches.

Never a default — always explicit.

`baseBranch` is optional: ref to fork from if `branch` doesn't exist.
Ignored when the branch already exists.

## Provider defaults

| Provider kind | Default strategy |
|--------------|-----------------|
| bind-mount (Docker, Podman) | `head` |
| isolated (Vercel) | `merge-to-head` |

## createWorktree constraint

`createWorktree({ branchStrategy })` accepts only `branch` and
`merge-to-head`. `head` is a **compile-time type error** — head means
no worktree.

## Built-in prompt arg coupling

The branch strategy determines:
- `{{SOURCE_BRANCH}}` — the branch the agent works on.
- `{{TARGET_BRANCH}}` — the host's active branch at `run()` time.

Both are auto-injected into `promptFile` prompts.

## When to use each

| Strategy | Use case |
|----------|---------|
| `head` | Fast local dev, no PR, bind-mount provider |
| `merge-to-head` | CI / unattended runs, protect HEAD from failures |
| `branch` | PRs, parallel multi-agent orchestration, stable branch names |
