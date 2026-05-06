# Sandcastle API Surface

Package: `@ai-hero/sandcastle`

## Top-level exports

```typescript
// Functions
export { run } from "./run.js";
export { interactive } from "./interactive.js";
export { createSandbox } from "./createSandbox.js";
export { createWorktree } from "./createWorktree.js";

// Agent providers
export { claudeCode, codex, opencode, pi } from "./AgentProvider.js";

// Sandbox provider factories
export { createBindMountSandboxProvider, createIsolatedSandboxProvider } from "./SandboxProvider.js";

// Session management
export { hostSessionStore, sandboxSessionStore, transferSession } from "./SessionStore.js";
export { SessionPaths, sessionPathsLayer, defaultSessionPathsLayer } from "./SessionPaths.js";

// Error types
export { CwdError } from "./resolveCwd.js";
```

## RunOptions

```typescript
interface RunOptions {
  agent: AgentProvider;
  sandbox: SandboxProvider;
  cwd?: string;                        // defaults to process.cwd()
  prompt?: string;                     // mutually exclusive with promptFile
  promptFile?: string;                 // resolved against process.cwd(), not cwd
  maxIterations?: number;              // default: 1
  hooks?: SandboxHooks;
  promptArgs?: PromptArgs;             // Record<string, string>
  logging?: LoggingOption;             // "file" (default) or "stdout"
  completionSignal?: string | string[]; // default: "<promise>COMPLETE</promise>"
  idleTimeoutSeconds?: number;         // default: 600
  name?: string;
  copyToWorktree?: string[];
  branchStrategy?: BranchStrategy;
  resumeSession?: string;             // incompatible with maxIterations > 1
  signal?: AbortSignal;
  timeouts?: Timeouts;
}
```

## RunResult

```typescript
interface RunResult {
  iterations: IterationResult[];
  completionSignal?: string;
  stdout: string;
  commits: { sha: string }[];
  branch: string;
  logFilePath?: string;
  preservedWorktreePath?: string;
}
```

## CreateSandboxOptions

```typescript
interface CreateSandboxOptions {
  branch: string;                      // explicit branch, required
  baseBranch?: string;                 // ref to fork from if branch doesn't exist
  sandbox: SandboxProvider;
  cwd?: string;
  hooks?: SandboxHooks;
  copyToWorktree?: string[];
  timeouts?: Timeouts;
}
```

## Sandbox handle

```typescript
interface Sandbox {
  readonly branch: string;
  readonly worktreePath: string;
  run(options: SandboxRunOptions): Promise<SandboxRunResult>;
  interactive(options: SandboxInteractiveOptions): Promise<SandboxInteractiveResult>;
  close(): Promise<CloseResult>;
  [Symbol.asyncDispose](): Promise<void>;
}
```

## CreateWorktreeOptions

```typescript
type WorktreeBranchStrategy = MergeToHeadBranchStrategy | NamedBranchStrategy;
// head is excluded — it's a type error

interface CreateWorktreeOptions {
  branchStrategy: WorktreeBranchStrategy;
  cwd?: string;
  copyToWorktree?: string[];
  hooks?: SandboxHooks;
  timeouts?: Timeouts;
}
```

## Worktree handle

```typescript
interface Worktree {
  readonly branch: string;
  readonly worktreePath: string;
  run(options: WorktreeRunOptions): Promise<WorktreeRunResult>;
  interactive(options: WorktreeInteractiveOptions): Promise<InteractiveResult>;
  createSandbox(options: WorktreeCreateSandboxOptions): Promise<Sandbox>;
  close(): Promise<CloseResult>;
  [Symbol.asyncDispose](): Promise<void>;
}
```

## Agent provider options

```typescript
interface ClaudeCodeOptions {
  effort?: "low" | "medium" | "high" | "max";  // max is Opus-only
  env?: Record<string, string>;
  captureSessions?: boolean;                    // default: true
}

interface CodexOptions {
  effort?: "low" | "medium" | "high" | "xhigh";
  env?: Record<string, string>;
}

interface PiOptions {
  env?: Record<string, string>;
}

interface OpenCodeOptions {
  env?: Record<string, string>;
}
```

## Branch strategy types

```typescript
type BranchStrategy = HeadBranchStrategy | MergeToHeadBranchStrategy | NamedBranchStrategy;

interface HeadBranchStrategy { type: "head" }
interface MergeToHeadBranchStrategy { type: "merge-to-head" }
interface NamedBranchStrategy { type: "branch"; branch: string; baseBranch?: string }
```

## SandboxHooks

```typescript
interface SandboxHooks {
  host?: {
    onWorktreeReady?: HookConfig[];
    onSandboxReady?: HookConfig[];
  };
  sandbox?: {
    onSandboxReady?: HookConfig[];
  };
}

interface HookConfig {
  command: string;
  sudo?: boolean;         // sandbox-only
  timeoutMs?: number;     // default: 60_000
}
```

## LoggingOption

```typescript
type LoggingOption =
  | { type: "file"; path: string; onAgentStreamEvent?: (event: AgentStreamEvent) => void }
  | { type: "stdout" };
```

## Sandbox provider imports

```typescript
// Docker
import { docker } from "@ai-hero/sandcastle/sandboxes/docker";

// Podman
import { podman } from "@ai-hero/sandcastle/sandboxes/podman";

// Vercel (Firecracker microVMs)
import { vercel } from "@ai-hero/sandcastle/sandboxes/vercel";

// No sandbox (host, interactive only)
import { noSandbox } from "@ai-hero/sandcastle";
```
