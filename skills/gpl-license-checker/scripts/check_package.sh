#!/usr/bin/env bash
# Thin shell wrapper around check_package.py — picks python3 and keeps PATH sane.
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec python3 "$DIR/check_package.py" "$@"
