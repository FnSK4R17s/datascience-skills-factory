#!/usr/bin/env bash
# install-hook.sh — merges a SessionStart hook into <repo>/.claude/settings.json
# that runs scripts/load-antipatterns.sh.
#
# Idempotent: if the hook (matched by command path containing 'load-antipatterns.sh')
# already exists, prints a message and exits 0.
#
# Requires: python3 (for safe JSON merge).

set -euo pipefail

SKILL_DIR="${CLAUDE_SKILL_DIR:-$(cd "$(dirname "$0")/.." && pwd)}"
HOOK_CMD="${SKILL_DIR}/scripts/load-antipatterns.sh"
TARGET_DIR="${1:-$(pwd)}"
SETTINGS="${TARGET_DIR}/.claude/settings.json"

mkdir -p "${TARGET_DIR}/.claude"

python3 - "$SETTINGS" "$HOOK_CMD" <<'PY'
import json, os, sys

settings_path = sys.argv[1]
hook_cmd = sys.argv[2]

if os.path.exists(settings_path):
    with open(settings_path) as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            print(f"Error: {settings_path} is not valid JSON. Refusing to overwrite.", file=sys.stderr)
            sys.exit(1)
else:
    data = {}

hooks = data.setdefault("hooks", {})
session_start = hooks.setdefault("SessionStart", [])

# Check for an existing matching hook.
for matcher_block in session_start:
    for h in matcher_block.get("hooks", []):
        if hook_cmd in h.get("command", ""):
            print(f"Hook already installed in {settings_path} — no changes.")
            sys.exit(0)

# Append a new matcher block (SessionStart matches all sources by default).
session_start.append({
    "hooks": [
        {"type": "command", "command": hook_cmd}
    ]
})

with open(settings_path, "w") as f:
    json.dump(data, f, indent=2)
    f.write("\n")

print(f"Installed SessionStart hook in {settings_path}:")
print(f"  command: {hook_cmd}")
PY
