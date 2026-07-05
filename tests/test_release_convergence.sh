#!/usr/bin/env bash
set -u
REPO="$(cd "$(dirname "$0")/.." && pwd)"
. "$REPO/tests/bootstrap/lib/assert.sh"

for removed in tdd grill-me grill-with-docs requesting-code-review rollback; do
  if [ -d "$REPO/$removed" ]; then
    fail "$removed is removed from the active skill surface"
  else
    TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: $removed is removed from the active skill surface"
  fi
done

implement_text="$(cat "$REPO/implement/SKILL.md")"
for token in "RED" "GREEN" "REFACTOR" "observed failing test"; do
  assert_contains "$implement_text" "$token" "implement owns $token discipline"
done
assert_not_contains "$implement_text" '`tdd`' "implement no longer delegates its core loop"

assert_contains "$(cat "$REPO/grilling/SKILL.md")" "adr.md" "grilling owns durable stress-test docs mode"
assert_contains "$(cat "$REPO/caveman-review/SKILL.md")" "fresh-context" "review style and dispatch share one skill"
assert_contains "$(cat "$REPO/finishing-a-development-branch/SKILL.md")" "Recovery Mode" "branch finish skill owns recovery mode"

core_count="$(sed 's/#.*//' "$REPO/profiles/core" | tr -d ' \t' | grep -vcE '^(@.*)?$')"
if [ "$core_count" -le 14 ]; then
  TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: core profile converges to at most 14 skills"
else
  fail "core profile converges to at most 14 skills"
fi
assert_file "$REPO/profiles/optional" "optional utility profile exists"
assert_contains "$(cat "$REPO/README.md")" "profile: personal optional" "README documents optional profile composition"
if grep -qx 'skill-creator' \
    "$REPO/profiles/core" \
    "$REPO/profiles/team-sprint" \
    "$REPO/profiles/personal" \
    "$REPO/profiles/optional"; then
  fail "skill-creator is absent from consuming profiles"
else
  TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: skill-creator is absent from consuming profiles"
fi

router_lines="$(wc -l < "$REPO/skill-router/SKILL.md" | tr -d ' ')"
if [ "$router_lines" -le 250 ]; then
  TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: router is at most 250 lines"
else
  fail "router is at most 250 lines"
fi
for flow in "探索" "建造" "修錯" "發布" "理解"; do
  assert_contains "$(cat "$REPO/skill-router/SKILL.md")" "## Flow: $flow" "router defines $flow flow"
done
decision_rows="$(awk '/^## 任務判斷表/{p=1;next} p && /^## /{exit} p && /^\|/{n++} END{print n+0}' "$REPO/skill-router/SKILL.md")"
if [ "$decision_rows" -le 8 ]; then
  TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: router decision table has at most six data rows"
else
  fail "router decision table has at most six data rows"
fi

assert_contains "$(cat "$REPO/ARTIFACTS.md")" "awaiting-approval" "artifact stages support approval waiting"
assert_contains "$(cat "$REPO/ARTIFACTS.md")" "approved" "artifact stages support approval completion"
assert_file "$REPO/GATE-PACKAGE.md" "Gate Package convention exists"
if [ -f "$REPO/GATE-PACKAGE.md" ]; then
  gate_package="$(cat "$REPO/GATE-PACKAGE.md")"
  for token in "Changes since previous Gate" "Evidence checklist" "Risks and open questions" "Decision options"; do
    assert_contains "$gate_package" "$token" "Gate Package contains $token"
  done
fi

assert_file "$REPO/qa/scripts/check-traceability.py" "QA traceability has a machine gate"
assert_file "$REPO/prototype/scripts/verify-freeze.py" "prototype freeze comparison has a machine gate"
prototype_text="$(cat "$REPO/prototype/SKILL.md")"
assert_contains "$prototype_text" "G1 / G4 / G6" "prototype documents exactly three human gates"
assert_contains "$prototype_text" "click walkthrough" "prototype G6 leaves human judgment to click walkthrough"
assert_not_contains "$prototype_text" "G5 Stage 1" "prototype folds G5 confirmation into G4"

assert_not_contains "$(cat "$REPO/spec/SKILL.md")" "Gate 0" "Spec preflight is folded into Gate 2"
assert_contains "$(cat "$REPO/README.md")" "PRD 核可、team 設計核可、發布核可" "README names exactly three workflow human gates"
assert_contains "$(cat "$REPO/prd-interview/SKILL.md")" "awaiting-approval" "PRD approval is a durable state transition"
assert_contains "$(cat "$REPO/spec/SKILL.md")" "awaiting-approval" "team design approval is a durable state transition"
assert_contains "$(cat "$REPO/finishing-a-development-branch/SKILL.md")" "awaiting-approval" "release approval is a durable state transition"
# metrics.md is private-only; on a public export it must be absent instead.
if [ -f "$REPO/docs/skills-reorg/metrics.md" ]; then
  assert_not_contains "$(cat "$REPO/docs/skills-reorg/metrics.md")" "test_dummy_pipeline.sh" "metrics no longer call artifact smoke an E2E journey"
elif [ -d "$REPO/_archive" ]; then
  fail "metrics no longer call artifact smoke an E2E journey (private repo missing docs/skills-reorg/metrics.md)"
else
  TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: metrics doc is absent on the public surface"
fi

finish
