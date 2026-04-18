#!/usr/bin/env bash
# generate-logo.sh — Download Fluent 3D emoji PNGs and composite into a logo
#
# Usage:
#   generate-logo.sh --skill <skill-name>    # Generate logo for a specific skill
#   generate-logo.sh --all                   # Generate logos for all skills missing one
#   generate-logo.sh --repo                  # Generate the repo-level logo
#   generate-logo.sh --emojis "🏭🔍" --output path/to/logo.png  # Custom
#
# Requires: python3, Pillow (pip install Pillow), curl

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
CACHE_DIR="${HOME}/.cache/factory-branding/fluent-emoji"
COMPOSE_SCRIPT="$SCRIPT_DIR/compose_logo.py"

# Emoji name to Fluent 3D asset folder mapping
declare -A EMOJI_FOLDERS=(
  ["🏭"]="Factory"
  ["🔍"]="Magnifying glass tilted left"
  ["🎨"]="Artist palette"
  ["📡"]="Satellite antenna"
  ["📋"]="Clipboard"
  ["📊"]="Bar chart"
  ["🔬"]="Microscope"
  ["✨"]="Sparkles"
  ["🎪"]="Circus tent"
)

# Skill to emoji suffix mapping
declare -A SKILL_EMOJIS=(
  ["auto-format"]="🏭 🎨"
  ["langfuse-tracing"]="🏭 📡"
  ["prd-karpathy-style"]="🏭 📋"
  ["qmd-search"]="🏭 🔍"
  ["factory-branding"]="🏭 🎪"
)

# Repo-level emojis (factory goes last here)
REPO_EMOJIS="📊 🔬 ✨ 🏭"

download_emoji() {
  local emoji="$1"
  local folder="${EMOJI_FOLDERS[$emoji]:-}"

  if [[ -z "$folder" ]]; then
    echo "ERROR: No Fluent folder mapping for emoji: $emoji"
    return 1
  fi

  local safe_name
  safe_name=$(echo "$folder" | tr ' ' '_' | tr '[:upper:]' '[:lower:]')
  local cache_path="$CACHE_DIR/${safe_name}_3d.png"

  if [[ -f "$cache_path" ]]; then
    echo "$cache_path"
    return 0
  fi

  mkdir -p "$CACHE_DIR"

  # URL-encode the folder name for GitHub raw URL
  local encoded_folder
  encoded_folder=$(python3 -c "import urllib.parse; print(urllib.parse.quote('$folder'))")
  local url="https://raw.githubusercontent.com/microsoft/fluentui-emoji/main/assets/${encoded_folder}/3D/${safe_name}_3d.png"

  echo "Downloading: $folder..." >&2
  if curl -fsSL "$url" -o "$cache_path" 2>/dev/null; then
    echo "$cache_path"
  else
    echo "ERROR: Failed to download $url" >&2
    rm -f "$cache_path"
    return 1
  fi
}

generate_for_emojis() {
  local emoji_string="$1"
  local output="$2"

  local image_paths=()
  for emoji in $emoji_string; do
    local path
    path=$(download_emoji "$emoji")
    image_paths+=("$path")
  done

  python3 "$COMPOSE_SCRIPT" --images "${image_paths[@]}" --output "$output"
}

generate_for_skill() {
  local skill="$1"
  local emojis="${SKILL_EMOJIS[$skill]:-}"

  if [[ -z "$emojis" ]]; then
    echo "ERROR: No emoji mapping for skill: $skill"
    echo "Add it to SKILL_EMOJIS in this script and to SKILL.md suffix table."
    exit 1
  fi

  local output="$REPO_ROOT/skills/$skill/logo.png"
  echo "Generating logo for $skill..."
  generate_for_emojis "$emojis" "$output"
}

# Parse arguments
case "${1:-}" in
  --skill)
    [[ -z "${2:-}" ]] && echo "Usage: $0 --skill <skill-name>" && exit 1
    generate_for_skill "$2"
    ;;

  --all)
    for skill in "${!SKILL_EMOJIS[@]}"; do
      if [[ ! -f "$REPO_ROOT/skills/$skill/logo.png" ]]; then
        generate_for_skill "$skill"
      else
        echo "Skipping $skill (logo.png exists)"
      fi
    done
    ;;

  --repo)
    echo "Generating repo-level logo..."
    generate_for_emojis "$REPO_EMOJIS" "$REPO_ROOT/logo.png"
    ;;

  --emojis)
    [[ -z "${2:-}" || -z "${3:-}" || "$3" != "--output" || -z "${4:-}" ]] && \
      echo "Usage: $0 --emojis \"🏭🔍\" --output path/to/logo.png" && exit 1
    generate_for_emojis "$2" "$4"
    ;;

  *)
    echo "Usage:"
    echo "  $0 --skill <skill-name>              Generate logo for a specific skill"
    echo "  $0 --all                              Generate logos for all skills missing one"
    echo "  $0 --repo                             Generate the repo-level logo"
    echo "  $0 --emojis \"🏭 🔍\" --output logo.png  Custom emoji composition"
    exit 1
    ;;
esac
