#!/usr/bin/env bash
# codespell-hook.sh — PostToolUse hook for Edit|Write events.
# Reads tool input JSON from stdin, extracts file_path, runs codespell -w on it.
# Exit 0 always — a spell-fix must never block an edit.

set -euo pipefail

# No-op if codespell is not installed.
command -v codespell >/dev/null 2>&1 || exit 0

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null || echo "")

[[ -z "$FILE_PATH" ]] && exit 0
[[ -f "$FILE_PATH" ]] || exit 0

# Skip binaries and large files quickly.
case "${FILE_PATH##*.}" in
  png|jpg|jpeg|gif|webp|ico|pdf|zip|tar|tgz|gz|xz|bz2|so|dll|dylib|exe|bin|wasm|woff|woff2|ttf|otf|eot|class|jar|whl|pyc|pyo)
    exit 0
    ;;
esac

# If the file lives in a repo with a .codespellrc, codespell picks it up
# automatically when run from that directory. cd to the file's directory
# so repo-local config applies.
REPO_ROOT=$(git -C "$(dirname "$FILE_PATH")" rev-parse --show-toplevel 2>/dev/null || dirname "$FILE_PATH")

(
  cd "$REPO_ROOT" && \
  codespell --write-changes --quiet-level=2 "$FILE_PATH" >/dev/null 2>&1 || true
)

exit 0
