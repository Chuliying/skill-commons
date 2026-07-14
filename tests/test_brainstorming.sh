#!/usr/bin/env bash
set -u
REPO="$(cd "$(dirname "$0")/.." && pwd)"
. "$REPO/tests/bootstrap/lib/assert.sh"

skill_text="$(cat "$REPO/brainstorming/SKILL.md")"
router_text="$(cat "$REPO/skill-router/SKILL.md")"
subagent_text="$(cat "$REPO/subagent-driven-development/SKILL.md")"
readme_text="$(cat "$REPO/README.md")"
discovery_text="$(cat "$REPO/docs/discovery-and-planning.md")"
sources_text="$(cat "$REPO/SOURCES.md")"
index_text="$(cat "$REPO/INDEX.md")"
changelog_text="$(cat "$REPO/CHANGELOG.md")"
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

router_lines="$(wc -l < "$REPO/skill-router/SKILL.md" | tr -d ' ')"
router_bytes="$(wc -c < "$REPO/skill-router/SKILL.md" | tr -d ' ')"
[ "$router_lines" -le 180 ] && [ "$router_bytes" -le 7600 ] \
  && { TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: router stays within hot-path line and byte budgets"; } \
  || fail "router stays within 180 lines and 7600 bytes"

plan_sync_bytes="$(wc -c < "$REPO/plan-sync/SKILL.md" | tr -d ' ')"
context_bytes="$((router_bytes + skill_bytes + reference_bytes + plan_sync_bytes))"
echo "  info: combined workflow source-size trend is $context_bytes bytes (reference 20480; informational only)"

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
assert_contains "$sources_text" "bounded discovery" "SOURCES records the local brainstorming rewrite"
for token in "## Concept influences" "391a2701dd948f94f56a39f7533f8eea9a859c87" "manual review reference" "Wayfinder" "Research" "to-spec" "to-tickets" "concept only" "Similarity ratio" "Longest identical token run"; do
  assert_contains "$sources_text" "$token" "SOURCES records reviewed concept provenance: $token"
done
assert_contains "$index_text" "docs/discovery-and-planning.md" "INDEX links to the discovery reader contract"
for token in "conditional Research" "consent-gated Deep Wayfinding" "Selected Seam" "vertical slices" "GPT-5.5"; do
  assert_contains "$changelog_text" "$token" "CHANGELOG records implemented discovery contract: $token"
done

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

pilot_runner="$REPO/docs/work/discovery-planning-slices/pilot/run_pilot.py"
if [ -f "$pilot_runner" ]; then
  pilot_runner_text="$(cat "$pilot_runner")"
  assert_not_contains "$pilot_runner_text" '"kind": item["kind"]' "pilot prompt does not expose gold kind labels"
  for token in "prompt_sha256" "schema_sha256" "corpus_sha256" "evaluator_sha256" "rubric_sha256" "scorer_sha256" "identity"; do
    assert_contains "$pilot_runner_text" "$token" "pilot raw-run reuse binds $token"
  done
  assert_not_contains "$pilot_runner_text" 'changed_average_questions_lte_0_5' "pilot acceptance does not treat model-reported questions as observed UX"
  assert_not_contains "$pilot_runner_text" 'changed_conditional_load_accuracy_eq_1' "pilot acceptance does not treat predicted loading as runtime observation"
else
  TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: private pilot runner is absent from the public payload"
fi

pilot_runs="$REPO/docs/work/discovery-planning-slices/pilot/pilot-runs-v3.jsonl"
pilot_summary="$REPO/docs/work/discovery-planning-slices/pilot/pilot-summary-v3.json"
pilot_disposition="$REPO/docs/work/discovery-planning-slices/reviews/owner-pilot-disposition.md"
if python3 - "$REPO" "$pilot_summary" <<'PY'
import ast
import hashlib
import json
from pathlib import Path
import re
import sys

root = Path(sys.argv[1])
summary_path = Path(sys.argv[2])
if not summary_path.is_file():
    raise SystemExit(0)
runner_path = root / "docs/work/discovery-planning-slices/pilot/run_pilot.py"
tree = ast.parse(runner_path.read_text(encoding="utf-8"))
components = None
for node in tree.body:
    if isinstance(node, ast.Assign) and any(
        isinstance(target, ast.Name) and target.id == "COMPONENTS"
        for target in node.targets
    ):
        components = ast.literal_eval(node.value)
        break
if not isinstance(components, dict):
    raise SystemExit("pilot payload drift gate: COMPONENTS mapping missing")

current_payload = "".join(
    (root / relative).read_text(encoding="utf-8")
    for relative in components.values()
)
current_sha = hashlib.sha256(current_payload.encode("utf-8")).hexdigest()
stored_sha = json.loads(summary_path.read_text(encoding="utf-8"))[
    "changed_payload_sha256"
]

if current_sha != stored_sha:
    evidence_paths = (
        root / "docs/discovery-and-planning.md",
        root / "CHANGELOG.md",
        root / "docs/STATUS.md",
        root / "docs/work/discovery-planning-slices/implement-report.md",
        root / "docs/work/discovery-planning-slices/reviews/fable-final-review.md",
    )
    marker = "pre-T10 historical negative evidence"
    missing = [str(path.relative_to(root)) for path in evidence_paths if marker not in path.read_text(encoding="utf-8")]
    if missing:
        raise SystemExit(
            "pilot payload drift gate: stored classifier payload "
            f"{stored_sha} differs from current {current_sha}; "
            f"missing historical-evidence label in {missing}"
        )
    association = re.compile(
        r"(?i)(?:current|post-T10|shipping|shipped|目前)[^\n]{0,140}(?:0\.8333|83\.33)|"
        r"(?:0\.8333|83\.33)[^\n]{0,140}(?:current|post-T10|shipping|shipped|目前)"
    )
    associated = [
        str(path.relative_to(root))
        for path in evidence_paths
        if association.search(path.read_text(encoding="utf-8"))
    ]
    if associated:
        raise SystemExit(
            "pilot payload drift gate: historical classifier score is associated "
            f"with the current/post-T10 shipping payload in {associated}"
        )
PY
then
  TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: classifier evidence stays bound to its stored payload identity"
else
  fail "classifier evidence stays bound to its stored payload identity"
fi
if [ -f "$pilot_runs" ] && [ -f "$pilot_summary" ] && python3 - "$pilot_runs" "$pilot_summary" "$pilot_disposition" <<'PY'
import hashlib
import json
from pathlib import Path
import sys

runs = [json.loads(line) for line in Path(sys.argv[1]).read_text().splitlines() if line]
summary = json.loads(Path(sys.argv[2]).read_text())
if len(runs) != 6:
    raise SystemExit(f"pilot identity gate: expected 6 runs, got {len(runs)}")
expected_keys = {
    (condition, repetition)
    for condition in ("baseline", "changed")
    for repetition in (1, 2, 3)
}
actual_keys = {(r["condition"], r["repetition"]) for r in runs}
if actual_keys != expected_keys:
    raise SystemExit(f"pilot identity gate: run keys differ: {sorted(actual_keys)}")
for run in runs:
    identity = run["identity"]
    condition = run["condition"]
    expected_identity = {
        "condition": condition,
        "repetition": run["repetition"],
        "corpus_sha256": summary["corpus_sha256"],
        "schema_sha256": summary["schema_sha256"],
        "evaluator_sha256": summary["evaluator_sha256"],
        "rubric_sha256": summary["rubric_sha256"],
        "scorer_sha256": summary["scorer_sha256"],
        "prompt_sha256": summary["prompt_sha256"][condition],
    }
    for key, value in expected_identity.items():
        if identity.get(key) != value:
            raise SystemExit(
                f"pilot identity gate: {condition}/{run['repetition']} {key} mismatch"
            )
passing_acceptance = {
    "all_six_runs_completed": True,
    "changed_case_exact_accuracy_gte_0_90": True,
    "pass": True,
}
acceptance = summary["scores"]["acceptance"]
if acceptance != passing_acceptance:
    score = summary["scores"]["changed"]["case_exact_accuracy"]
    disposition_path = Path(sys.argv[3])
    if not disposition_path.is_file():
        raise SystemExit(
            f"pilot acceptance gate: changed exact={score:.4f}, required>=0.9000; "
            "owner disposition missing"
        )
    disposition = disposition_path.read_text()
    summary_sha = hashlib.sha256(Path(sys.argv[2]).read_bytes()).hexdigest()
    required = (
        "Decision: accept-without-effectiveness-claim",
        f"Pilot summary SHA-256: `{summary_sha}`",
        "does not relabel the smoke as PASS",
    )
    missing = [token for token in required if token not in disposition]
    if missing:
        raise SystemExit(f"pilot owner-disposition gate: missing {missing}")
PY
then
  TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: v3 pilot is identity-bound and either passes or has an exact owner no-claim disposition"
elif [ ! -e "$pilot_runs" ] && [ ! -e "$pilot_summary" ]; then
  TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: private pilot evidence is absent from the public payload"
else
  fail "v3 pilot is identity-bound and either passes or has an exact owner no-claim disposition"
fi

finish
