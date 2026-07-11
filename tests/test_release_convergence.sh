#!/usr/bin/env bash
set -u
REPO="$(cd "$(dirname "$0")/.." && pwd)"
. "$REPO/tests/bootstrap/lib/assert.sh"

for removed in tdd grill-me grill-with-docs requesting-code-review rollback ponytail; do
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
readme_text="$(cat "$REPO/README.md")"
readme_en_text="$(cat "$REPO/README.en.md")"
index_text="$(cat "$REPO/INDEX.md")"
bridge_text="$(cat "$REPO/docs/skill-commons-submodule-bridge.md")"
changelog_text="$(cat "$REPO/CHANGELOG.md")"

if [ -d "$REPO/docs/work" ]; then
  active_work_items="$(bash "$REPO/scripts/work-items.sh" --work-root "$REPO/docs/work" list --status active)"
  stale_work_items="$(bash "$REPO/scripts/work-items.sh" --work-root "$REPO/docs/work" stale --days 1 --now 2026-07-11T14:00:00+08:00)"
  assert_contains "$active_work_items" "public-release" "public release remains the intentional active work item"
  for reconciled in skill-workflow-review work-item-docs; do
    assert_not_contains "$active_work_items" "$reconciled" "$reconciled is closed before release"
    assert_not_contains "$stale_work_items" "$reconciled" "$reconciled is absent from stale active work"
  done
fi

assert_contains "$readme_text" "delivery_mode: personal" "README shows an explicit delivery mode before onboarding"
assert_contains "$readme_text" "capability_packs:" "README documents composable capability packs"
assert_contains "$readme_text" "v0.7.1" "README pins the v0.7.1 contract"
assert_contains "$readme_en_text" "v0.7.1" "English summary pins the v0.7.1 contract"
assert_contains "$bridge_text" "v0.7.1" "submodule bridge pins v0.7.1"
assert_contains "$changelog_text" "## [Unreleased]" "changelog keeps an Unreleased section after the release cut"
assert_contains "$changelog_text" "## [0.7.1] - 2026-07-11" "changelog records the v0.7.1 release date"
assert_contains "$changelog_text" "## [0.7.0] - 2026-07-11" "changelog records the v0.7.0 release date"
assert_not_contains "$changelog_text" "Release candidate: v0.7.0" "changelog removes the release-candidate marker"
public_release_text="$(printf '%s\n%s\n%s\n%s\n' \
  "$readme_text" "$readme_en_text" "$bridge_text" "$changelog_text" | \
  tr '[:upper:]' '[:lower:]')"
for stale_rc in \
  "release candidate" \
  "release-candidate" \
  "exact commit" \
  "tag remains unpublished" \
  "do not infer an unpublished tag" \
  "正式 tag 發布後" \
  "不要把 \`v0.7.0\` 當成"; do
  assert_not_contains "$public_release_text" "$stale_rc" "public release docs remove stale RC instruction: $stale_rc"
done
for retired_cli in init_plan.py sync_tasks.py append_note.py refresh_snapshot.py; do
  assert_contains "$changelog_text" "$retired_cli" "changelog names retired Plan Sync CLI $retired_cli"
done
assert_contains "$changelog_text" "planctl.py" "changelog names the canonical Plan Sync CLI replacement"

for stale_version in "v0.5.0" "v0.6.0"; do
  assert_not_contains "$readme_text" "$stale_version" "README has no stale $stale_version pin"
  assert_not_contains "$readme_en_text" "$stale_version" "English summary has no stale $stale_version pin"
  assert_not_contains "$bridge_text" "$stale_version" "submodule bridge has no stale $stale_version pin"
done

for heading in \
  "## Execution Mode 與工作流程" \
  "## 核心能力與邊界" \
  "### Plan Sync" \
  "### Repo Map" \
  "## 平台與 fan-out" \
  "## 驗證、安全與授權"; do
  assert_contains "$readme_text" "$heading" "README keeps public contract section: $heading"
done

for overclaim in \
  "最痛的三件事" \
  "min(重做成本, 操作者的錯誤定位能力)" \
  "留空會 fan-out"; do
  assert_not_contains "$readme_text" "$overclaim" "README removes overclaim: $overclaim"
done
assert_not_contains "$readme_en_text" "three worst" "English summary removes superlative positioning"
assert_not_contains "$readme_en_text" "Right-sized" "English summary removes formulaic positioning"
for heading in \
  "## Scope and boundaries" \
  "## Delivery selection and platforms" \
  "## Plan Sync and host Goal Mode" \
  "## Repo Map and optional visualization" \
  "## Upgrade and local management"; do
  assert_contains "$readme_en_text" "$heading" "English summary keeps public contract section: $heading"
done

for command in doctor update uninstall; do
  assert_contains "$readme_text" "manage.sh $command" "README documents bootstrap $command"
  assert_contains "$bridge_text" "manage.sh $command" "submodule bridge documents bootstrap $command"
done
assert_contains "$bridge_text" "intentionally exits zero" "bridge labels check.sh as advisory"
assert_contains "$bridge_text" "preserves foreign content" "bridge states uninstall preservation boundary"
for text in "$readme_text" "$readme_en_text" "$bridge_text"; do
  assert_contains "$text" '- profile:' "upgrade docs identify the legacy blank profile field"
  assert_contains "$text" 'delivery_mode' "upgrade docs identify the explicit replacement field"
done
assert_contains "$readme_text" "CLEAR/FINDINGS/SKIP" "README uses the scoped secret-preflight vocabulary"

if python3 - "$REPO/README.md" "$REPO/README.en.md" <<'PY'
from pathlib import Path
import sys

for name in sys.argv[1:]:
    text = Path(name).read_text(errors="replace")
    heading = "## 升級、檢查與移除" if name.endswith("README.md") else "## Upgrade and local management"
    start = text.find(heading)
    section = text[start:] if start >= 0 else ""
    positions = [
        section.find("fetch --tags"),
        section.find("checkout v0.7.1"),
        section.find("bootstrap/manage.sh update"),
    ]
    if not section or any(position < 0 for position in positions) or positions != sorted(positions):
        raise SystemExit(f"{name}: upgrade commands must fetch, select, then update")
PY
then
  TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: README upgrade commands require explicit revision selection"
else
  fail "README upgrade commands require explicit revision selection"
fi

for external_skill in skill-creator brainstorming finishing-a-development-branch subagent-driven-development humanizer; do
  assert_contains "$index_text" "\`$external_skill\` (ext" "INDEX marks sourced skill $external_skill"
done

assert_contains "$index_text" "delivery_mode" "INDEX derives bundles from explicit delivery mode"
assert_contains "$index_text" "capability_packs" "INDEX derives utilities from capability packs"
assert_not_contains "$index_text" "ponytail" "INDEX has no retired ponytail entry"
assert_not_contains "$readme_text" "personal = 16" "README does not turn the pre-W6 audit into a current count"
assert_not_contains "$index_text" 'personal` = 16' "INDEX does not hand-maintain bundle counts"

if python3 - "$REPO/README.md" <<'PY'
from pathlib import Path
import sys

text = Path(sys.argv[1]).read_text(errors="replace")
start = text.find("## Quick Start")
end = text.find("\n## Execution Mode", start + 1) if start >= 0 else -1
section = text[start:end if end >= 0 else len(text)] if start >= 0 else ""
selection = section.find("delivery_mode: personal")
onboard = section.find("bootstrap/onboard.sh")
if not section or selection < 0 or onboard < 0 or selection > onboard:
    raise SystemExit("Quick Start must make delivery selection explicit before onboarding")
PY
then
  TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: Quick Start selects a delivery mode before onboarding"
else
  fail "Quick Start selects a delivery mode before onboarding"
fi
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
assert_contains "$(cat "$REPO/ARTIFACTS.md")" "work_status: active | completed | abandoned" "artifact contract separates work completion"
assert_contains "$(cat "$REPO/ARTIFACTS.md")" "delivery_status: not_requested | awaiting_approval | approved | pr_created | merged | deployed" "artifact contract separates evidence-backed delivery"
assert_contains "$(cat "$REPO/ARTIFACTS.md")" "merge_sha" "artifact delivery requires merge evidence"
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
assert_not_contains "$(cat "$REPO/spec/SKILL.md")" "Personal/refactor optional spec" "personal feature does not invent an optional Spec"
assert_contains "$(cat "$REPO/qa/SKILL.md")" 'qa (validate)** → `verification-before-completion`' "QA pipeline hands off to final verification"
assert_contains "$(cat "$REPO/finishing-a-development-branch/SKILL.md")" "awaiting-approval" "release approval is a durable state transition"
assert_contains "$(cat "$REPO/finishing-a-development-branch/SKILL.md")" "PR URL / merge SHA" "release closeout reports actual delivery evidence"
assert_not_contains "$(cat "$REPO/finishing-a-development-branch/SKILL.md")" '標記 `shipped`' "release closeout does not conflate completed work with delivery"
finish_text="$(cat "$REPO/finishing-a-development-branch/SKILL.md")"
assert_not_contains "$finish_text" '選項 3 將 release stage 設為 `blocked`' "keep-branch does not author a blocked stage on completed work"
assert_contains "$finish_text" '選項 3 將 release stage 設為 `done`' "keep-branch uses a checker-legal completed release stage"

handoff_path="$REPO/docs/work/v0-7-0-release/reviews/fable-final-release-candidate-handoff.md"
if [ -f "$handoff_path" ]; then
  handoff_text="$(cat "$handoff_path")"
  for finding in "NEW-1 (R3-1)" "NEW-2 (R3-2)" "R3-3" "R3-4"; do
    assert_contains "$handoff_text" "$finding" "final handoff records $finding disposition"
  done
  assert_contains "$handoff_text" "336b9d0b6d1d663e37726325de187408e320de34" "handoff identifies the actual round-2 reviewed candidate"
  assert_contains "$handoff_text" "25-assertion RED snapshot" "handoff scopes the original RED count"
  assert_contains "$handoff_text" "30-assertion round-3 replay" "handoff records the independent final-gate replay"
  assert_not_contains "$handoff_text" "first reproduced 23 old-contract failures" "handoff does not present incomparable RED counts as one baseline"
else
  TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: private Fable handoff is absent from the public export"
fi
# metrics.md is private-only; on a public export it must be absent instead.
if [ -f "$REPO/docs/skills-reorg/metrics.md" ]; then
  assert_not_contains "$(cat "$REPO/docs/skills-reorg/metrics.md")" "test_dummy_pipeline.sh" "metrics no longer call artifact smoke an E2E journey"
elif [ -d "$REPO/_archive" ]; then
  fail "metrics no longer call artifact smoke an E2E journey (private repo missing docs/skills-reorg/metrics.md)"
else
  TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: metrics doc is absent on the public surface"
fi

finish
