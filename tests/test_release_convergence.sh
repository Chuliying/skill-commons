#!/usr/bin/env bash
set -u
REPO="$(cd "$(dirname "$0")/.." && pwd)"
. "$REPO/tests/bootstrap/lib/assert.sh"

for removed in tdd grill-me grill-with-docs requesting-code-review rollback ponytail finishing-a-development-branch; do
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
sync_text="$(cat "$REPO/sync-work/SKILL.md")"
for mode in "Scoped Save" "Integrate" "Finish" "Recovery"; do
  assert_contains "$sync_text" "## Mode: $mode" "sync-work owns the $mode mode"
done
for safety_contract in \
  "unrelated dirty work" \
  "fresh verification" \
  "separate security evidence" \
  "approval before fetch" \
  "approval before merge or rebase" \
  "no remote" \
  "divergence" \
  "conflict" \
  "staged, uncommitted, unpushed, and published" \
  "reset --hard" \
  "force push" \
  "whole-tree checkout"; do
  assert_contains "$sync_text" "$safety_contract" "sync-work preserves $safety_contract"
done
for closeout in "Local merge" "Push and create PR" "Keep branch" "Discard work"; do
  assert_contains "$sync_text" "$closeout" "sync-work presents closeout outcome: $closeout"
done
for delivery_contract in \
  "work_status" \
  "delivery_status" \
  "Gate Package" \
  "approval_ref" \
  "pr_url" \
  "merge_sha" \
  "post-merge verification" \
  "discard double-confirmation"; do
  assert_contains "$sync_text" "$delivery_contract" "sync-work preserves delivery contract $delivery_contract"
done
sources_text="$(cat "$REPO/SOURCES.md")"
active_sources_text="$(sed '/^## Optional runtime adapters/,$d' "$REPO/SOURCES.md")"
assert_not_contains "$active_sources_text" "finishing-a-development-branch" "retired finish owner is absent from the active provenance table"
assert_contains "$sources_text" "## Retired source provenance" "retired finish provenance remains explicit"
assert_contains "$sources_text" "finishing-a-development-branch" "retired finish license and patch history remain recorded"
assert_contains "$(cat "$REPO/SOURCES.md")" 'T05 closeout handoff 改為 `sync-work` Finish' "adapted subagent handoff patch is recorded in provenance"

core_count="$(sed 's/#.*//' "$REPO/profiles/core" | tr -d ' \t' | grep -vcE '^(@.*)?$')"
if [ "$core_count" -eq 7 ]; then
  TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: core profile is the released v0.9.0 seven-owner set"
else
  fail "core profile is the released v0.9.0 seven-owner set"
fi
assert_file "$REPO/profiles/optional" "optional utility profile exists"
readme_text="$(cat "$REPO/README.md")"
readme_en_text="$(cat "$REPO/README.en.md")"
index_text="$(cat "$REPO/INDEX.md")"
bridge_text="$(cat "$REPO/docs/skill-commons-submodule-bridge.md")"
spec_state_text="$(cat "$REPO/docs/spec-state-protocol.md")"
evaluation_text="$(cat "$REPO/docs/evaluation.md")"
bootstrap_text="$(cat "$REPO/bootstrap/README.md")"
security_text="$(cat "$REPO/security/SKILL.md")"
changelog_text="$(cat "$REPO/CHANGELOG.md")"
unreleased_text="$(awk '/^## \[Unreleased\]/{p=1;next} p && /^## \[/{exit} p' "$REPO/CHANGELOG.md")"
release_090_text="$(awk '/^## \[0\.9\.0\]/{p=1;next} p && /^## \[/{exit} p' "$REPO/CHANGELOG.md")"
release_080_text="$(awk '/^## \[0\.8\.0\]/{p=1;next} p && /^## \[/{exit} p' "$REPO/CHANGELOG.md")"
gitattributes_text="$(cat "$REPO/.gitattributes")"
export_script_text="$(cat "$REPO/scripts/export-public.sh")"

if [ -d "$REPO/docs/work" ]; then
  active_work_items="$(bash "$REPO/scripts/work-items.sh" --work-root "$REPO/docs/work" list --status active)"
  shipped_work_items="$(bash "$REPO/scripts/work-items.sh" --work-root "$REPO/docs/work" list --status shipped)"
  stale_work_items="$(bash "$REPO/scripts/work-items.sh" --work-root "$REPO/docs/work" stale --days 1 --now 2026-07-11T14:00:00+08:00)"
  assert_not_contains "$active_work_items" "public-release" "public release leaves no active closeout residue"
  assert_contains "$shipped_work_items" "public-release" "public release records its shipped legacy closeout"
  for reconciled in skill-workflow-review work-item-docs; do
    assert_not_contains "$active_work_items" "$reconciled" "$reconciled is closed before release"
    assert_not_contains "$stale_work_items" "$reconciled" "$reconciled is absent from stale active work"
  done
fi

assert_contains "$readme_text" "delivery_mode: personal" "README shows an explicit delivery mode before onboarding"
assert_contains "$readme_text" "capability_packs:" "README documents composable capability packs"
assert_contains "$readme_text" "checkout v0.9.0" "README pins the v0.9.0 release"
assert_contains "$readme_en_text" "checkout v0.9.0" "English summary pins the v0.9.0 release"
assert_contains "$bridge_text" "checkout v0.9.0" "submodule bridge pins v0.9.0"
for entrypoint_text in "$readme_text" "$readme_en_text"; do
  assert_contains "$entrypoint_text" ".agent/skills/_shared/scripts/project-status.sh" "README documents the v0.9.0 project-status entry"
  assert_contains "$entrypoint_text" "--json" "README documents project-status machine output"
done
assert_contains "$changelog_text" "## [Unreleased]" "changelog keeps an Unreleased section after the release cut"
assert_contains "$changelog_text" "## [0.9.0] - 2026-07-15" "changelog records the v0.9.0 release date"
assert_contains "$changelog_text" "## [0.8.0] - 2026-07-14" "changelog records the v0.8.0 release date"
assert_contains "$changelog_text" "## [0.7.1] - 2026-07-11" "changelog records the v0.7.1 release date"
assert_contains "$changelog_text" "## [0.7.0] - 2026-07-11" "changelog records the v0.7.0 release date"
if [ -z "$(printf '%s' "$unreleased_text" | tr -d '[:space:]')" ]; then
  TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: Unreleased is reset after the v0.9.0 cut"
else
  fail "Unreleased is reset after the v0.9.0 cut"
fi
assert_contains "$release_090_text" "### Added" "v0.9.0 records its public feature addition"
assert_contains "$release_090_text" "project-status" "v0.9.0 records the project-status entry"
assert_contains "$release_090_text" "### Changed" "v0.9.0 records its claim-boundary change"
assert_contains "$release_090_text" "unverified historical narrative" "v0.9.0 records the benchmark evidence downgrade"
assert_contains "$release_090_text" "### Fixed" "v0.9.0 records release-hardening fixes"
assert_contains "$release_090_text" "environment fallback" "v0.9.0 records secret fallback detection"
assert_contains "$release_090_text" "managed stamp" "v0.9.0 records unstamped bootstrap detection"
for deferred_name in config-master page-composer prod-prototype-builder prototype-reviser prod-like-prototype; do
  assert_not_contains "$release_090_text" "$deferred_name" "v0.9.0 excludes deferred prod-like surface: $deferred_name"
done
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
assert_contains "$release_080_text" "### Removed" "v0.8.0 changelog has a removed section"
assert_contains "$release_080_text" "finishing-a-development-branch" "v0.8.0 changelog records the retired Git owner"
for optional_move in brainstorming grilling to-prd caveman-review shared-skill-onboarder; do
  assert_contains "$release_080_text" "\`$optional_move\`" "v0.8.0 changelog records core-to-optional move: $optional_move"
done
assert_contains "$release_080_text" "canonical-v2-only" "v0.8.0 changelog records the plan-format break"
assert_contains "$gitattributes_text" "/website/** export-ignore" "archive attributes exclude the nested website"
assert_contains "$gitattributes_text" "**/.env export-ignore" "archive attributes exclude .env files"
assert_contains "$gitattributes_text" "**/.env.* export-ignore" "archive attributes exclude environment variants"
assert_contains "$gitattributes_text" "**/.env.example -export-ignore" "archive attributes retain synthetic env examples"
assert_contains "$export_script_text" '"website"' "public export forbidden list rejects the website"
assert_contains "$export_script_text" "public export contains environment file" "public export rejects environment files after extraction"

for stale_version in "v0.5.0" "v0.6.0" "v0.8.0"; do
  assert_not_contains "$readme_text" "$stale_version" "README has no stale $stale_version pin"
  assert_not_contains "$readme_en_text" "$stale_version" "English summary has no stale $stale_version pin"
  assert_not_contains "$bridge_text" "$stale_version" "submodule bridge has no stale $stale_version pin"
done

for heading in \
  "## 核心價值" \
  "## 什麼時候值得用" \
  "## Quick Start" \
  "## 執行模型" \
  "## 信任與授權邊界" \
  "## 已驗證與尚未驗證" \
  "## 文件入口" \
  "## Maintainer verification"; do
  assert_contains "$readme_text" "$heading" "README keeps minimum entry section: $heading"
done

for core_narrative in \
  "可驗證、可接續" \
  "Spec 是施工圖" \
  "## 已驗證與尚未驗證" \
  "Spec drift"; do
  assert_contains "$readme_text" "$core_narrative" "README explains the durable engineering-state product core: $core_narrative"
done
for protocol_contract in "spec entropy" "One durable work item" "References instead of copied truth" "Cross-tool portability"; do
  assert_contains "$spec_state_text" "$protocol_contract" "spec-state document owns protocol detail: $protocol_contract"
done
for evidence_contract in "Frozen A/B/C benchmark" "Luna-high scoring repair" "Product-value test still needed"; do
  assert_contains "$evaluation_text" "$evidence_contract" "evaluation document owns evidence detail: $evidence_contract"
done
assert_not_contains "$evaluation_text" "](work/" "public evaluation has no links into export-ignored work items"
assert_contains "$evaluation_text" 'recorded `fail` against the pre-correction text' "evaluation preserves the review requirement failure precisely"

for overclaim in \
  "最痛的三件事" \
  "min(重做成本, 操作者的錯誤定位能力)" \
  "留空會 fan-out"; do
  assert_not_contains "$readme_text" "$overclaim" "README removes overclaim: $overclaim"
done
assert_not_contains "$readme_text" "不是" "README avoids the owner-rejected X-not-Y sentence pattern"
assert_not_contains "$readme_text" "並非" "README avoids the owner-rejected contrast synonym"
assert_not_contains "$readme_text" "而是" "README avoids the owner-rejected contrast conjunction"
assert_not_contains "$readme_en_text" "three worst" "English summary removes superlative positioning"
assert_not_contains "$readme_en_text" "Right-sized" "English summary removes formulaic positioning"
assert_contains "$readme_text" "最新工作狀態" "README uses a junior-readable shared-state term"
assert_contains "$readme_en_text" "latest work state" "English README uses a junior-readable shared-state term"
assert_not_contains "$readme_text" "current truth" "README removes unexplained internal state jargon"
assert_not_contains "$readme_en_text" "current truth" "English README removes unexplained internal state jargon"
assert_not_contains "$readme_text" "owner" "README calls installed capabilities skills instead of owners"
assert_not_contains "$readme_en_text" "owner" "English README calls installed capabilities skills instead of owners"
assert_contains "$readme_text" 'delivery_mode` 是安裝時選擇的技能組合' "README distinguishes install selection from task execution"
assert_contains "$readme_text" 'execution_mode` 是 Router 依單一任務決定的執行方式' "README explains task execution without setup jargon"
assert_contains "$readme_en_text" '`delivery_mode` selects the installed skill set' "English README distinguishes install selection from task execution"
assert_contains "$readme_en_text" '`execution_mode` is the Router choice for one task' "English README explains task execution without setup jargon"
assert_contains "$readme_text" "## 安裝完成後" "README tells a new user what to do after doctor"
assert_contains "$readme_en_text" "## After installation" "English README tells a new user what to do after doctor"
assert_contains "$readme_text" "匯出 CSV" "README gives one concrete natural-language task"
assert_contains "$readme_en_text" "export CSV" "English README gives one concrete natural-language task"
assert_not_contains "$readme_text" "A/B/C 路徑線索" "README keeps packet-leak lab detail in evaluation docs"
assert_not_contains "$readme_en_text" "A/B/C path clues" "English README keeps packet-leak lab detail in evaluation docs"
assert_not_contains "$readme_text" "零模型內容 gate" "README keeps packet-gate mechanics in evaluation docs"
assert_not_contains "$readme_en_text" "zero-model content gate" "English README keeps packet-gate mechanics in evaluation docs"
for heading in \
  "## Why it exists" \
  "## Quick Start" \
  "## Execution and trust model" \
  "## Evidence boundary" \
  "## Documentation" \
  "## Maintainer verification"; do
  assert_contains "$readme_en_text" "$heading" "English summary keeps minimum entry section: $heading"
done

assert_contains "$readme_text" "manage.sh doctor" "README keeps the first health-check command"
for command in doctor update uninstall; do
  assert_contains "$bootstrap_text" "manage.sh $command" "bootstrap manual owns $command"
  assert_contains "$bridge_text" "manage.sh $command" "submodule bridge documents bootstrap $command"
done
assert_contains "$bridge_text" "intentionally exits zero" "bridge labels check.sh as advisory"
assert_contains "$bridge_text" "preserves foreign content" "bridge states uninstall preservation boundary"
assert_contains "$bootstrap_text" 'profile:' "bootstrap manual identifies the legacy profile field"
assert_contains "$bootstrap_text" 'delivery_mode' "bootstrap manual identifies the explicit replacement field"
assert_contains "$bridge_text" '- profile:' "upgrade guide identifies the legacy blank profile field"
assert_contains "$bridge_text" 'delivery_mode' "upgrade guide identifies the explicit replacement field"
assert_contains "$security_text" "CLEAR/FINDINGS/SKIP" "security owner keeps the scoped secret-preflight vocabulary"
for entrypoint in "$readme_text" "$readme_en_text"; do
  assert_contains "$entrypoint" "bootstrap/README.md" "README links the bootstrap owner"
  assert_contains "$entrypoint" "docs/profile-platform-support.md" "README links the platform owner"
done

if python3 - "$REPO/docs/skill-commons-submodule-bridge.md" <<'PY'
from pathlib import Path
import sys

for name in sys.argv[1:]:
    text = Path(name).read_text(errors="replace")
    start = text.find("When upgrading a v0.6 installation")
    section = text[start:] if start >= 0 else ""
    positions = [
        section.find("fetch --tags"),
        section.find("checkout v0.9.0"),
        section.find("bootstrap/manage.sh update"),
    ]
    if not section or any(position < 0 for position in positions) or positions != sorted(positions):
        raise SystemExit(f"{name}: upgrade commands must fetch, select, then update")
PY
then
  TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: upgrade owner requires explicit revision selection"
else
  fail "upgrade owner requires explicit revision selection"
fi

readme_lines="$(wc -l < "$REPO/README.md" | tr -d ' ')"
readme_en_lines="$(wc -l < "$REPO/README.en.md" | tr -d ' ')"
if [ "$readme_lines" -le 180 ] && [ "$readme_en_lines" -le 150 ]; then
  TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: README entry surfaces stay within line budgets"
else
  fail "README entry surfaces stay within line budgets"
fi

for external_skill in skill-creator brainstorming subagent-driven-development humanizer; do
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
assert_contains "$sync_text" "awaiting_approval" "release approval is a durable state transition"
assert_contains "$sync_text" "actual event" "release closeout reports actual delivery evidence"
assert_not_contains "$sync_text" '標記 `shipped`' "release closeout does not conflate completed work with delivery"
assert_contains "$sync_text" 'release stage: `done`' "keep-branch uses a checker-legal completed release stage"

if python3 - "$REPO" <<'PY'
from pathlib import Path
import sys

repo = Path(sys.argv[1])
needle = "finishing-a-development-branch"
allowed_exact = {
    Path("CHANGELOG.md"),
    Path("SOURCES.md"),
    Path(".claude/skills/SOURCES.md"),
    Path(".codex/skills/SOURCES.md"),
    Path(".agents/skills/SOURCES.md"),
    Path("bootstrap/generate.sh"),
    Path("tests/bootstrap/test_generate_safety.sh"),
    Path("tests/test_profiles.sh"),
    Path("tests/test_release_convergence.sh"),
    Path("tests/test_skill_surface.sh"),
    Path("tests/test_skills_reorg.sh"),
}
allowed_prefixes = (
    Path(".claude/worktrees"),
    Path("_archive"),
    Path("journey-evals/runs"),
    Path("docs/skills-reorg"),
    Path("docs/superpowers"),
    Path("docs/work/skill-bundle-convergence"),
    Path("docs/work/skill-bundle-effect-benchmark"),
    Path("docs/work/repo-explainer-site"),
    Path("docs/work/public-release"),
    Path("docs/work/skill-workflow-review"),
    Path("docs/work/v0-7-0-release"),
    Path("website"),
)
residue = []
for path in repo.rglob("*"):
    if not path.is_file() or path.is_symlink():
        continue
    rel = path.relative_to(repo)
    if rel.parts and rel.parts[0] == ".git":
        continue
    if rel in allowed_exact or any(rel == prefix or prefix in rel.parents for prefix in allowed_prefixes):
        continue
    try:
        text = path.read_text(encoding="utf-8")
    except (UnicodeDecodeError, OSError):
        continue
    if needle in text:
        residue.append(str(rel))
if residue:
    raise SystemExit("active old-owner residue: " + ", ".join(sorted(residue)))
PY
then
  TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: active surface has no retired Git-owner residue"
else
  fail "active surface has no retired Git-owner residue"
fi

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
