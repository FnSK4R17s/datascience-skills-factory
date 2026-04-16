#!/usr/bin/env bash
# auto-format.sh — PostToolUse hook for Edit|Write events
# Reads tool input JSON from stdin, extracts file_path, runs the appropriate formatter.
# Exit 0 always — formatting failure should not block edits.

set -euo pipefail

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

# No file path means nothing to format
[[ -z "$FILE_PATH" ]] && exit 0

# File must exist (could be a delete or failed write)
[[ -f "$FILE_PATH" ]] || exit 0

# Determine formatter by extension
EXT="${FILE_PATH##*.}"

case "$EXT" in
  py)
    if command -v ruff &>/dev/null; then
      ruff format --quiet "$FILE_PATH" 2>/dev/null || true
      ruff check --fix --quiet "$FILE_PATH" 2>/dev/null || true
    elif command -v black &>/dev/null; then
      black --quiet "$FILE_PATH" 2>/dev/null || true
    fi
    ;;

  js|jsx|ts|tsx|json|css|scss|html|md|yaml|yml)
    if command -v bunx &>/dev/null; then
      bunx prettier --write --log-level=error "$FILE_PATH" 2>/dev/null || true
    elif command -v npx &>/dev/null; then
      npx prettier --write --log-level=error "$FILE_PATH" 2>/dev/null || true
    fi
    ;;

  rs)
    if command -v rustfmt &>/dev/null; then
      rustfmt --edition 2021 --quiet "$FILE_PATH" 2>/dev/null || true
    fi
    ;;
esac

exit 0
