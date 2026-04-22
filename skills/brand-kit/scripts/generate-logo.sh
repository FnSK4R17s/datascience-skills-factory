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
EMOJI_MAP="$SCRIPT_DIR/../references/emoji-folders.json"

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

# ── Emoji → Fluent asset path lookup ─────────────────────────────
# Canonical mapping lives in references/emoji-folders.json, generated
# from microsoft/fluentui-emoji via scripts/build-emoji-map.py.
#
# Precedence for a given emoji:
#   1. branding.yml `emoji_folders:` override (per-ecosystem escape hatch)
#   2. references/emoji-folders.json (ships with the skill; ~3145 entries)

if [[ ! -f "$EMOJI_MAP" ]]; then
  echo "ERROR: emoji map not found: $EMOJI_MAP" >&2
  echo "Run scripts/build-emoji-map.py to regenerate." >&2
  exit 1
fi

# Return the Fluent folder name for a given emoji, consulting the config
# override first and falling back to the JSON map. Empty string on miss.
lookup_folder() {
  local emoji="$1"
  python3 - "$CONFIG" "$EMOJI_MAP" "$emoji" <<'PY'
import json, sys, yaml
cfg_path, map_path, emoji = sys.argv[1], sys.argv[2], sys.argv[3]
with open(cfg_path) as f:
    cfg = yaml.safe_load(f) or {}
override = (cfg.get("emoji_folders") or {}).get(emoji)
if override:
    print(override)
    sys.exit(0)
with open(map_path, encoding="utf-8") as f:
    mapping = json.load(f)
entry = mapping.get(emoji)
if entry:
    print(entry["folder"])
PY
}

# Return the asset subpath (relative to assets/ on GitHub) for a given
# emoji. Config override yields just a folder name; if so, we synthesize
# the default "<Folder>/3D/<slug>_3d.png" path.
lookup_asset_path() {
  local emoji="$1"
  python3 - "$CONFIG" "$EMOJI_MAP" "$emoji" <<'PY'
import json, sys, yaml
cfg_path, map_path, emoji = sys.argv[1], sys.argv[2], sys.argv[3]
with open(cfg_path) as f:
    cfg = yaml.safe_load(f) or {}
override_folder = (cfg.get("emoji_folders") or {}).get(emoji)
if override_folder:
    slug = override_folder.replace(" ", "_").lower()
    print(f"{override_folder}/3D/{slug}_3d.png")
    sys.exit(0)
with open(map_path, encoding="utf-8") as f:
    mapping = json.load(f)
entry = mapping.get(emoji)
if entry:
    print(entry["asset_path"])
PY
}

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

  local asset_path
  asset_path="$(lookup_asset_path "$emoji")"
  if [[ -z "$asset_path" ]]; then
    echo "ERROR: No Fluent mapping for emoji: $emoji" >&2
    echo "  Either add an override to '$CONFIG' under 'emoji_folders:'," >&2
    echo "  or refresh '$EMOJI_MAP' via scripts/build-emoji-map.py." >&2
    return 1
  fi

  local folder
  folder="$(lookup_folder "$emoji")"

  # Cache key = the asset path, flattened into a filesystem-safe name.
  local cache_key
  cache_key="$(echo -n "$asset_path" | tr '/' '_' | tr ' ' '_')"
  local cache_path="$CACHE_DIR/$cache_key"

  if [[ -f "$cache_path" ]]; then
    echo "$cache_path"
    return 0
  fi

  mkdir -p "$CACHE_DIR"

  local encoded_path
  encoded_path=$(python3 -c "
import sys, urllib.parse
print('/'.join(urllib.parse.quote(p) for p in sys.argv[1].split('/')))
" "$asset_path")

  local url="https://raw.githubusercontent.com/microsoft/fluentui-emoji/main/assets/${encoded_path}"

  echo "Downloading: $folder..." >&2
  if curl -fsSL "$url" -o "$cache_path" 2>/dev/null; then
    echo "$cache_path"
  else
    echo "ERROR: Failed to download $folder" >&2
    echo "  URL: $url" >&2
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
