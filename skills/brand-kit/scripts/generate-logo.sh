#!/usr/bin/env bash
# generate-logo.sh — Read branding.yml, download Fluent 3D emoji PNGs, composite into logos
#
# Usage:
#   generate-logo.sh --config branding.yml --skill <skill-name>
#   generate-logo.sh --config branding.yml --all
#   generate-logo.sh --config branding.yml --repo
#
# Requires: python3, Pillow, PyYAML, curl

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CACHE_DIR="${HOME}/.cache/brand-kit/fluent-emoji"
COMPOSE_SCRIPT="$SCRIPT_DIR/compose_logo.py"

CONFIG=""
MODE=""
SKILL_NAME=""

# ── Parse arguments ──────────────────────────────────────────────

while [[ $# -gt 0 ]]; do
  case "$1" in
    --config) CONFIG="$2"; shift 2 ;;
    --skill)  MODE="skill"; SKILL_NAME="$2"; shift 2 ;;
    --all)    MODE="all"; shift ;;
    --repo)   MODE="repo"; shift ;;
    *)        echo "Unknown flag: $1"; exit 1 ;;
  esac
done

if [[ -z "$CONFIG" ]]; then
  echo "ERROR: --config <path-to-branding.yml> is required"
  echo "Usage:"
  echo "  $0 --config branding.yml --skill <skill-name>"
  echo "  $0 --config branding.yml --all"
  echo "  $0 --config branding.yml --repo"
  exit 1
fi

if [[ ! -f "$CONFIG" ]]; then
  echo "ERROR: Config not found: $CONFIG"
  exit 1
fi

REPO_ROOT="$(cd "$(dirname "$CONFIG")" && pwd)"

# ── Emoji name to Fluent folder lookup ───────────────────────────
# This is the canonical mapping. Add new entries here when new emojis are used.

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
  ["🪢"]="Knot"
  ["⚓"]="Anchor"
  ["🦞"]="Lobster"
  ["🏠"]="House"
  ["🔐"]="Locked with key"
  ["💪"]="Flexed biceps"
  ["🔭"]="Telescope"
  ["📚"]="Books"
  ["🧠"]="Brain"
  ["🚪"]="Door"
  ["🧪"]="Test tube"
  ["🧬"]="Dna"
  ["📈"]="Chart increasing"
  ["🔧"]="Wrench"
  ["🌐"]="Globe with meridians"
  ["📦"]="Package"
  ["🔗"]="Link"
  ["⚡"]="High voltage"
  ["🛡️"]="Shield"
  ["📝"]="Memo"
  ["🎯"]="Direct hit"
  ["🔄"]="Counterclockwise arrows button"
  ["🏗️"]="Building construction"
  ["🗺️"]="World map"
  ["🧭"]="Compass"
)

# ── YAML parsing via Python (avoids yq dependency) ───────────────

yaml_get() {
  local key="$1"
  python3 -c "
import yaml, sys
with open('$CONFIG') as f:
    cfg = yaml.safe_load(f)
keys = '$key'.split('.')
v = cfg
for k in keys:
    if isinstance(v, list):
        v = v[int(k)]
    else:
        v = v[k]
print(v)
" 2>/dev/null
}

yaml_list() {
  local key="$1"
  python3 -c "
import yaml, sys
with open('$CONFIG') as f:
    cfg = yaml.safe_load(f)
keys = '$key'.split('.')
v = cfg
for k in keys:
    if isinstance(v, list):
        v = v[int(k)]
    else:
        v = v[k]
if isinstance(v, list):
    for item in v:
        print(item)
else:
    print(v)
"
}

yaml_skill_names() {
  python3 -c "
import yaml
with open('$CONFIG') as f:
    cfg = yaml.safe_load(f)
for name in cfg.get('skills', {}):
    print(name)
"
}

# ── Download a single Fluent 3D emoji PNG ────────────────────────

download_emoji() {
  local emoji="$1"
  local folder="${EMOJI_FOLDERS[$emoji]:-}"

  if [[ -z "$folder" ]]; then
    echo "ERROR: No Fluent folder mapping for emoji: $emoji" >&2
    echo "Add it to EMOJI_FOLDERS in generate-logo.sh" >&2
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

# ── Build emoji list for a skill ─────────────────────────────────

get_skill_emojis() {
  local skill="$1"

  # Base mark emojis
  local base_emojis
  base_emojis=$(python3 -c "
import yaml
with open('$CONFIG') as f:
    cfg = yaml.safe_load(f)
for entry in cfg['base_mark']:
    print(entry['emoji'])
")

  # Skill suffix emojis
  local suffix_emojis
  suffix_emojis=$(python3 -c "
import yaml
with open('$CONFIG') as f:
    cfg = yaml.safe_load(f)
for e in cfg['skills']['$skill']['suffix']:
    print(e)
")

  # Skills: base first, then suffix
  echo "$base_emojis"
  echo "$suffix_emojis"
}

# ── Composite a list of emojis into a logo ───────────────────────

generate_logo() {
  local output="$1"
  shift
  local emojis=("$@")

  local height
  height=$(yaml_get "defaults.pixel_height" 2>/dev/null || echo "168")
  local gap
  gap=$(yaml_get "defaults.gap" 2>/dev/null || echo "8")

  local image_paths=()
  for emoji in "${emojis[@]}"; do
    local path
    path=$(download_emoji "$emoji")
    image_paths+=("$path")
  done

  python3 "$COMPOSE_SCRIPT" \
    --images "${image_paths[@]}" \
    --output "$output" \
    --height "$height" \
    --gap "$gap"
}

# ── Generate for a single skill ─────────────────────────────────

generate_for_skill() {
  local skill="$1"
  local output="$REPO_ROOT/skills/$skill/logo.png"

  echo "Generating logo for $skill..."

  local emojis=()
  while IFS= read -r e; do
    emojis+=("$e")
  done < <(get_skill_emojis "$skill")

  generate_logo "$output" "${emojis[@]}"
}

# ── Generate repo-level logo ────────────────────────────────────

generate_for_repo() {
  local output_path
  output_path=$(yaml_get "repo.output" 2>/dev/null || echo "logo.png")
  local output="$REPO_ROOT/$output_path"

  echo "Generating repo-level logo..."

  local emojis=()
  while IFS= read -r e; do
    emojis+=("$e")
  done < <(yaml_list "repo.emojis")

  generate_logo "$output" "${emojis[@]}"
}

# ── Main dispatch ────────────────────────────────────────────────

case "$MODE" in
  skill)
    generate_for_skill "$SKILL_NAME"
    ;;

  all)
    while IFS= read -r skill; do
      if [[ ! -f "$REPO_ROOT/skills/$skill/logo.png" ]]; then
        generate_for_skill "$skill"
      else
        echo "Skipping $skill (logo.png exists)"
      fi
    done < <(yaml_skill_names)
    ;;

  repo)
    generate_for_repo
    ;;

  *)
    echo "ERROR: Specify --skill <name>, --all, or --repo"
    exit 1
    ;;
esac
