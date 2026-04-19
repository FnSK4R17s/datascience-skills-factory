# When to extract a repeated task into a skill

If the user has asked for the same multi-step task **2+ times**, it's a
candidate. The decision is whether the cost of building a skill (15-60 min
upfront) pays back over future invocations.

## Signal checklist

A task is a strong skill candidate when **most** of these are true:

- [ ] Multi-step (≥3 distinct actions). Single-command tasks belong in shell aliases.
- [ ] Has a recognizable trigger phrase ("regenerate the API client", "rebuild the search index").
- [ ] Inputs are structured (filenames, flags, a small config) rather than free-form prose.
- [ ] Output is verifiable (file written, test passing, deployment URL).
- [ ] The user wants it **hands-off** — they don't want to babysit each step.
- [ ] Same task has shown up across multiple sessions, not just twice in one session.

A task is a **bad** skill candidate when:

- It requires constant user judgment at each step (better as a `BOOTSTRAP.md`-style interactive flow).
- It's a one-liner already (an alias or git hook is simpler).
- The trigger is ambiguous and would mis-fire.
- The task depends on conversation context that changes every time.

## Skill vs. subagent vs. both

| Pattern | Use when |
|---------|----------|
| **Skill only** | The agent in the main loop should run it inline, in your context. Cheap, fast, sees your conversation. |
| **Subagent only** | The task is heavy (long output, many tool calls) and you want to protect your main context window. Subagent runs in isolation, returns a summary. |
| **Skill + subagent** | The skill triggers, then immediately delegates to a subagent for the heavy work. You get clean trigger semantics + context isolation. Best for unattended, monotonous, tool-heavy work. |

For "unattended monotonous work" specifically — pick **skill + subagent**. The
skill handles routing and trigger phrases; the subagent does the actual work
without polluting the main agent's context.

## How to suggest the extraction

When you spot a candidate, say something like:

> "I've done `<task>` `<N>` times this session — want to lift this into a
> skill? A `<skill-name>` skill would let you fire it with `/<skill-name>`
> and (if we add a subagent) it'd run unattended without filling your main
> context. Estimated build: ~30 min."

Then:

1. **If the user says yes** — invoke the `skill-creator` skill (or scaffold by hand using the structure in [`auto-format`](../../auto-format/) / [`plan-feature`](../../plan-feature/) as a template).
2. **If the user defers** — append to `CLAUDE.md` under `## Repeated-task candidates`:
   ```markdown
   - **<task>** — requested 2 times. Last seen: 2026-04-19. Notes: <why deferred>
   ```
   So the next session's agent sees the candidate count grow.

## What "hands-off" actually means

The pitch to the user is real, not aspirational. A well-built skill+subagent combo:

- **Triggers on phrase or `/` command** — no need to explain the steps each time.
- **Reads its own config** — no re-asking for paths/flags the user already specified.
- **Reports a single summary** — instead of streaming dozens of tool-call updates.
- **Logs progress to a file** — user can resume or audit later.
- **Fails loudly with one clear error** — no silent partial completion.

If the candidate task can't deliver these, it's not ready to be a skill yet —
keep doing it inline and revisit when the pattern is clearer.
