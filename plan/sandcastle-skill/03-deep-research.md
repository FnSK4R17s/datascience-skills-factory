# Stage 3 — Deep Research

**Feature:** sandcastle-skill
**Date:** 2026-05-06

## Resolved questions

### Q: What is the exact import path structure?

- **Method:** source code scan of `src/index.ts` and `package.json`.
- **Finding:** Main package exports come from `@ai-hero/sandcastle`. Sandbox
  providers have subpath exports: `@ai-hero/sandcastle/sandboxes/docker`,
  `.../podman`, `.../vercel`. The `noSandbox()` function is exported from the
  main package. Source: `src__index.ts`, `package.json`.
- **Implication:** Skill must clearly distinguish main imports from subpath
  sandbox imports.

### Q: What are the exact runtime error conditions?

- **Method:** source code scan of `src/run.ts:282-327`.
- **Finding:** Five validated constraints:
  1. `head` + isolated provider = error
  2. `copyToWorktree` + `head` = error
  3. `resumeSession` + `maxIterations > 1` = error
  4. `promptArgs` + inline `prompt:` = error (via `validateNoArgsWithInlinePrompt`)
  5. `{{SOURCE_BRANCH}}`/`{{TARGET_BRANCH}}` in `promptArgs` = error (via
     `validateNoBuiltInArgOverride`)
- **Implication:** All five must be documented as gotchas.

### Q: What is the hooks API shape?

- **Method:** source code scan of `SandboxLifecycle.ts` types (referenced in
  `src/run.ts`).
- **Finding:** Hooks are grouped under a top-level `hooks` key with `host`
  and `sandbox` sub-objects. This avoids the duplicate-key problem of having
  `sandbox` as both a provider and a hooks namespace. Source: `RunOptions`
  interface in `src/run.ts:229`.
- **Implication:** Skill examples must use `hooks: { host: {...}, sandbox: {...} }`
  not top-level `host`/`sandbox` keys.

### Q: How does `promptFile` resolution differ from `cwd`?

- **Method:** ADR-0002 + source code.
- **Finding:** `promptFile` is resolved against `process.cwd()`, NOT against
  the `cwd` option. The README and ADR-0002 are explicit about this. Source:
  `RunOptions.promptFile` JSDoc in `src/run.ts:224-225`.
- **Implication:** Document this as a gotcha when using custom `cwd`.

## Risks surfaced

- Sandcastle is early-stage open source. The API may change between versions.
  The skill should point to the scraped docs as ground truth rather than
  hardcoding version-specific details.

## Scope check

- [x] Scope still matches Stage 2 v1
- [ ] Scope has grown — user must decide to split or accept
