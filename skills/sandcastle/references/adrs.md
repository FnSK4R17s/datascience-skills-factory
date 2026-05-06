# Architecture Decision Records

Summary of ADRs from `docs/adr/` in the Sandcastle repo.

## ADR-0001: Per-step timeouts

Lifecycle steps (copyToWorktree, hooks) get individual configurable timeouts
via the `timeouts` option and per-hook `timeoutMs`. Default: 60s for hooks,
60s for copyToWorktree.

## ADR-0002: cwd option

`run()`, `createSandbox()`, and `createWorktree()` accept a `cwd` option to
override `process.cwd()` as the anchor for `.sandcastle/` paths and git
operations. Relative paths resolved against `process.cwd()`.

Note: `promptFile` is always resolved against `process.cwd()`, not `cwd`.

## ADR-0003: Reuse worktree by default

`createSandbox()` reuses an existing worktree if the branch already exists,
rather than failing or creating a new one. Reduces waste in CI environments
where the same branch is used across runs.

## ADR-0004: AbortSignal on run and interactive

All `run()`, `interactive()`, and sandbox `.run()` accept `signal: AbortSignal`.
Behavior:
- Pre-aborted signal rejects immediately without setup.
- Mid-iteration abort kills the agent subprocess.
- Worktree is preserved on disk after abort.
- Rejected promise surfaces `signal.reason` verbatim — no wrapping.
- The Sandbox/Worktree handle remains usable after abort.

## ADR-0005a: Remove chown UID alignment

Removed UID alignment between host and container users. The non-root `agent`
user inside the container has a fixed UID; bind-mount file ownership is
handled by Docker's user namespace mapping, not by aligning UIDs.

## ADR-0005b: Usage — raw tokens, no percentage

Token usage is reported as raw counts (inputTokens, cacheCreationInputTokens,
cacheReadInputTokens, outputTokens), not as percentages. Format: "103k"
representing total input-side tokens rounded up to nearest 1000.

## ADR-0006: Git worktree mounts on Windows

On Windows, git worktree paths use different mount resolution. The
`resolveGitMounts` function handles platform differences to correctly mount
the `.git` directory and worktree refs.

## ADR-0007: Worktree locking

Sandcastle uses git worktree locking to prevent concurrent cleanup of
worktrees that are in use. Stale worktrees are pruned at startup via
`WorktreeManager.pruneStale()`.

## ADR-0008: Inline prompts skip processing

Inline `prompt:` strings skip all preprocessing — no `{{KEY}}` substitution,
no `` !`command` `` expansion. This is intentional: inline prompts are for
quick, literal instructions where substitution would be surprising.

## ADR-0009: Templates — no shared code

Each template is a standalone directory with its own prompt files. Templates
do not share code or prompt fragments. This keeps each template
self-contained and independently modifiable.
