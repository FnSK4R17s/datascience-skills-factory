#!/usr/bin/env bash
# log-antipattern.sh — append a new anti-pattern entry to ANTIPATTERNS.md.
# Usage:
#   log-antipattern.sh "<one-line summary>" "<correct approach>" ["<context>"]
#
# Inserts the new entry directly after the "<!-- New entries go below this line, newest first. -->"
# marker so the file stays sorted newest-first.
# If ANTIPATTERNS.md is missing, prints an error and exits non-zero.

set -euo pipefail

if [[ $# -lt 2 ]]; then
  echo "Usage: $0 <summary> <correct-approach> [context]" >&2
  exit 2
fi

SUMMARY="$1"
CORRECT="$2"
CONTEXT="${3:-}"

TARGET="${ANTIPATTERNS_FILE:-$(pwd)/ANTIPATTERNS.md}"

if [[ ! -f "$TARGET" ]]; then
  echo "Error: $TARGET not found. Run repo-best-practices BOOTSTRAP.md first." >&2
  exit 1
fi

DATE=$(date +%Y-%m-%d)
MARKER="<!-- New entries go below this line, newest first. -->"

ENTRY="## ${DATE} — ${SUMMARY}

**What went wrong:** (filled by agent — describe the mistake)

**Correct approach:** ${CORRECT}"

if [[ -n "$CONTEXT" ]]; then
  ENTRY+="

**Context:** ${CONTEXT}"
fi

ENTRY+="

---
"

# Insert after the marker line. Use awk for portability.
TMP=$(mktemp)
awk -v marker="$MARKER" -v entry="$ENTRY" '
  { print }
  $0 == marker && !inserted {
    print ""
    print entry
    inserted = 1
  }
' "$TARGET" > "$TMP"

# If the marker was missing, append entry at end and warn.
if ! grep -qF "$MARKER" "$TARGET"; then
  echo "Warning: marker line missing from $TARGET — appending at end." >&2
  cat "$TARGET" > "$TMP"
  printf '\n%s\n' "$ENTRY" >> "$TMP"
fi

mv "$TMP" "$TARGET"

echo "Logged anti-pattern to $TARGET:"
echo "  ${DATE} — ${SUMMARY}"
