# sandcastle-skill — Requirements

## Must

1. Accurately describe all three entry points: `run()`, `createSandbox()`,
   `createWorktree()` with their option types and return types.
2. Cover all four agent providers (claudeCode, codex, pi, opencode) with
   their specific options.
3. Cover all four sandbox providers (docker, podman, vercel, noSandbox) with
   import paths and kind classification.
4. Document the three branch strategies (head, merge-to-head, branch) with
   defaults, constraints, and when-to-use heuristics.
5. Document the prompt system: inline vs. file, `{{KEY}}` substitution,
   `` !`command` `` expansion, built-in placeholders, expansion order, safety
   guarantees.
6. Document hooks system: two scopes (host, sandbox), ordering, timeouts,
   sudo.
7. Document all five templates with their workflow shapes.
8. List all runtime error conditions (head + isolated, copyToWorktree + head,
   resumeSession + maxIterations > 1, promptArgs + inline, built-in arg
   override).
9. Include reference files for: API surface, branch strategies, prompt system,
   sandbox providers, templates, ADRs.

## Should

- Include the parallel-planner-with-review template's four-role workflow as a
  concrete multi-agent example.
- Document session capture/resume mechanics.
- Document cancellation via AbortSignal.
- Document environment variable merge rules and resolution order.
- Document `sandcastle init` scaffolding workflow.

## Won't

- Ship executable code or hooks. The skill is documentation-only.
- Cover Sandcastle's internal architecture (Effect layers, orchestrator).
- Cover specific model pricing or token limits.
- Hardcode version-specific API details that may change — point to the
  docs in `plan/sandcastle-skill/docs/` for those.
