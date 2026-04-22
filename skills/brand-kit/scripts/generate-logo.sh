#!/usr/bin/env bash
# generate-logo.sh — Read branding.yml, download Fluent 3D emoji PNGs, composite into logos
#
# Usage:
#   generate-logo.sh --config branding.yml --skill    <skill-name>
#   generate-logo.sh --config branding.yml --subrepo  <subrepo-name>
#   generate-logo.sh --config branding.yml --sibling  <sibling-name>
#   generate-logo.sh --config branding.yml --all              # all skills
#   generate-logo.sh --config branding.yml --all-subrepos     # all subrepos
#   generate-logo.sh --config branding.yml --all-siblings     # all siblings
#   generate-logo.sh --config branding.yml --everything       # skills + subrepos + siblings
#   generate-logo.sh --config branding.yml --repo             # repo-level logo
#
# Scope semantics:
#   skill     — directory under skills/ inside the repo containing branding.yml
#   subrepo   — repo nested inside this repo (default base: "." at repo root)
#   sibling   — repo adjacent on disk, outside this repo (default base: "..")
#
# Requires: python3, Pillow, PyYAML, curl

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CACHE_DIR="${HOME}/.cache/brand-kit/fluent-emoji"
COMPOSE_SCRIPT="$SCRIPT_DIR/compose_logo.py"

CONFIG=""
MODE=""
TARGET_NAME=""

# ── Parse arguments ──────────────────────────────────────────────

while [[ $# -gt 0 ]]; do
  case "$1" in
    --config)         CONFIG="$2"; shift 2 ;;
    --skill)          MODE="skill";   TARGET_NAME="$2"; shift 2 ;;
    --subrepo)        MODE="subrepo"; TARGET_NAME="$2"; shift 2 ;;
    --sibling)        MODE="sibling"; TARGET_NAME="$2"; shift 2 ;;
    --all)            MODE="all"; shift ;;
    --all-subrepos)   MODE="all-subrepos"; shift ;;
    --all-siblings)   MODE="all-siblings"; shift ;;
    --everything)     MODE="everything"; shift ;;
    --repo)           MODE="repo"; shift ;;
    *)                echo "Unknown flag: $1"; exit 1 ;;
  esac
done

if [[ -z "$CONFIG" ]]; then
  echo "ERROR: --config <path-to-branding.yml> is required"
  echo "Usage:"
  echo "  $0 --config branding.yml --skill    <skill-name>"
  echo "  $0 --config branding.yml --subrepo  <subrepo-name>"
  echo "  $0 --config branding.yml --sibling  <sibling-name>"
  echo "  $0 --config branding.yml --all | --all-subrepos | --all-siblings | --everything"
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
  ["🚦"]="Vertical traffic light"
  ["🐃"]="Water buffalo"
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
for name in cfg.get('skills') or {}:
    print(name)
"
}

yaml_subrepo_names() {
  python3 -c "
import yaml
with open('$CONFIG') as f:
    cfg = yaml.safe_load(f)
for name in cfg.get('subrepos') or {}:
    print(name)
"
}

yaml_sibling_names() {
  python3 -c "
import yaml
with open('$CONFIG') as f:
    cfg = yaml.safe_load(f)
for name in cfg.get('siblings') or {}:
    print(name)
"
}

# Resolve an absolute output directory for a subrepo or sibling entry.
# Order of precedence:
#   1. Per-entry `path:` (treated as relative to branding.yml's repo root, unless absolute)
#   2. `<scope>_base_path` + name
#
# Args: <scope: subrepos|siblings> <name> <default_base_path>
resolve_entry_dir() {
  local scope="$1"
  local name="$2"
  local default_base="$3"

  python3 - "$CONFIG" "$REPO_ROOT" "$scope" "$name" "$default_base" <<'PY'
import os, sys, yaml

config_path, repo_root, scope, name, default_base = sys.argv[1:6]

with open(config_path) as f:
    cfg = yaml.safe_load(f) or {}

entries = cfg.get(scope) or {}
if name not in entries:
    print(f"ERROR: '{name}' not found under '{scope}' in {config_path}", file=sys.stderr)
    sys.exit(1)

entry = entries[name] or {}
override = entry.get("path")

base_key = f"{scope}_base_path"
base = cfg.get(base_key, default_base)

if override:
    target = override if os.path.isabs(override) else os.path.join(repo_root, override)
else:
    base_abs = base if os.path.isabs(base) else os.path.join(repo_root, base)
    target = os.path.join(base_abs, name)

print(os.path.normpath(target))
PY
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

  # Fluent 3D layout has two shapes:
  #   (a) No skin tones: assets/<Folder>/3D/<name>_3d.png
  #   (b) Skin-toned:    assets/<Folder>/Default/3D/<name>_3d_default.png
  local base="https://raw.githubusercontent.com/microsoft/fluentui-emoji/main/assets/${encoded_folder}"
  local url_plain="${base}/3D/${safe_name}_3d.png"
  local url_default="${base}/Default/3D/${safe_name}_3d_default.png"

  echo "Downloading: $folder..." >&2
  if curl -fsSL "$url_plain" -o "$cache_path" 2>/dev/null; then
    echo "$cache_path"
  elif curl -fsSL "$url_default" -o "$cache_path" 2>/dev/null; then
    echo "$cache_path"
  else
    echo "ERROR: Failed to download $folder (tried plain + skin-tone-Default layouts)" >&2
    echo "  $url_plain" >&2
    echo "  $url_default" >&2
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

# Build emoji list for a subrepo or sibling entry.
# Same convention as skills: base mark first, suffix appended.
# Args: <scope: subrepos|siblings> <name>
get_entry_emojis() {
  local scope="$1"
  local name="$2"

  python3 - "$CONFIG" "$scope" "$name" <<'PY'
import sys, yaml

config_path, scope, name = sys.argv[1:4]
with open(config_path) as f:
    cfg = yaml.safe_load(f) or {}

for entry in cfg.get("base_mark", []):
    print(entry["emoji"])

entries = cfg.get(scope) or {}
if name not in entries:
    sys.exit(f"ERROR: '{name}' not found under '{scope}'")

for e in (entries[name] or {}).get("suffix", []):
    print(e)
PY
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

# ── Generate for a single subrepo or sibling ─────────────────────

generate_for_entry() {
  local scope="$1"       # subrepos | siblings
  local name="$2"
  local default_base="$3"

  local target_dir
  target_dir=$(resolve_entry_dir "$scope" "$name" "$default_base")

  if [[ ! -d "$target_dir" ]]; then
    echo "WARNING: Target directory does not exist: $target_dir" >&2
    echo "  Creating it so logo.png can be written." >&2
    mkdir -p "$target_dir"
  fi

  local output="$target_dir/logo.png"

  echo "Generating logo for $scope/$name → $output"

  local emojis=()
  while IFS= read -r e; do
    emojis+=("$e")
  done < <(get_entry_emojis "$scope" "$name")

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

run_all_skills() {
  while IFS= read -r skill; do
    [[ -z "$skill" ]] && continue
    if [[ ! -f "$REPO_ROOT/skills/$skill/logo.png" ]]; then
      generate_for_skill "$skill"
    else
      echo "Skipping skill/$skill (logo.png exists)"
    fi
  done < <(yaml_skill_names)
}

run_all_subrepos() {
  while IFS= read -r name; do
    [[ -z "$name" ]] && continue
    local target_dir
    target_dir=$(resolve_entry_dir "subrepos" "$name" ".")
    if [[ -f "$target_dir/logo.png" ]]; then
      echo "Skipping subrepo/$name (logo.png exists at $target_dir)"
    else
      generate_for_entry "subrepos" "$name" "."
    fi
  done < <(yaml_subrepo_names)
}

run_all_siblings() {
  while IFS= read -r name; do
    [[ -z "$name" ]] && continue
    local target_dir
    target_dir=$(resolve_entry_dir "siblings" "$name" "..")
    if [[ -f "$target_dir/logo.png" ]]; then
      echo "Skipping sibling/$name (logo.png exists at $target_dir)"
    else
      generate_for_entry "siblings" "$name" ".."
    fi
  done < <(yaml_sibling_names)
}

case "$MODE" in
  skill)
    generate_for_skill "$TARGET_NAME"
    ;;

  subrepo)
    generate_for_entry "subrepos" "$TARGET_NAME" "."
    ;;

  sibling)
    generate_for_entry "siblings" "$TARGET_NAME" ".."
    ;;

  all)
    run_all_skills
    ;;

  all-subrepos)
    run_all_subrepos
    ;;

  all-siblings)
    run_all_siblings
    ;;

  everything)
    run_all_skills
    run_all_subrepos
    run_all_siblings
    ;;

  repo)
    generate_for_repo
    ;;

  *)
    echo "ERROR: Specify one of: --skill, --subrepo, --sibling, --all, --all-subrepos, --all-siblings, --everything, --repo"
    exit 1
    ;;
esac
