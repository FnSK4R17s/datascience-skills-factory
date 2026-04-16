#!/usr/bin/env bash
# install-formatters.sh — Install missing formatters based on project detection
# Usage: install-formatters.sh [--python] [--js] [--rust] [--all] [--detect]
#   --detect  Auto-detect languages from current directory (default if no flags)

set -euo pipefail

INSTALL_PYTHON=false
INSTALL_JS=false
INSTALL_RUST=false

detect_languages() {
  if [[ -f pyproject.toml ]] || [[ -f setup.py ]] || [[ -f requirements.txt ]] || ls *.py &>/dev/null; then
    INSTALL_PYTHON=true
  fi
  if [[ -f package.json ]] || [[ -f tsconfig.json ]]; then
    INSTALL_JS=true
  fi
  if [[ -f Cargo.toml ]]; then
    INSTALL_RUST=true
  fi
}

# Parse arguments
if [[ $# -eq 0 ]] || [[ "$1" == "--detect" ]]; then
  detect_languages
else
  for arg in "$@"; do
    case "$arg" in
      --python) INSTALL_PYTHON=true ;;
      --js)     INSTALL_JS=true ;;
      --rust)   INSTALL_RUST=true ;;
      --all)    INSTALL_PYTHON=true; INSTALL_JS=true; INSTALL_RUST=true ;;
      *) echo "Unknown flag: $arg"; exit 1 ;;
    esac
  done
fi

INSTALLED=()
SKIPPED=()

# Python: ruff
if [[ "$INSTALL_PYTHON" == true ]]; then
  if command -v ruff &>/dev/null; then
    SKIPPED+=("ruff (already installed: $(ruff --version))")
  else
    echo "Installing ruff..."
    if command -v uv &>/dev/null; then
      uv tool install ruff
    elif command -v pipx &>/dev/null; then
      pipx install ruff
    else
      pip install --user ruff
    fi
    INSTALLED+=("ruff")
  fi
fi

# JavaScript/TypeScript: prettier
if [[ "$INSTALL_JS" == true ]]; then
  if npx prettier --version &>/dev/null 2>&1; then
    SKIPPED+=("prettier (already available via npx)")
  else
    echo "Installing prettier..."
    if command -v bun &>/dev/null; then
      bun add --dev prettier
    elif [[ -f package.json ]]; then
      npm install --save-dev prettier
    else
      npm init -y && npm install --save-dev prettier
    fi
    INSTALLED+=("prettier")
  fi
fi

# Rust: rustfmt
if [[ "$INSTALL_RUST" == true ]]; then
  if command -v rustfmt &>/dev/null; then
    SKIPPED+=("rustfmt (already installed: $(rustfmt --version 2>/dev/null || echo 'available'))")
  else
    echo "Installing rustfmt via rustup..."
    if command -v rustup &>/dev/null; then
      rustup component add rustfmt
      INSTALLED+=("rustfmt")
    else
      echo "ERROR: rustup not found. Install from https://rustup.rs"
      exit 1
    fi
  fi
fi

# Summary
echo ""
echo "=== Formatter Install Summary ==="
if [[ ${#INSTALLED[@]} -gt 0 ]]; then
  echo "Installed: ${INSTALLED[*]}"
fi
if [[ ${#SKIPPED[@]} -gt 0 ]]; then
  echo "Skipped:   ${SKIPPED[*]}"
fi
if [[ ${#INSTALLED[@]} -eq 0 ]] && [[ ${#SKIPPED[@]} -eq 0 ]]; then
  echo "No languages detected. Use --python, --js, --rust, or --all."
fi
