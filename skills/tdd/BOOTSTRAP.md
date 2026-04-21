# BOOTSTRAP.md — TDD subagent setup

The skill ships three subagents under `skills/tdd/agents/`:

- `tdd-red.md`
- `tdd-green.md`
- `tdd-refactor.md`

**Claude Code only discovers subagents from specific locations.** The skill folder isn't necessarily one of them. Until these files are at a discovery path, the main agent can't spawn them by name.

## What you (the agent) need to do

1. **Look up the current discovery rules.** Use the `claude-docs` skill to fetch the live subagent documentation. Don't trust any path a static document (including this one) names — discovery rules change between Claude Code versions.

   ```
   /claude-docs subagents
   ```

2. **From the docs, pick the scope** (project-level vs user-level vs anything else the current docs describe). Default to **project-level** unless the user explicitly asks for broader scope.

   > ⚠️ **Per the user's [global rules](~/.claude/CLAUDE.md):** never write to `~/.claude/` without the user's explicit, in-this-message permission. If the docs point at a user-scope path and the user hasn't OK'd that, ask first or have them do the copy themselves.

3. **Resolve the skill path.** This skill could live in any of: `~/.claude/skills/tdd/`, `<project>/.claude/skills/tdd/`, or wherever a plugin / dev install put it. Find it before the copy.

4. **Copy the three subagent files** from `<skill-path>/agents/` to whichever destination the docs identified.

5. **Verify.** Restart the Claude Code session (subagents load at session start) and check that `tdd-red`, `tdd-green`, `tdd-refactor` appear in `/agents`.

## What this BOOTSTRAP does NOT do

- Does not install hooks (this skill has none).
- Does not modify `settings.json` (this skill needs no settings).
- Does not create state directories or scaffolding files.
- Does not install dev dependencies — the project owns its tooling.

The whole skill is markdown. The "install" is one `cp` and a session restart, against whichever path the **current** docs say.
