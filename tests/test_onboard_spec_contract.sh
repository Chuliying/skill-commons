#!/usr/bin/env bash
# One rule for missing manifest keys. The onboarder promises that consuming skills derive
# a missing key from the repository or ask; spec used to stop outright when system_context
# was absent, which blocked a fresh personal install (competitor test S3). This checks the
# written contract only; the agent's behavior is checked by the positioning re-run (T06).
set -u
REPO="$(cd "$(dirname "$0")/.." && pwd)"
. "$REPO/tests/bootstrap/lib/assert.sh"

spec="$(cat "$REPO/spec/SKILL.md")"
onboarder="$(cat "$REPO/shared-skill-onboarder/SKILL.md")"
step0="$(awk '/^### Step 0/{on=1; next} on && /^### /{exit} on' "$REPO/spec/SKILL.md")"
gate_row="$(grep -E '^\| \*\*System Context\*\*' "$REPO/spec/SKILL.md")"

# The onboarder states the principle once and points to each skill's own rule.
assert_contains "$onboarder" "會依 repo 慣例推導或直接詢問使用者" "onboarder states derive-or-ask for missing keys"
assert_contains "$onboarder" "Manifest Contract" "onboarder points to each skill's own manifest rule"

# spec defines its rule in Step 0 and no longer stops on a missing key.
assert_not_contains "$spec" "\`system_context\` 缺失時停止" "spec does not stop when system_context is missing"
assert_contains "$spec" "### Step 0: 讀取 Project Manifest（本技能的 Manifest Contract）" "spec Step 0 is the skill's manifest contract"
assert_contains "$step0" "檢查 \`system_context\`" "spec Step 0 has a decision for system_context"
system_context_rule="$(printf '%s\n' "$step0" | awk '/檢查 `system_context`/{on=1} on' )"
assert_contains "$system_context_rule" "推導" "missing system_context is derived first"
assert_contains "$system_context_rule" "詢問使用者" "spec asks only when derivation is not enough"
assert_contains "$system_context_rule" "不依賴" "derivation does not depend on an optional skill"

# The Gate 2 row follows Step 0 instead of demanding the key.
assert_contains "$gate_row" "Step 0" "Gate 2 System Context row follows the Step 0 decision"
assert_not_contains "$gate_row" "必須讀取" "Gate 2 does not require system_context to exist up front"

finish
