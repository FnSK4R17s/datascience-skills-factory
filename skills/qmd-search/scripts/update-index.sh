#!/usr/bin/env bash
# update-index.sh — PostToolUse hook to incrementally re-index after writes
# Reads tool input JSON from stdin, checks if the written file is in a qmd collection.
# If so, runs qmd update + embed for that collection.
# Exit 0 always — index failure should not block edits.

set -euo pipefail

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

# No file path means nothing to index
[[ -z "$FILE_PATH" ]] && exit 0

# File must exist
[[ -f "$FILE_PATH" ]] || exit 0

# Only index markdown files
EXT="${FILE_PATH##*.}"
[[ "$EXT" == "md" ]] || exit 0

# qmd must be installed
command -v qmd &>/dev/null || exit 0

# Run update + embed (qmd handles collection membership internally)
qmd update 2>/dev/null || true
qmd embed 2>/dev/null || true

exit 0
