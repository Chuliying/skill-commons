#!/usr/bin/env bash
set -u
REPO="$(cd "$(dirname "$0")/.." && pwd)"
. "$REPO/tests/bootstrap/lib/assert.sh"

skill_text="$(cat "$REPO/brainstorming/SKILL.md")"
router_text="$(cat "$REPO/skill-router/SKILL.md")"
subagent_text="$(cat "$REPO/subagent-driven-development/SKILL.md")"
readme_text="$(cat "$REPO/README.md")"
readme_en_text="$(cat "$REPO/README.en.md")"
sources_text="$(cat "$REPO/SOURCES.md")"

for token in "material ambiguity" "Skip" "Quick" "Standard" "Deep" "最多 3 個問題" "最多 2 個選項" "一次最終確認"; do
  assert_contains "$skill_text" "$token" "brainstorming defines bounded contract: $token"
done
assert_contains "$skill_text" "repo evidence" "brainstorming inspects repository evidence before asking"
assert_contains "$skill_text" "跨 session" "brainstorming makes durable output conditional"
assert_contains "$skill_text" "使用者明確同意" "Deep mode requires explicit agreement"
assert_not_contains "$skill_text" "所有需求都要經歷此流程" "brainstorming is not universal"
assert_not_contains "$skill_text" "未輸出 Checklist = 未完成 Skill" "brainstorming has no mandatory checklist"
assert_not_contains "$skill_text" "每個段落後問確認" "brainstorming has no repeated confirmation ceremony"

skill_lines="$(wc -l < "$REPO/brainstorming/SKILL.md" | tr -d ' ')"
if [ "$skill_lines" -le 120 ]; then
  TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: brainstorming stays at or below 120 lines"
else
  fail "brainstorming stays at or below 120 lines (got $skill_lines)"
fi

assert_contains "$router_text" "material ambiguity" "router uses the qualification boundary"
assert_contains "$router_text" "Skip / Quick / Standard / Deep" "router names the bounded modes"
assert_not_contains "$router_text" 'personal 預設 `brainstorming → to-prd`' "router does not force personal discovery"
assert_not_contains "$subagent_text" "先用 brainstorming + plan-sync" "subagent fallback does not force brainstorming"

for token in "### Brainstorming：有歧義才用" "Skip / Quick / Standard / Deep" "matched A/B run"; do
  assert_contains "$readme_text" "$token" "README explains brainstorming boundary: $token"
done
for token in "## Brainstorming qualification and cost" "Skip" "Quick" "Standard" "Deep" "with-skill/without-skill"; do
  assert_contains "$readme_en_text" "$token" "English README explains brainstorming boundary: $token"
done
assert_contains "$sources_text" "bounded discovery" "SOURCES records the local brainstorming rewrite"

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
assert len(rows) == 16
assert [int(item["id"]) for item in rows] == list(range(1, 17))
routes = Counter(item["expected_route"] for item in rows)
assert routes == {"skip": 8, "quick": 3, "standard": 4, "deep": 1}
for item in rows:
    assert item["prompt"].strip()
PY
then
  TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: balanced 16-case routing fixture is valid"
else
  fail "balanced 16-case routing fixture is valid"
fi

finish
