#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/cc-switch.sh"

pass=0; fail=0

assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [[ "$actual" == "$expected" ]]; then
    echo "  PASS: $desc"; pass=$((pass + 1))
  else
    echo "  FAIL: $desc"
    echo "    expected: $expected"
    echo "    actual:   $actual"
    fail=$((fail + 1))
  fi
}

assert_contains() {
  local desc="$1" needle="$2" haystack="$3"
  if echo "$haystack" | grep -qF "$needle"; then
    echo "  PASS: $desc"; pass=$((pass + 1))
  else
    echo "  FAIL: $desc — '$needle' not found in output"
    fail=$((fail + 1))
  fi
}

assert_file_key() {
  local desc="$1" file="$2" jq_path="$3" expected="$4"
  local actual
  actual=$(jq -r "$jq_path" "$file" 2>/dev/null || echo "MISSING")
  assert_eq "$desc" "$expected" "$actual"
}

setup() {
  export TMP_DIR
  TMP_DIR=$(mktemp -d)
  export SETTINGS_FILE="$TMP_DIR/settings.json"
  export PREFERENCES_FILE="$TMP_DIR/preferences.json"
}

teardown() {
  rm -rf "$TMP_DIR"
}

# ── Test 1: profile1 merges env into empty settings.json ──────────────────────
echo ""
echo "Test 1: profile1 into empty settings.json"
setup
output=$(bash "$SCRIPT" profile1 2>&1)
assert_contains "exits with success message" "✓ profile1 active" "$output"
assert_file_key "sets ANTHROPIC_MODEL" "$SETTINGS_FILE" '.env.ANTHROPIC_MODEL' "cc/claude-sonnet-4-6"
assert_file_key "sets model key" "$SETTINGS_FILE" '.model' "sonnet"
teardown

# ── Test 2: profile1 preserves existing keys not in profile ───────────────────
echo ""
echo "Test 2: profile1 preserves existing settings.json keys"
setup
echo '{"theme":"dark-daltonized","hooks":{"SessionStart":[]}}' > "$SETTINGS_FILE"
bash "$SCRIPT" profile1 2>&1 > /dev/null
assert_file_key "preserves theme" "$SETTINGS_FILE" '.theme' "dark-daltonized"
assert_file_key "preserves hooks" "$SETTINGS_FILE" '.hooks.SessionStart | length' "0"
teardown

# ── Test 3: profile1 into missing settings.json ───────────────────────────────
echo ""
echo "Test 3: profile1 into missing settings.json"
setup
# SETTINGS_FILE does not exist
bash "$SCRIPT" profile1 2>&1 > /dev/null
assert_file_key "creates settings.json with env" "$SETTINGS_FILE" '.env.ANTHROPIC_MODEL' "cc/claude-sonnet-4-6"
teardown

# ── Test 4: profile2 prompts for model slots ──────────────────────────────────
echo ""
echo "Test 4: profile2 prompts and saves model preferences"
setup
output=$(printf "1\n2\n3\n" | bash "$SCRIPT" profile2 2>&1)
assert_contains "shows sonnet prompt" "ANTHROPIC_DEFAULT_SONNET_MODEL" "$output"
assert_contains "shows opus prompt" "ANTHROPIC_DEFAULT_OPUS_MODEL" "$output"
assert_contains "saves confirmation" "Preferences saved." "$output"
assert_file_key "saves sonnet pref" "$PREFERENCES_FILE" '.profile2.ANTHROPIC_DEFAULT_SONNET_MODEL' "alicode-intl/qwen3.5-plus"
assert_file_key "saves opus pref" "$PREFERENCES_FILE" '.profile2.ANTHROPIC_DEFAULT_OPUS_MODEL' "alicode-intl/kimi-k2.5"
assert_file_key "injects sonnet into settings" "$SETTINGS_FILE" '.env.ANTHROPIC_DEFAULT_SONNET_MODEL' "alicode-intl/qwen3.5-plus"
teardown

# ── Test 5: profile2 second run uses saved preferences (no prompt) ────────────
echo ""
echo "Test 5: profile2 second run is instant (saved preferences)"
setup
printf "1\n2\n3\n" | bash "$SCRIPT" profile2 2>&1 > /dev/null
output=$(bash "$SCRIPT" profile2 2>&1)
assert_contains "shows saved preferences message" "(saved preferences)" "$output"
# If prompt appeared, output would contain "Select [1-7]:"
if echo "$output" | grep -qF "Select [1-7]:"; then
  echo "  FAIL: second run should not prompt"; ((fail++))
else
  echo "  PASS: second run did not prompt"; ((pass++))
fi
teardown

# ── Test 6: --reset clears preferences and re-prompts ────────────────────────
echo ""
echo "Test 6: --reset clears preferences"
setup
printf "1\n2\n3\n" | bash "$SCRIPT" profile2 2>&1 > /dev/null
output=$(printf "3\n1\n2\n" | bash "$SCRIPT" profile2 --reset 2>&1)
assert_contains "shows prompt after reset" "ANTHROPIC_DEFAULT_SONNET_MODEL" "$output"
assert_file_key "saves new sonnet pref after reset" "$PREFERENCES_FILE" '.profile2.ANTHROPIC_DEFAULT_SONNET_MODEL' "alicode-intl/glm-5"
teardown

# ── Test 7: invalid profile name exits with error ─────────────────────────────
echo ""
echo "Test 7: invalid profile name"
setup
output=$(bash "$SCRIPT" doesnotexist 2>&1 || true)
assert_contains "shows error message" "not found" "$output"
teardown

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo "Results: $pass passed, $fail failed"
[[ $fail -eq 0 ]]
