#!/usr/bin/env bash
# bootstrap.sh — first-run scaffolder for repo-best-practices.
# Creates CLAUDE.md, ANTIPATTERNS.md, and AGENTS.md→CLAUDE.md symlink at the
# current working directory (assumed to be the repo root).
# Idempotent: skips files that already exist.

set -euo pipefail

SKILL_DIR="${CLAUDE_SKILL_DIR:-$(cd "$(dirname "$0")/.." && pwd)}"
ASSET_DIR="${SKILL_DIR}/assets"
TARGET_DIR="${1:-$(pwd)}"

cd "$TARGET_DIR"

created=()
skipped=()

# CLAUDE.md
if [[ -e CLAUDE.md ]]; then
  skipped+=("CLAUDE.md (exists)")
else
  cp "${ASSET_DIR}/CLAUDE.md" CLAUDE.md
  created+=("CLAUDE.md")
fi

# ANTIPATTERNS.md
if [[ -e ANTIPATTERNS.md ]]; then
  skipped+=("ANTIPATTERNS.md (exists)")
else
  cp "${ASSET_DIR}/ANTIPATTERNS.md" ANTIPATTERNS.md
  created+=("ANTIPATTERNS.md")
fi

# AGENTS.md symlink
if [[ -e AGENTS.md || -L AGENTS.md ]]; then
  skipped+=("AGENTS.md (exists)")
else
  ln -s CLAUDE.md AGENTS.md
  created+=("AGENTS.md → CLAUDE.md")
fi

echo "Bootstrap complete in: $TARGET_DIR"
echo
if (( ${#created[@]} > 0 )); then
  echo "Created:"
  printf '  - %s\n' "${created[@]}"
fi
if (( ${#skipped[@]} > 0 )); then
  echo "Skipped:"
  printf '  - %s\n' "${skipped[@]}"
fi
echo
echo "Next: open CLAUDE.md and fill in 'Project summary' + 'Conventions'."
