#!/usr/bin/env bash
# PreToolUse hook: reject Edit/Write on manifest files that would introduce a DENY-class dep.
#
# Claude Code passes the tool-use payload as JSON on stdin. We only care when the
# tool is Edit or Write and the target path is a known manifest. Otherwise we exit 0
# silently so the tool call proceeds.
#
# On DENY verdict, we exit 2 with a message on stderr — Claude Code surfaces the stderr
# back to the model as a blocking hook result.
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCAN="$DIR/scan_manifest.py"

payload="$(cat || true)"
[ -z "$payload" ] && exit 0

tool="$(printf '%s' "$payload" | python3 -c 'import json,sys;print(json.load(sys.stdin).get("tool_name",""))' 2>/dev/null || true)"
path="$(printf '%s' "$payload" | python3 -c 'import json,sys;d=json.load(sys.stdin);print((d.get("tool_input") or {}).get("file_path",""))' 2>/dev/null || true)"

[ -z "$path" ] && exit 0

case "$tool" in
  Edit|Write|MultiEdit) ;;
  *) exit 0 ;;
esac

case "$(basename "$path")" in
  pyproject.toml|package.json|Cargo.toml|go.mod) ;;
  requirements*.txt) ;;
  *) exit 0 ;;
esac

# Only block when the file currently exists — for a fresh file we can't scan the pre-write state.
[ -f "$path" ] || exit 0

if ! out="$(python3 "$SCAN" "$path" 2>&1)"; then
  rc=$?
  if [ "$rc" -ge 2 ]; then
    {
      echo "gpl-license-checker: blocking DENY-class dep in $path"
      echo "$out" | grep -E '^(DENY|ERROR)'
    } >&2
    exit 2
  fi
fi
exit 0
