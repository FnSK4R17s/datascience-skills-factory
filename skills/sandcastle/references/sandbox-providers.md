# Sandbox Providers

Sandcastle abstracts sandbox runtimes behind a provider interface. Two kinds:
bind-mount and isolated.

## Built-in providers

### Docker (bind-mount)

```typescript
import { docker } from "@ai-hero/sandcastle/sandboxes/docker";

docker({
  imageName?: string,       // default: builds from .sandcastle/Dockerfile
  network?: string | string[], // Docker networks to attach
  env?: Record<string, string>,
})
```

Host worktree is bind-mounted into the container. Agent writes directly to
host filesystem through the mount.

### Podman (bind-mount)

```typescript
import { podman } from "@ai-hero/sandcastle/sandboxes/podman";

podman({
  imageName?: string,
  env?: Record<string, string>,
})
```

Same semantics as Docker but uses Podman runtime.

### Vercel (isolated)

```typescript
import { vercel } from "@ai-hero/sandcastle/sandboxes/vercel";

vercel({
  env?: Record<string, string>,
})
```

Firecracker microVM via `@vercel/sandbox`. Own filesystem — provider handles
`copyIn`/`copyFileOut` for file sync. Stronger isolation than bind-mount.

### noSandbox (host)

```typescript
import { noSandbox } from "@ai-hero/sandcastle";

noSandbox()
```

Runs directly on the host. Interactive sessions only — not for AFK agents.

## Two kinds

### Bind-mount

- Host worktree is mounted into the container.
- Agent writes directly to host filesystem.
- No file sync needed.
- Faster iteration.
- Default branch strategy: `head`.

### Isolated

- Sandbox has its own filesystem.
- Provider implements `copyIn` and `copyFileOut`.
- Sync overhead.
- Stronger isolation.
- Default branch strategy: `merge-to-head`.

## Custom providers

```typescript
import {
  createBindMountSandboxProvider,
  createIsolatedSandboxProvider,
} from "@ai-hero/sandcastle";
```

### Bind-mount custom provider

```typescript
const myProvider = createBindMountSandboxProvider({
  name: "my-runtime",
  sandboxHomedir: "/home/agent",
  env: { MY_VAR: "value" },
  create: async (options: BindMountCreateOptions) => {
    // options.worktreePath — host-side worktree path
    // options.hostRepoPath — host-side repo root
    // options.mounts — volume mounts to apply
    // options.env — environment variables
    return {
      worktreePath: "/workspace",
      exec: async (command, opts?) => { /* ... */ },
      interactiveExec: async (args, opts) => { /* ... */ },
      copyFileIn: async (hostPath, sandboxPath) => { /* ... */ },
      copyFileOut: async (sandboxPath, hostPath) => { /* ... */ },
      close: async () => { /* ... */ },
    };
  },
});
```

### Isolated custom provider

```typescript
const myProvider = createIsolatedSandboxProvider({
  name: "my-vm",
  env: { MY_VAR: "value" },
  create: async (options: IsolatedCreateOptions) => {
    // options.env — environment variables
    // options.copyPaths — paths to copy into the sandbox
    return {
      worktreePath: "/workspace",
      exec: async (command, opts?) => { /* ... */ },
      interactiveExec: async (args, opts) => { /* ... */ },
      copyFileIn: async (hostPath, sandboxPath) => { /* ... */ },
      copyFileOut: async (sandboxPath, hostPath) => { /* ... */ },
      close: async () => { /* ... */ },
    };
  },
});
```

## Environment merge rules

- Agent-provider env and sandbox-provider env **must not overlap** — overlap
  throws at `run()` time.
- Both override `.sandcastle/.env` resolver output.
- The strict no-overlap rule makes env leakage between layers explicit.

## Exec contract

Provider `exec()` implementations **must** support line-by-line streaming via
`onLine`. This is how Sandcastle delivers live feedback and enforces idle
timeouts. A buffered implementation that only calls `onLine` after the process
exits does NOT satisfy the contract.

## Default Dockerfile requirements

- Node.js 22 base image
- System deps: `git`, `curl`, `jq`
- GitHub CLI (`gh`)
- Claude Code CLI (`claude`)
- Non-root `agent` user (Claude refuses to run as root)
