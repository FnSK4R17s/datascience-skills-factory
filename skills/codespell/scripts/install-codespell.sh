#!/usr/bin/env bash
# install-codespell.sh — install codespell and (optionally) the pre-commit runner.
# Usage:
#   install-codespell.sh                    # install codespell only
#   install-codespell.sh --pre-commit       # also install pre-commit runner
#   install-codespell.sh --all              # codespell + pre-commit
#
# Prefers uv > pipx > pip --user for isolated CLI installs.

set -euo pipefail

WANT_PRECOMMIT=false
case "${1:-}" in
  --pre-commit|--all) WANT_PRECOMMIT=true ;;
esac

install_tool() {
  local tool="$1"
  if command -v "$tool" >/dev/null 2>&1; then
    echo "skip: $tool already installed ($($tool --version 2>&1 | head -1))"
    return 0
  fi
  echo "installing: $tool"
  if command -v uv >/dev/null 2>&1; then
    uv tool install "$tool"
  elif command -v pipx >/dev/null 2>&1; then
    pipx install "$tool"
  elif command -v pip >/dev/null 2>&1; then
    pip install --user "$tool"
  else
    echo "ERROR: need one of uv, pipx, or pip to install $tool" >&2
    return 1
  fi
}

install_tool codespell

if [[ "$WANT_PRECOMMIT" == true ]]; then
  install_tool pre-commit
fi

echo ""
echo "=== versions ==="
codespell --version 2>&1 | head -1
if [[ "$WANT_PRECOMMIT" == true ]]; then
  pre-commit --version 2>&1 | head -1
fi
