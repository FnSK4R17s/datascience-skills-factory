# Hook config — SessionStart anti-pattern loader

The optional hook installed by `scripts/install-hook.sh` adds a `SessionStart`
entry to `<repo-root>/.claude/settings.json`. It runs `load-antipatterns.sh`,
which reads the top N entries from `ANTIPATTERNS.md` and injects them as a
system reminder visible to the agent at session start.

## Resulting settings.json shape

```json
{
  "hooks": {
    "SessionStart": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "/abs/path/to/skills/repo-best-practices/scripts/load-antipatterns.sh"
          }
        ]
      }
    ]
  }
}
```

If `.claude/settings.json` already has other hooks, the installer **merges** —
it does not overwrite. If a hook with the same command path is already present,
it's a no-op.

## How `load-antipatterns.sh` works

1. Reads `ANTIPATTERNS_FILE` (default: `<cwd>/ANTIPATTERNS.md`).
2. Extracts the first N entries (default `ANTIPATTERNS_TOP_N=10`) — each entry
   starts with `## ` and ends at the next `---` line.
3. Emits JSON: `{ "hookSpecificOutput": { "hookEventName": "SessionStart", "additionalContext": "<rendered entries>" } }`.
4. Claude Code merges `additionalContext` into the session's initial context.

If `ANTIPATTERNS.md` is missing or empty, the hook emits `{}` and exits 0 —
never blocks session start.

## Tuning

To change how many entries are injected, set `ANTIPATTERNS_TOP_N` in the
hook's environment (edit `.claude/settings.json` to add `"env"` to the hook
block, or wrap the command in a shell that sets it). Example:

```json
{
  "type": "command",
  "command": "ANTIPATTERNS_TOP_N=20 /abs/path/to/load-antipatterns.sh"
}
```

## When NOT to install

- Anti-patterns are already short or rare → on-demand `Read` is fine.
- Repo has many sessions per day and context cost matters → skip the hook.
- You don't trust the file to stay short → skip; use a `Stop` hook to nag the
  agent to check on demand instead.

## Uninstalling

Edit `.claude/settings.json` and remove the matching `SessionStart` entry, or
delete `.claude/settings.json` entirely if no other hooks are configured.
