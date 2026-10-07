#!/usr/bin/env bash
set -u
REPO="$(cd "$(dirname "$0")/.." && pwd)"
. "$REPO/tests/bootstrap/lib/assert.sh"

skill_text="$(cat "$REPO/brainstorming/SKILL.md")"
router_text="$(cat "$REPO/skill-router/SKILL.md")"
subagent_text="$(cat "$REPO/subagent-driven-development/SKILL.md")"
readme_text="$(cat "$REPO/README.md")"
discovery_text="$(cat "$REPO/docs/discovery-and-planning.md")"
spec_text="$(cat "$REPO/spec/SKILL.md")"
qa_plan_text="$(cat "$REPO/qa/references/qa-plan.md")"
research_path="$REPO/brainstorming/references/research.md"
wayfinding_path="$REPO/brainstorming/references/wayfinding.md"
research_text=""
wayfinding_text=""

if [ -f "$research_path" ]; then
  research_text="$(cat "$research_path")"
else
  fail "brainstorming provides conditional Research reference"
fi
if [ -f "$wayfinding_path" ]; then
  wayfinding_text="$(cat "$wayfinding_path")"
else
  fail "brainstorming provides conditional Wayfinding reference"
fi

for token in "material ambiguity" "Skip" "Quick" "Standard" "Deep" "最多 3 個問題" "最多 2 個選項" "一次最終確認"; do
  assert_contains "$skill_text" "$token" "brainstorming defines bounded contract: $token"
done
assert_contains "$skill_text" "repo evidence" "brainstorming inspects repository evidence before asking"
assert_contains "$skill_text" "跨 session" "brainstorming makes durable output conditional"
assert_contains "$skill_text" "使用者明確同意" "Deep mode requires explicit agreement"
assert_contains "$skill_text" "references/research.md" "qualified discovery can load Research conditionally"
assert_contains "$skill_text" "references/wayfinding.md" "consented Deep can load Wayfinding conditionally"
assert_contains "$skill_text" "事實問題" "direct factual questions keep the Skip path"
assert_not_contains "$skill_text" "所有需求都要經歷此流程" "brainstorming is not universal"
assert_not_contains "$skill_text" "未輸出 Checklist = 未完成 Skill" "brainstorming has no mandatory checklist"
assert_not_contains "$skill_text" "每個段落後問確認" "brainstorming has no repeated confirmation ceremony"
assert_contains "$skill_text" "progress/commentary" "brainstorming keeps skill transparency in progress updates"
assert_contains "$skill_text" "final answer" "brainstorming keeps internal skill narration out of the final answer"

skill_lines="$(wc -l < "$REPO/brainstorming/SKILL.md" | tr -d ' ')"
skill_bytes="$(wc -c < "$REPO/brainstorming/SKILL.md" | tr -d ' ')"
if [ "$skill_lines" -le 120 ]; then
  TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: brainstorming stays at or below 120 lines"
else
  fail "brainstorming stays at or below 120 lines (got $skill_lines)"
fi
if [ "$skill_bytes" -le 4608 ]; then
  TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: brainstorming stays at or below 4608 bytes"
else
  fail "brainstorming stays at or below 4608 bytes (got $skill_bytes)"
fi

for token in "qualified Standard or Deep" "primary sources" "source budget" "stopping condition" "citations" "uncertainty" "synchronous fallback" "conditional durable output"; do
  assert_contains "$research_text" "$token" "Research reference defines bounded evidence contract: $token"
done
for token in "Destination" "Fog" "Frontier" "Decisions" "Out of scope" "Consent Ref" "Remaining Budget" "proceed" "narrow" "stay Standard" "legacy" "24,576" "6,144" "docs/reference"; do
  assert_contains "$wayfinding_text" "$token" "Wayfinding reference defines bounded map contract: $token"
done

if [ -f "$research_path" ]; then
  research_lines="$(wc -l < "$research_path" | tr -d ' ')"
  research_bytes="$(wc -c < "$research_path" | tr -d ' ')"
  [ "$research_lines" -le 40 ] && [ "$research_bytes" -le 4096 ] \
    && { TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: Research reference stays within line and byte budgets"; } \
    || fail "Research reference stays within 40 lines and 4096 bytes"
fi
if [ -f "$wayfinding_path" ]; then
  wayfinding_lines="$(wc -l < "$wayfinding_path" | tr -d ' ')"
  wayfinding_bytes="$(wc -c < "$wayfinding_path" | tr -d ' ')"
  [ "$wayfinding_lines" -le 90 ] && [ "$wayfinding_bytes" -le 9216 ] \
    && { TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: Wayfinding reference stays within line and byte budgets"; } \
    || fail "Wayfinding reference stays within 90 lines and 9216 bytes"
fi

reference_bytes="$((research_bytes + wayfinding_bytes))"
if [ "$reference_bytes" -le 3072 ]; then
  TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: conditional discovery references stay within their combined context budget"
else
  fail "conditional discovery references stay within 3072 bytes (got $reference_bytes)"
fi

assert_contains "$router_text" "material ambiguity" "router uses the qualification boundary"
assert_contains "$router_text" "Skip / Quick / Standard / Deep" "router names the bounded modes"
assert_contains "$router_text" "Research" "router keeps qualified Research inside discovery"
assert_contains "$router_text" "Wayfinding" "router names consented Deep Wayfinding"
assert_contains "$router_text" "事實問題" "router keeps factual questions on direct evidence path"
assert_not_contains "$router_text" 'personal 預設 `brainstorming → to-prd`' "router does not force personal discovery"
assert_not_contains "$subagent_text" "先用 brainstorming + plan-sync" "subagent fallback does not force brainstorming"
assert_contains "$subagent_text" "Fog" "subagent execution rejects unresolved discovery Fog"

assert_contains "$spec_text" "### 技術方案研究 (Tech Research)" "Spec retains phase-owned technical research"
assert_contains "$qa_plan_text" "### 測試策略研究 (QA Research)" "QA retains phase-owned test-strategy research"
assert_not_contains "$spec_text" "brainstorming/references/research.md" "Spec research does not re-enter discovery"
assert_not_contains "$qa_plan_text" "brainstorming/references/research.md" "QA research does not re-enter discovery"

for token in "## Brainstorming：有歧義才用" "事實查證" "Bounded ambiguity" "同意進入 Deep" "需求已清楚" "Research" "Wayfinding" "Selected Seam" "垂直切片" "83.33%" "proven effectiveness"; do
  assert_contains "$discovery_text" "$token" "discovery reader explains boundary: $token"
done
for token in "Factual lookup" "Bounded ambiguity" "Consented Deep" "Known executable work" "Research" "Wayfinding" "Selected Seam" "vertical slice" "83.33%" "pre-T10 historical negative evidence"; do
  assert_contains "$discovery_text" "$token" "discovery reader keeps evidence boundary: $token"
done
assert_contains "$readme_text" "docs/discovery-and-planning.md" "README links the discovery reader"

if [ ! -e "$REPO/brainstorming/evals" ]; then
  TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: maintainer routing fixtures are not in the fan-out skill payload"
else
  fail "maintainer routing fixtures are not in the fan-out skill payload"
fi

if python3 - "$REPO/tests/fixtures/brainstorming-routing.tsv" <<'PY'
from collections import Counter
import csv
from pathlib import Path
import sys

path = Path(sys.argv[1])
lines = path.read_text().splitlines()
assert "does not prove" in lines[0]
rows = list(csv.DictReader(lines[1:], delimiter="\t"))
assert len(rows) == 25
assert [int(item["id"]) for item in rows] == list(range(1, 26))
routes = Counter(item["expected_route"] for item in rows)
assert routes == {"skip": 14, "quick": 3, "standard": 6, "deep": 2}
allowed_next = {"answer", "implement", "plan-sync", "research-subroutine", "wayfinding", "continue-current-flow"}
allowed_deep = {"n/a", "proceed", "narrow", "stay-standard", "resume", "legacy-no-upgrade"}
assert {item["expected_next"] for item in rows} <= allowed_next
assert {item["expected_deep_action"] for item in rows} <= allowed_deep
assert {item["expected_deep_action"] for item in rows if item["expected_route"] == "deep"} == {"proceed", "resume"}
assert {item["expected_deep_action"] for item in rows if item["expected_route"] == "standard"} >= {"narrow", "stay-standard"}
assert all(item["expected_route"] == "standard" and item["expected_next"] != "wayfinding" for item in rows if item["expected_deep_action"] in {"narrow", "stay-standard"})
assert all(item["expected_route"] == "deep" and item["expected_next"] in {"wayfinding", "continue-current-flow"} for item in rows if item["expected_deep_action"] in {"proceed", "resume"})
assert all(item["expected_route"] == "skip" and item["expected_next"] != "wayfinding" for item in rows if item["expected_deep_action"] == "legacy-no-upgrade")
assert sum(item["expected_route"] == "skip" and item["expected_next"] == "answer" for item in rows) >= 2
assert sum(item["expected_next"] == "continue-current-flow" for item in rows) == 5
for item in rows:
    assert item["prompt"].strip()
PY
then
  TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: 25-case routing and deep-action fixture is valid"
else
  fail "25-case routing and deep-action fixture is valid"
fi

finish
