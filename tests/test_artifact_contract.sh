#!/usr/bin/env bash
set -u
REPO="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
. "$REPO/tests/bootstrap/lib/assert.sh"

mkdir -p "$TMP/project/.agent" "$TMP/project/src" "$TMP/project/tests"
printf '%s\n' \
  '## Project Identity' \
  '- name: dummy-pipeline' \
  '## Skill Roots' \
  '- shared_skills_root: .agent/skills/_shared' \
  '- project_skills_root: .agent/skills/project' \
  '## Paths' \
  '- work_root: docs/work' \
  '- docs_root: docs' \
  > "$TMP/project/.agent/project-manifest.md"
printf '# Guardrails\n- workspace-only writes\n' > "$TMP/project/.agent/guardrails.md"

bash "$REPO/bootstrap/generate.sh" \
  "$TMP/project/.claude/skills" \
  "$TMP/project/.codex/skills" >/dev/null

WORK="$TMP/project/docs/work/hello"
mkdir -p "$WORK/plan"

write_output() {
  path="$1"; body="$2"
  mkdir -p "$(dirname "$WORK/$path")"
  printf '%s\n' "$body" > "$WORK/$path"
}

write_output prd.md \
  '# Dummy PRD
AC-001: running greet.sh prints hello'
write_output spec.md \
  '# Dummy Spec
Create src/greet.sh and test observable stdout.'
write_output qa-plan.md \
  '# Dummy QA Plan
TC-001 maps to AC-001 and expects stdout hello.'
write_output adr.md \
  '# Dummy Decision

## Output contract
The greeting is plain text.'
write_output plan/implementation.md \
  '# Dummy Plan
Write failing test, implement minimum shell script, rerun test.'
printf '# Dummy Tasks\n- [ ] T01 implement greet\n' \
  > "$WORK/plan/tasks.md"
printf '# Dummy Notes\nCurrent State Snapshot: planned\n' \
  > "$WORK/plan/notes.md"
printf '%s\n' \
  'slug: hello' \
  'title: Dummy greeting' \
  'created_at: 2026-06-18T00:00:00+08:00' \
  'updated_at: 2026-06-18T00:00:00+08:00' \
  'status: active' \
  'stages:' \
  '  prd: { skill: prd-interview, file: prd.md, status: ready }' \
  '  spec: { skill: spec, file: spec.md, status: ready }' \
  '  qa-plan: { skill: qa, file: qa-plan.md, status: ready }' \
  '  implement: { skill: implement, file: implement-report.md, status: pending }' \
  '  qa-report: { skill: qa, file: qa-report.md, status: pending }' \
  'inputs:' \
  '  - dummy-request' \
  > "$WORK/meta.yml"

printf '%s\n' \
  '#!/usr/bin/env bash' \
  'set -euo pipefail' \
  'out="$(bash "$(dirname "$0")/../src/greet.sh")"' \
  '[ "$out" = "hello" ]' \
  > "$TMP/project/tests/greet_test.sh"

set +e
bash "$TMP/project/tests/greet_test.sh" >/dev/null 2>&1
red_rc=$?
set -e
assert_neq "0" "$red_rc" "artifact-contract smoke implementation observes RED before production code"

printf '%s\n' '#!/usr/bin/env bash' 'printf "hello\n"' > "$TMP/project/src/greet.sh"
if bash "$TMP/project/tests/greet_test.sh"; then
  TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: artifact-contract smoke implementation reaches GREEN"
else
  fail "artifact-contract smoke implementation reaches GREEN"
fi

write_output implement-report.md \
  '# Dummy Implement Report
RED: greet.sh absent
GREEN: greet_test.sh passes'

write_output qa-report.md \
  '# Dummy QA Report
AC-001: PASS
TC-001: PASS'
cat >> "$WORK/prd.md" <<'EOF'

## Delivery
- 發布日：2026-06-18
- 與 PRD 的偏差：無
- 驗收：[qa-report.md](qa-report.md)（PASS）
EOF
cat >> "$WORK/adr.md" <<'EOF'

> promoted-to: docs/decisions.md
EOF
sed -i.bak \
  -e 's/updated_at: 2026-06-18T00:00:00+08:00/updated_at: 2026-06-18T01:00:00+08:00/' \
  -e 's/status: active/status: shipped/' \
  -e 's/status: ready/status: done/g' \
  -e 's/status: pending }/status: done }/' \
  -e 's/qa-report.md, status: done/qa-report.md, status: validated/' \
  "$WORK/meta.yml"
rm -f "$WORK/meta.yml.bak"

for required in \
  "docs/work/hello/prd.md" \
  "docs/work/hello/spec.md" \
  "docs/work/hello/qa-plan.md" \
  "docs/work/hello/adr.md" \
  "docs/work/hello/plan/implementation.md" \
  "docs/work/hello/plan/tasks.md" \
  "docs/work/hello/plan/notes.md" \
  "docs/work/hello/implement-report.md" \
  "docs/work/hello/qa-report.md"; do
  assert_file "$TMP/project/$required" "artifact-contract smoke produced $required"
done

meta_count="$(find "$TMP/project/docs/work" -name meta.yml -type f | wc -l | tr -d ' ')"
assert_eq "1" "$meta_count" "artifact-contract smoke work item has one shared meta.yml"
assert_contains "$(cat "$WORK/meta.yml")" "status: shipped" "artifact-contract smoke work item is closed out"
assert_contains "$(cat "$WORK/meta.yml")" "qa-report.md, status: validated" "artifact-contract smoke QA stage is validated"
assert_contains "$(cat "$WORK/prd.md")" "## Delivery" "artifact-contract smoke PRD records delivery"
assert_contains "$(cat "$WORK/adr.md")" "promoted-to: docs/decisions.md" "artifact-contract smoke closeout records promotion provenance"

claude_count="$(find "$TMP/project/.claude/skills" -mindepth 2 -maxdepth 2 -name SKILL.md -type f | wc -l | tr -d ' ')"
codex_count="$(find "$TMP/project/.codex/skills" -mindepth 2 -maxdepth 2 -name SKILL.md -type f | wc -l | tr -d ' ')"
expected_workflow_count="$(
  find "$REPO" -mindepth 2 -maxdepth 2 -type f -name SKILL.md \
    -not -path "$REPO/_archive/*" \
    -not -path "$REPO/.claude/*" \
    -not -path "$REPO/.codex/*" \
    -not -path "$REPO/.agents/*" \
    -print |
    sed "s#^$REPO/##;s#/SKILL.md##" |
    grep -vx 'skill-creator' |
    wc -l |
    tr -d ' '
)"
assert_eq "$expected_workflow_count" "$claude_count" "artifact-contract smoke consuming repo has all Claude workflow skills"
assert_eq "$expected_workflow_count" "$codex_count" "artifact-contract smoke consuming repo has all Codex workflow skills"

# The same manifest-driven pipeline must work for different stacks without
# language-specific profiles.
for fixture_name in python-cli ts-web; do
  fixture_source="$REPO/tests/fixtures/$fixture_name"
  fixture_project="$TMP/fixtures/$fixture_name"
  if [ ! -d "$fixture_source" ]; then
    fail "$fixture_name fixture exists"
    continue
  fi
  if git -C "$REPO" ls-files --error-unmatch "tests/fixtures/$fixture_name/.gitignore" >/dev/null 2>&1; then
    TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: $fixture_name fixture gitignore is published"
  else
    fail "$fixture_name fixture gitignore is published"
  fi
  mkdir -p "$(dirname "$fixture_project")"
  cp -R "$fixture_source" "$fixture_project"
  manifest="$fixture_project/.agent/project-manifest.md"
  mkdir -p "$fixture_project/.claude/skills" "$fixture_project/.codex/skills"
  bash "$REPO/bootstrap/generate.sh" \
    "$fixture_project/.claude/skills" \
    "$fixture_project/.codex/skills" >/dev/null

  set +e
  verify_output="$(cd "$fixture_project" && PROJECT_MANIFEST="$manifest" bash "$REPO/verification-before-completion/scripts/verify.sh" 2>&1)"
  verify_rc=$?
  qa_output="$(cd "$fixture_project" && PROJECT_MANIFEST="$manifest" bash "$REPO/qa/scripts/run-qa.sh" 2>&1)"
  qa_rc=$?
  gate_output="$(cd "$fixture_project" && PROJECT_MANIFEST="$manifest" bash "$REPO/scripts/run-gate.sh" full 2>&1)"
  gate_rc=$?
  api_gate_output="$(cd "$fixture_project" && PROJECT_MANIFEST="$manifest" bash "$REPO/scripts/run-gate.sh" api-endpoints 2>&1)"
  api_gate_rc=$?
  secret_output="$(cd "$fixture_project" && PROJECT_MANIFEST="$manifest" bash "$REPO/security/scripts/scan-secrets.sh" 2>&1)"
  secret_rc=$?
  scan_output="$(cd "$fixture_project" && node "$REPO/shared-skill-onboarder/scripts/scan-project.js" 2>&1)"
  scan_rc=$?
  set -e

  assert_eq "0" "$verify_rc" "$fixture_name verification pipeline passes"
  assert_eq "0" "$qa_rc" "$fixture_name QA pipeline passes"
  assert_eq "0" "$gate_rc" "$fixture_name full deterministic gate passes"
  assert_eq "0" "$api_gate_rc" "$fixture_name capability-aware API gate passes"
  assert_eq "0" "$secret_rc" "$fixture_name manifest-aware secret scan passes"
  assert_eq "0" "$scan_rc" "$fixture_name onboarding scan passes"

  if [ "$fixture_name" = "python-cli" ]; then
    assert_contains "$verify_output" "type-check N/A" "Python CLI does not invent a typed-contract gate"
    assert_contains "$qa_output" "E2E N/A" "Python CLI does not invent an E2E gate"
    assert_contains "$gate_output" "design-token N/A" "Python CLI does not invent a UI gate"
    assert_contains "$api_gate_output" "api-check N/A" "Python CLI does not invent an API gate"
    assert_not_contains "$gate_output" "npm" "Python CLI gate has no npm assumption"
    assert_contains "$secret_output" "Secret scan extensions: py" "Python secret scan reads manifest extensions"
    assert_contains "$scan_output" 'has_ui: `false`' "onboarding detects no UI capability"
    assert_contains "$scan_output" 'source_extensions: `py`' "onboarding detects Python extensions"
  else
    assert_contains "$verify_output" "type-check PASSED" "TS Web runs typed-contract verification"
    assert_contains "$qa_output" "E2E step complete" "TS Web runs E2E verification"
    assert_contains "$gate_output" "Design Token" "TS Web runs UI gate"
    assert_contains "$api_gate_output" "PASS" "TS Web runs API gate"
    assert_contains "$scan_output" 'has_ui: `true`' "onboarding detects UI capability"
    assert_contains "$scan_output" 'has_api: `true`' "onboarding detects API capability"
    assert_contains "$scan_output" 'typed_contracts: `true`' "onboarding detects typed contracts"
    mkdir -p "$fixture_project/src/types"
    printf 'export const latest = { password: "abcdef123456" }\n' > "$fixture_project/src/types/leak.ts"
    set +e
    hardcoded_secret_output="$(cd "$fixture_project" && PROJECT_MANIFEST="$manifest" bash "$REPO/security/scripts/scan-secrets.sh" 2>&1)"
    hardcoded_secret_rc=$?
    set -e
    rm -f "$fixture_project/src/types/leak.ts"
    assert_neq "0" "$hardcoded_secret_rc" "TS Web secret scan catches hard-coded secrets in ordinary paths/content"
    assert_contains "$hardcoded_secret_output" "src/types/leak.ts" "TS Web secret scan reports the hard-coded secret path"
    printf 'export const token = import.meta.env.VITE_SECRET_TOKEN\n' > "$fixture_project/src/vite-secret-regression.ts"
    set +e
    vite_secret_output="$(cd "$fixture_project" && PROJECT_MANIFEST="$manifest" bash "$REPO/security/scripts/scan-secrets.sh" 2>&1)"
    vite_secret_rc=$?
    set -e
    assert_neq "0" "$vite_secret_rc" "TS Web secret scan rejects sensitive Vite client env prefixes"
    assert_contains "$vite_secret_output" "VITE_SECRET_TOKEN" "TS Web secret scan reports the Vite client env leak"
  fi
done

finish
