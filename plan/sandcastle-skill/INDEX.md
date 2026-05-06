# Sandcastle Skill — Documentation Index

Local mirror. Source: mattpocock/sandcastle GitHub repo (README, docs/, ideas/, research/, src/templates/, CLAUDE.md, CONTEXT.md).
Scraped: 2026-05-06

## Core Documentation

| File | Title |
|------|-------|
| [docs/README.md](docs/README.md) | Sandcastle README — full API reference |
| [docs/CLAUDE.md](docs/CLAUDE.md) | Agent instructions for working in the repo |
| [docs/CONTEXT.md](docs/CONTEXT.md) | Project context and architecture |
| [docs/CHANGELOG.md](docs/CHANGELOG.md) | Changelog |

## Docs Site Content

| File | Title |
|------|-------|
| [docs/docs__content__docs__index.mdx](docs/docs__content__docs__index.mdx) | Getting Started |
| [docs/docs__content__docs__agents.mdx](docs/docs__content__docs__agents.mdx) | Agent Providers |
| [docs/docs__content__docs__configuration.mdx](docs/docs__content__docs__configuration.mdx) | Configuration |

## Architecture Decision Records

| File | Title |
|------|-------|
| [docs/docs__adr__0001-per-step-timeouts.md](docs/docs__adr__0001-per-step-timeouts.md) | Per-step timeouts |
| [docs/docs__adr__0002-cwd-option.md](docs/docs__adr__0002-cwd-option.md) | cwd option |
| [docs/docs__adr__0003-reuse-worktree-by-default.md](docs/docs__adr__0003-reuse-worktree-by-default.md) | Reuse worktree by default |
| [docs/docs__adr__0004-abort-signal-on-run-and-interactive.md](docs/docs__adr__0004-abort-signal-on-run-and-interactive.md) | AbortSignal on run and interactive |
| [docs/docs__adr__0005-remove-chown-uid-alignment.md](docs/docs__adr__0005-remove-chown-uid-alignment.md) | Remove chown UID alignment |
| [docs/docs__adr__0005-usage-raw-tokens-no-percentage.md](docs/docs__adr__0005-usage-raw-tokens-no-percentage.md) | Usage: raw tokens, no percentage |
| [docs/docs__adr__0006-git-worktree-mounts-on-windows.md](docs/docs__adr__0006-git-worktree-mounts-on-windows.md) | Git worktree mounts on Windows |
| [docs/docs__adr__0007-worktree-locking.md](docs/docs__adr__0007-worktree-locking.md) | Worktree locking |
| [docs/docs__adr__0008-inline-prompts-skip-processing.md](docs/docs__adr__0008-inline-prompts-skip-processing.md) | Inline prompts skip processing |
| [docs/docs__adr__0009-templates-no-shared-code.md](docs/docs__adr__0009-templates-no-shared-code.md) | Templates: no shared code |

## Internal Agent Docs

| File | Title |
|------|-------|
| [docs/docs__agents__adding-an-agent-provider.md](docs/docs__agents__adding-an-agent-provider.md) | Adding an agent provider |
| [docs/docs__agents__domain.md](docs/docs__agents__domain.md) | Domain model |
| [docs/docs__agents__issue-tracker.md](docs/docs__agents__issue-tracker.md) | Issue tracker |
| [docs/docs__agents__triage.md](docs/docs__agents__triage.md) | Triage |

## Ideas & Research

| File | Title |
|------|-------|
| [docs/ideas__config-and-hooks.md](docs/ideas__config-and-hooks.md) | Config and hooks |
| [docs/research__sandbox-provider-research.md](docs/research__sandbox-provider-research.md) | Sandbox provider research |

## Templates

| File | Title |
|------|-------|
| [docs/src__templates__blank__prompt.md](docs/src__templates__blank__prompt.md) | Blank template prompt |
| [docs/src__templates__simple-loop__prompt.md](docs/src__templates__simple-loop__prompt.md) | Simple loop prompt |
| [docs/src__templates__sequential-reviewer__implement-prompt.md](docs/src__templates__sequential-reviewer__implement-prompt.md) | Sequential reviewer: implement |
| [docs/src__templates__sequential-reviewer__review-prompt.md](docs/src__templates__sequential-reviewer__review-prompt.md) | Sequential reviewer: review |
| [docs/src__templates__sequential-reviewer__CODING_STANDARDS.md](docs/src__templates__sequential-reviewer__CODING_STANDARDS.md) | Sequential reviewer: coding standards |
| [docs/src__templates__parallel-planner__plan-prompt.md](docs/src__templates__parallel-planner__plan-prompt.md) | Parallel planner: plan |
| [docs/src__templates__parallel-planner__implement-prompt.md](docs/src__templates__parallel-planner__implement-prompt.md) | Parallel planner: implement |
| [docs/src__templates__parallel-planner__merge-prompt.md](docs/src__templates__parallel-planner__merge-prompt.md) | Parallel planner: merge |
| [docs/src__templates__parallel-planner-with-review__plan-prompt.md](docs/src__templates__parallel-planner-with-review__plan-prompt.md) | Parallel planner+review: plan |
| [docs/src__templates__parallel-planner-with-review__implement-prompt.md](docs/src__templates__parallel-planner-with-review__implement-prompt.md) | Parallel planner+review: implement |
| [docs/src__templates__parallel-planner-with-review__review-prompt.md](docs/src__templates__parallel-planner-with-review__review-prompt.md) | Parallel planner+review: review |
| [docs/src__templates__parallel-planner-with-review__merge-prompt.md](docs/src__templates__parallel-planner-with-review__merge-prompt.md) | Parallel planner+review: merge |
| [docs/src__templates__parallel-planner-with-review__CODING_STANDARDS.md](docs/src__templates__parallel-planner-with-review__CODING_STANDARDS.md) | Parallel planner+review: coding standards |

## TypeScript Source (API surface)

| File | Title |
|------|-------|
| [docs/src__index.ts](docs/src__index.ts) | Package exports |
| [docs/src__run.ts](docs/src__run.ts) | run() implementation |
| [docs/src__createSandbox.ts](docs/src__createSandbox.ts) | createSandbox() implementation |
| [docs/src__createWorktree.ts](docs/src__createWorktree.ts) | createWorktree() implementation |
| [docs/src__interactive.ts](docs/src__interactive.ts) | interactive() implementation |
| [docs/src__AgentProvider.ts](docs/src__AgentProvider.ts) | Agent provider types + built-ins |
| [docs/src__SandboxProvider.ts](docs/src__SandboxProvider.ts) | Sandbox provider types |
| [docs/src__sandboxes__docker.ts](docs/src__sandboxes__docker.ts) | Docker sandbox provider |
| [docs/src__sandboxes__podman.ts](docs/src__sandboxes__podman.ts) | Podman sandbox provider |
| [docs/src__sandboxes__vercel.ts](docs/src__sandboxes__vercel.ts) | Vercel sandbox provider |
| [docs/src__sandboxes__no-sandbox.ts](docs/src__sandboxes__no-sandbox.ts) | noSandbox() provider |
| [docs/src__PromptPreprocessor.ts](docs/src__PromptPreprocessor.ts) | Prompt preprocessing (!` ` expansion) |
| [docs/src__PromptArgumentSubstitution.ts](docs/src__PromptArgumentSubstitution.ts) | Prompt {{KEY}} substitution |
| [docs/src__errors.ts](docs/src__errors.ts) | Error types |
| [docs/src__WorktreeManager.ts](docs/src__WorktreeManager.ts) | Worktree management |
| [docs/src__EnvResolver.ts](docs/src__EnvResolver.ts) | .env resolver |
| [docs/src__mergeProviderEnv.ts](docs/src__mergeProviderEnv.ts) | Provider env merge logic |
| [docs/package.json](docs/package.json) | Package manifest |
