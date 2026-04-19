#!/usr/bin/env bash
# load-antipatterns.sh — SessionStart hook that injects the top N anti-patterns
# from ANTIPATTERNS.md as a system reminder.
#
# Hook contract:
#   - Reads SessionStart event JSON from stdin (we ignore the input).
#   - Writes a JSON object to stdout with `additionalContext` for the model.
#   - Exit 0 even if the file is missing — never block session start.
#
# Configurable via env:
#   ANTIPATTERNS_FILE — path to ANTIPATTERNS.md (default: $CWD/ANTIPATTERNS.md)
#   ANTIPATTERNS_TOP_N — how many entries to include (default: 10)

set -euo pipefail

TARGET="${ANTIPATTERNS_FILE:-$(pwd)/ANTIPATTERNS.md}"
TOP_N="${ANTIPATTERNS_TOP_N:-10}"

# Drain stdin so the harness doesn't see a broken pipe.
cat >/dev/null || true

if [[ ! -f "$TARGET" ]]; then
  echo '{}'
  exit 0
fi

# Extract the first N real entries.
# An entry starts with "## YYYY-MM-DD " and ends at the next "---" line.
# The leading date guard skips the template's example block.
ENTRIES=$(awk -v n="$TOP_N" '
  BEGIN { count = 0; in_entry = 0 }
  /^## [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9] / {
    if (count >= n) exit
    in_entry = 1
    count++
  }
  in_entry { print }
  /^---$/ && in_entry {
    in_entry = 0
    print ""
  }
' "$TARGET")

if [[ -z "$ENTRIES" ]]; then
  echo '{}'
  exit 0
fi

# Build the system reminder text.
CONTEXT="Repo anti-patterns (top ${TOP_N} from ANTIPATTERNS.md). Read these before non-trivial work:

${ENTRIES}"

# Emit JSON with hookSpecificOutput.additionalContext.
# Use python (jq may not be present) for safe JSON encoding.
python3 -c "
import json, sys
print(json.dumps({
    'hookSpecificOutput': {
        'hookEventName': 'SessionStart',
        'additionalContext': sys.argv[1],
    }
}))
" "$CONTEXT"
