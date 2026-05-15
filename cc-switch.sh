#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROFILES_FILE="$SCRIPT_DIR/profiles.json"
# Allow override via env for testing
SETTINGS_FILE="${SETTINGS_FILE:-$HOME/.claude/settings.json}"
PREFERENCES_FILE="${PREFERENCES_FILE:-$SCRIPT_DIR/preferences.json}"

# ── helpers ──────────────────────────────────────────────────────────────────

die() { echo "Error: $1" >&2; exit 1; }

require_jq() {
  command -v jq &>/dev/null || die "jq is required. Install with: sudo apt install jq"
}

load_profile() {
  local name="$1"
  [[ -f "$PROFILES_FILE" ]] || die "profiles.json not found at $PROFILES_FILE"
  local profile
  profile=$(jq -e --arg p "$name" '.[$p] // empty' "$PROFILES_FILE" 2>/dev/null) \
    || die "Profile '$name' not found in profiles.json"
  echo "$profile"
}

get_preference() {
  local profile="$1" slot="$2"
  [[ -f "$PREFERENCES_FILE" ]] || return 0
  jq -r --arg p "$profile" --arg s "$slot" '.[$p][$s] // empty' "$PREFERENCES_FILE"
}

save_preference() {
  local profile="$1" slot="$2" value="$3"
  local current='{}'
  [[ -f "$PREFERENCES_FILE" ]] && current=$(cat "$PREFERENCES_FILE")
  echo "$current" \
    | jq --arg p "$profile" --arg s "$slot" --arg v "$value" '.[$p][$s] = $v' \
    > "$PREFERENCES_FILE.tmp" \
    && mv "$PREFERENCES_FILE.tmp" "$PREFERENCES_FILE"
}

clear_preferences() {
  local profile="$1"
  [[ -f "$PREFERENCES_FILE" ]] || return 0
  jq --arg p "$profile" 'del(.[$p])' "$PREFERENCES_FILE" \
    > "$PREFERENCES_FILE.tmp" \
    && mv "$PREFERENCES_FILE.tmp" "$PREFERENCES_FILE"
}

prompt_model() {
  local slot="$1" profile_json="$2"
  local count
  count=$(echo "$profile_json" | jq '.available_models | length')
  echo "" >&2
  echo "$slot:" >&2
  local i=1
  while IFS= read -r model; do
    echo "  $i) $model" >&2
    i=$((i + 1))
  done < <(echo "$profile_json" | jq -r '.available_models[]')
  local choice
  while true; do
    read -rp "Select [1-$count]: " choice
    if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= count )); then
      echo "$profile_json" | jq -r --argjson idx "$((choice - 1))" '.available_models[$idx]'
      return
    fi
    echo "  Invalid selection. Try again." >&2
  done
}

merge_into_settings() {
  local patch="$1"
  local current='{}'
  if [[ -f "$SETTINGS_FILE" ]]; then
    local raw
    raw=$(cat "$SETTINGS_FILE")
    # treat empty or whitespace-only file as {}
    [[ -n "$(echo "$raw" | tr -d '[:space:]')" ]] && current="$raw"
  fi
  local dir
  dir=$(dirname "$SETTINGS_FILE")
  mkdir -p "$dir"
  echo "$current" \
    | jq --argjson patch "$patch" '. * $patch' \
    > "$SETTINGS_FILE.tmp"
  # jq * does deep merge for objects but replaces arrays — current profiles have no array keys
  mv "$SETTINGS_FILE.tmp" "$SETTINGS_FILE"
}

print_summary() {
  local profile_name="$1" has_slots="$2" used_saved="$3"
  echo ""
  if [[ "$has_slots" == "true" ]]; then
    if [[ "$used_saved" == "true" ]]; then
      echo "✓ $profile_name active (saved preferences)"
    else
      echo "Preferences saved."
      echo "✓ $profile_name active"
    fi
    local sonnet opus default_model
    sonnet=$(get_preference "$profile_name" "ANTHROPIC_DEFAULT_SONNET_MODEL")
    opus=$(get_preference "$profile_name" "ANTHROPIC_DEFAULT_OPUS_MODEL")
    default_model=$(get_preference "$profile_name" "ANTHROPIC_MODEL")
    [[ -n "$sonnet" ]] && echo "  sonnet  → $sonnet"
    [[ -n "$opus" ]] && echo "  opus    → $opus"
    [[ -n "$default_model" ]] && echo "  default → $default_model"
  else
    echo "✓ $profile_name active"
  fi
}

# ── main ─────────────────────────────────────────────────────────────────────

main() {
  local profile_name="" reset=false

  for arg in "$@"; do
    case "$arg" in
      --reset) reset=true ;;
      -*) die "Unknown flag: $arg" ;;
      *) [[ -z "$profile_name" ]] && profile_name="$arg" || die "Unexpected argument: $arg" ;;
    esac
  done

  [[ -n "$profile_name" ]] || die "Usage: $0 <profile-name> [--reset]"

  require_jq

  local profile
  profile=$(load_profile "$profile_name")

  local has_slots
  has_slots=$(echo "$profile" | jq 'has("model_slots")')

  $reset && [[ "$has_slots" == "true" ]] && clear_preferences "$profile_name"

  local resolved="$profile"
  local used_saved=true

  if [[ "$has_slots" == "true" ]]; then
    local announced=false
    local slots
    mapfile -t slots < <(echo "$profile" | jq -r '.model_slots[]')
    for slot in "${slots[@]}"; do
      local saved
      saved=$(get_preference "$profile_name" "$slot")
      if [[ -n "$saved" ]]; then
        resolved=$(echo "$resolved" | jq --arg s "$slot" --arg v "$saved" '.env[$s] = $v')
      else
        if ! $announced; then
          echo "Switching to $profile_name..." >&2
          echo "No saved preferences found. Select models:" >&2
          announced=true
          used_saved=false
        fi
        local chosen
        chosen=$(prompt_model "$slot" "$profile")
        save_preference "$profile_name" "$slot" "$chosen"
        resolved=$(echo "$resolved" | jq --arg s "$slot" --arg v "$chosen" '.env[$s] = $v')
      fi
    done
  fi

  local patch
  patch=$(echo "$resolved" | jq 'del(.model_slots, .available_models)')

  merge_into_settings "$patch"
  print_summary "$profile_name" "$has_slots" "$used_saved"
}

main "$@"
