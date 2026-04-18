#!/usr/bin/env bash
# install-qmd.sh — Install qmd (local hybrid search engine for markdown)
# Usage: install-qmd.sh [--check]
#   --check   Only verify installation, don't install

set -euo pipefail

CHECK_ONLY=false
[[ "${1:-}" == "--check" ]] && CHECK_ONLY=true

# Check if already installed
if command -v qmd &>/dev/null; then
  VERSION=$(qmd --version 2>/dev/null || echo "unknown")
  echo "qmd already installed: $VERSION"
  exit 0
fi

if [[ "$CHECK_ONLY" == true ]]; then
  echo "qmd is not installed."
  exit 1
fi

# Check runtime prerequisites
HAS_NODE=false
HAS_BUN=false

if command -v node &>/dev/null; then
  NODE_VER=$(node --version | sed 's/v//' | cut -d. -f1)
  if [[ "$NODE_VER" -ge 22 ]]; then
    HAS_NODE=true
  else
    echo "WARNING: Node.js $(node --version) found but qmd requires >= 22"
  fi
fi

if command -v bun &>/dev/null; then
  HAS_BUN=true
fi

if [[ "$HAS_NODE" == false ]] && [[ "$HAS_BUN" == false ]]; then
  echo "ERROR: qmd requires Node.js >= 22 or Bun >= 1.0.0"
  echo "Install Node.js: https://nodejs.org/"
  echo "Install Bun: https://bun.sh/"
  exit 1
fi

# Install via preferred package manager
echo "Installing qmd..."

if [[ "$HAS_BUN" == true ]]; then
  bun install -g @tobilu/qmd
elif [[ "$HAS_NODE" == true ]]; then
  npm install -g @tobilu/qmd
fi

# Verify
if command -v qmd &>/dev/null; then
  echo "qmd installed successfully: $(qmd --version 2>/dev/null || echo 'ok')"
else
  echo "ERROR: qmd install completed but binary not found in PATH"
  exit 1
fi
