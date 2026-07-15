#!/usr/bin/env bash
set -u
REPO="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
. "$REPO/tests/bootstrap/lib/assert.sh"

run_gate_text="$(cat "$REPO/scripts/run-gate.sh")"
run_gate_extended_filters="$(printf '%s\n' "$run_gate_text" | grep -c 'grep -vE "test|spec')"
assert_eq "3" "$run_gate_extended_filters" "run-gate uses portable ERE alternation for all three exclusion filters"

artifacts_text="$(cat "$REPO/ARTIFACTS.md")"
assert_not_contains "$artifacts_text" "brainstorm: { skill: brainstorming" "artifact contract keeps Deep control outside lifecycle stages"
assert_contains "$artifacts_text" "brainstorm.md" "artifact contract recognizes the optional discovery document"
assert_contains "$artifacts_text" "inputs" "artifact contract links optional discovery through existing inputs"
assert_contains "$artifacts_text" "release: { skill: sync-work" "artifact release stage uses the authoritative Git owner"
assert_not_contains "$(cat "$REPO/protocol-registry.json")" '"brainstorm"' "protocol registry has no undeclared brainstorm lifecycle"

mkdir -p "$TMP/project/.git" "$TMP/project/.agent" "$TMP/project/src" "$TMP/project/tests"
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

PROFILE=all bash "$REPO/bootstrap/generate.sh" \
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
write_output plan/plan.md \
  '# Plan: Dummy greeting

## Plan
- Format: canonical-v2
- Intent: Implement and verify the greeting.
- Scope: One shell script and its test.
- Non-goals: No unrelated behavior.

## Sources
- local: ../prd.md#AC-001

## Tasks

### T01 | implement greet
- Status: pending
- Depends On: []

#### Intent
Implement the greeting after observing a failing test.

#### Expected Result
The script prints hello.

#### Definition of Done
- The greeting test passes.

#### Verification
- Run tests/greet_test.sh.

## Change Log
- 2026-06-18: Created the canonical plan.'
printf '%s\n' \
  'schema_version: work-item/v3' \
  'slug: hello' \
  'title: Dummy greeting' \
  'created_at: 2026-06-18T00:00:00+08:00' \
  'updated_at: 2026-06-18T00:00:00+08:00' \
  'execution_mode: team-feature' \
  'work_status: active' \
  'delivery_status: not_requested' \
  'stages:' \
  '  prd: { skill: prd-interview, file: prd.md, status: ready }' \
  '  spec: { skill: spec, file: spec.md, status: ready }' \
  '  qa-plan: { skill: qa, file: qa-plan.md, status: ready }' \
  '  plan: { skill: plan-sync, file: plan/plan.md, status: ready }' \
  '  implement: { skill: implement, file: implement-report.md, status: pending }' \
  '  qa-report: { skill: qa, file: qa-report.md, status: pending }' \
  'inputs:' \
  '  - dummy-request' \
  > "$WORK/meta.yml"

if python3 "$REPO/plan-sync/scripts/planctl.py" check --plan-dir "$WORK/plan" >/dev/null; then
  TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: artifact-contract smoke plan passes canonical validation"
else
  fail "artifact-contract smoke plan passes canonical validation"
fi

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
  -e 's/work_status: active/work_status: completed/' \
  -e 's/delivery_status: not_requested/delivery_status: awaiting_approval/' \
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
  "docs/work/hello/plan/plan.md" \
  "docs/work/hello/implement-report.md" \
  "docs/work/hello/qa-report.md"; do
  assert_file "$TMP/project/$required" "artifact-contract smoke produced $required"
done

meta_count="$(find "$TMP/project/docs/work" -name meta.yml -type f | wc -l | tr -d ' ')"
assert_eq "1" "$meta_count" "artifact-contract smoke work item has one shared meta.yml"
assert_contains "$(cat "$WORK/meta.yml")" "work_status: completed" "artifact-contract smoke records completed work"
assert_contains "$(cat "$WORK/meta.yml")" "delivery_status: awaiting_approval" "artifact-contract smoke does not invent delivery"
assert_contains "$(cat "$WORK/meta.yml")" "qa-report.md, status: validated" "artifact-contract smoke QA stage is validated"
assert_contains "$(cat "$WORK/prd.md")" "## Delivery" "artifact-contract smoke PRD records delivery"
assert_contains "$(cat "$WORK/adr.md")" "promoted-to: docs/decisions.md" "artifact-contract smoke closeout records promotion provenance"
if bash "$REPO/scripts/work-items.sh" --work-root "$TMP/project/docs/work" check >/dev/null; then
  TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: artifact-contract smoke produces valid work-item/v3 metadata"
else
  fail "artifact-contract smoke produces valid work-item/v3 metadata"
fi

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
  PROFILE=all bash "$REPO/bootstrap/generate.sh" \
    "$fixture_project/.claude/skills" \
    "$fixture_project/.codex/skills" >/dev/null
  git -C "$fixture_project" init -q
  git -C "$fixture_project" checkout -q -b main
  git -C "$fixture_project" config core.excludesFile /dev/null
  git -C "$fixture_project" add -A
  git -C "$fixture_project" -c user.name='Artifact Test' -c user.email=artifact@example.com \
    commit -qm 'fixture baseline'

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
    assert_contains "$gate_output" "no production console.log" "gate exclusion filter spares console.log in test files"
    assert_contains "$gate_output" "no unbounded any types" "gate exclusion filter spares any types in test files"
    assert_contains "$gate_output" "no hard-coded color values" "gate exclusion filter spares color literals in test files"
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
    assert_not_contains "$hardcoded_secret_output" "abcdef123456" "TS Web secret scan redacts the hard-coded secret value"
    printf 'export const token = import.meta.env.VITE_SECRET_TOKEN\n' > "$fixture_project/src/vite-secret-regression.ts"
    set +e
    vite_secret_output="$(cd "$fixture_project" && PROJECT_MANIFEST="$manifest" bash "$REPO/security/scripts/scan-secrets.sh" 2>&1)"
    vite_secret_rc=$?
    set -e
    assert_neq "0" "$vite_secret_rc" "TS Web secret scan rejects sensitive Vite client env prefixes"
    assert_contains "$vite_secret_output" "src/vite-secret-regression.ts" "TS Web secret scan reports the Vite client env path"
    assert_contains "$vite_secret_output" "client-exposed env candidate redacted" "TS Web secret scan labels a redacted client env finding"
  fi
done

# Secret preflight failures must fail closed before emitting any CLEAR result.
scanner_order_check="$(python3 - "$REPO/security/scripts/scan-secrets.sh" <<'PY'
from pathlib import Path
import sys

lines = [
    line for line in Path(sys.argv[1]).read_text().splitlines()
    if "grep -r" in line and "include_args" in line and "exclude_args" in line
]
if lines and all(line.index("include_args") < line.index("exclude_args") for line in lines):
    print("portable")
else:
    print("non-portable")
PY
)"
assert_eq "portable" "$scanner_order_check" "secret scanner applies includes before excludes for GNU/BSD parity"

make_scanner_fixture() {
  fixture_name="$1"
  ignore_rule="$2"
  source_roots="${3:-src}"
  source_extensions="${4:-py}"
  SCANNER_FIXTURE="$TMP/scanner/$fixture_name"
  mkdir -p "$SCANNER_FIXTURE/.agent" "$SCANNER_FIXTURE/src"
  printf '%s\n' \
    '## Paths' \
    "- source_roots: $source_roots" \
    '## Stack' \
    "- source_extensions: $source_extensions" \
    '- framework: python-cli' \
    '- package_manager: python' \
    '- has_ui: false' \
    > "$SCANNER_FIXTURE/.agent/project-manifest.md"
  printf '%s\n' "$ignore_rule" > "$SCANNER_FIXTURE/.gitignore"
  printf 'def greet():\n    return "hello"\n' > "$SCANNER_FIXTURE/src/greet.py"
  git -C "$SCANNER_FIXTURE" init -q
  git -C "$SCANNER_FIXTURE" checkout -q -b main
  git -C "$SCANNER_FIXTURE" config core.excludesFile /dev/null
  git -C "$SCANNER_FIXTURE" add -A
  git -C "$SCANNER_FIXTURE" -c user.name='Scanner Test' -c user.email=scanner@example.com \
    commit -qm 'fixture baseline'
}

make_scanner_fixture too-many-args '.env'
set +e
too_many_output="$(cd "$SCANNER_FIXTURE" && bash "$REPO/security/scripts/scan-secrets.sh" src tests 2>&1)"
too_many_rc=$?
set -e
assert_neq "0" "$too_many_rc" "secret scanner rejects more than one target argument"
assert_contains "$too_many_output" "at most one target" "secret scanner explains its argument contract"

make_scanner_fixture missing-default '.env' 'src missing-root'
set +e
missing_default_output="$(cd "$SCANNER_FIXTURE" && bash "$REPO/security/scripts/scan-secrets.sh" 2>&1)"
missing_default_rc=$?
set -e
assert_neq "0" "$missing_default_rc" "secret scanner rejects a missing default target"
assert_not_contains "$missing_default_output" "CLEAR:" "target validation completes before any CLEAR result"

make_scanner_fixture untraversable-target '.env'
mkdir -p "$SCANNER_FIXTURE/locked"
chmod 600 "$SCANNER_FIXTURE/locked"
set +e
untraversable_output="$(cd "$SCANNER_FIXTURE" && bash "$REPO/security/scripts/scan-secrets.sh" locked 2>&1)"
untraversable_rc=$?
set -e
chmod 700 "$SCANNER_FIXTURE/locked"
assert_neq "0" "$untraversable_rc" "secret scanner rejects an untraversable target"
assert_not_contains "$untraversable_output" "CLEAR:" "untraversable target fails before scan results"

make_scanner_fixture outside-worktree '.env'
outside_target="$TMP/scanner/outside-worktree-source"
mkdir -p "$outside_target"
printf "%s = '%s'\n" password outside-secret-value > "$outside_target/leak.py"
set +e
outside_output="$(cd "$SCANNER_FIXTURE" && bash "$REPO/security/scripts/scan-secrets.sh" "$outside_target" 2>&1)"
outside_rc=$?
set -e
assert_neq "0" "$outside_rc" "secret scanner rejects a target outside the Git worktree"
assert_contains "$outside_output" "outside the Git worktree" "secret scanner explains the target boundary"
assert_not_contains "$outside_output" "CLEAR:" "outside target rejection happens before scan results"
assert_not_contains "$outside_output" "outside-secret-value" "outside target content is never emitted"

make_scanner_fixture symlink-target '.env'
symlink_victim="$TMP/scanner/symlink-target-victim"
mkdir -p "$symlink_victim"
printf "%s = '%s'\n" password symlink-secret-value > "$symlink_victim/leak.py"
ln -s "$symlink_victim" "$SCANNER_FIXTURE/source-link"
set +e
symlink_output="$(cd "$SCANNER_FIXTURE" && bash "$REPO/security/scripts/scan-secrets.sh" source-link 2>&1)"
symlink_rc=$?
set -e
assert_neq "0" "$symlink_rc" "secret scanner rejects a symlink target"
assert_contains "$symlink_output" "symlink" "secret scanner explains the symlink boundary"
assert_not_contains "$symlink_output" "CLEAR:" "symlink target rejection happens before scan results"
assert_not_contains "$symlink_output" "symlink-secret-value" "symlink target content is never emitted"
set +e
symlink_slash_output="$(cd "$SCANNER_FIXTURE" && bash "$REPO/security/scripts/scan-secrets.sh" source-link/ 2>&1)"
symlink_slash_rc=$?
set -e
assert_neq "0" "$symlink_slash_rc" "secret scanner rejects a symlink target with a trailing slash"
assert_contains "$symlink_slash_output" "symlink" "trailing-slash symlink error is actionable"
assert_not_contains "$symlink_slash_output" "CLEAR:" "trailing-slash symlink fails before scan results"
assert_not_contains "$symlink_slash_output" "symlink-secret-value" "trailing-slash symlink content is never emitted"

make_scanner_fixture type-ignore-secret '.env'
printf "%s = '%s'  # type: ignore\n" password type-ignore-real-secret > "$SCANNER_FIXTURE/src/greet.py"
set +e
type_ignore_output="$(cd "$SCANNER_FIXTURE" && bash "$REPO/security/scripts/scan-secrets.sh" 2>&1)"
type_ignore_rc=$?
set -e
assert_neq "0" "$type_ignore_rc" "secret scanner catches a real secret beside a type-ignore comment"
assert_contains "$type_ignore_output" "src/greet.py" "type-ignore finding retains its file location"
assert_contains "$type_ignore_output" "hard-coded secret candidate redacted" "type-ignore finding retains a useful category"
assert_not_contains "$type_ignore_output" "type-ignore-real-secret" "type-ignore finding redacts the secret value"

make_scanner_fixture env-fallback-secret '.env'
printf '%s%s%s\n' \
  'api_key = os.environ.get("API_KEY") ' \
  'or "fallback-real-secret-value' \
  '"' > "$SCANNER_FIXTURE/src/greet.py"
set +e
env_fallback_output="$(cd "$SCANNER_FIXTURE" && bash "$REPO/security/scripts/scan-secrets.sh" 2>&1)"
env_fallback_rc=$?
set -e
assert_neq "0" "$env_fallback_rc" "secret scanner catches a hard-coded environment fallback"
assert_contains "$env_fallback_output" "src/greet.py" "environment fallback finding retains its file location"
assert_contains "$env_fallback_output" "hard-coded secret candidate redacted" "environment fallback finding retains a useful category"
assert_not_contains "$env_fallback_output" "fallback-real-secret-value" "environment fallback finding redacts the secret value"

make_scanner_fixture process-env-fallback-secret '.env' src js
printf '%s%s%s\n' \
  'api_key = process.env.API_KEY ' \
  '|| "abcdefgh123456' \
  '"' > "$SCANNER_FIXTURE/src/greet.js"
set +e
process_env_fallback_output="$(cd "$SCANNER_FIXTURE" && bash "$REPO/security/scripts/scan-secrets.sh" 2>&1)"
process_env_fallback_rc=$?
set -e
assert_neq "0" "$process_env_fallback_rc" "secret scanner catches a JavaScript environment fallback"
assert_contains "$process_env_fallback_output" "src/greet.js" "JavaScript fallback finding retains its file location"
assert_contains "$process_env_fallback_output" "hard-coded secret candidate redacted" "JavaScript fallback finding retains a useful category"
assert_not_contains "$process_env_fallback_output" "abcdefgh123456" "JavaScript fallback finding redacts the secret value"

make_scanner_fixture placeholder-value '.env'
printf "password = 'example-password'\n" > "$SCANNER_FIXTURE/src/greet.py"
set +e
placeholder_output="$(cd "$SCANNER_FIXTURE" && bash "$REPO/security/scripts/scan-secrets.sh" 2>&1)"
placeholder_rc=$?
set -e
assert_eq "0" "$placeholder_rc" "secret scanner retains a demonstrable placeholder-value exemption"

make_scanner_fixture uppercase-committed-secret '.env'
printf '%s = "%s"\n' API_KEY committed-uppercase-secret-value > "$SCANNER_FIXTURE/src/greet.py"
git -C "$SCANNER_FIXTURE" add src/greet.py
git -C "$SCANNER_FIXTURE" -c user.name='Scanner Test' -c user.email=scanner@example.com \
  commit -qm 'add uppercase secret fixture'
set +e
uppercase_secret_output="$(cd "$SCANNER_FIXTURE" && bash "$REPO/security/scripts/scan-secrets.sh" 2>&1)"
uppercase_secret_rc=$?
set -e
assert_neq "0" "$uppercase_secret_rc" "secret scanner catches committed uppercase secret identifiers"
assert_contains "$uppercase_secret_output" "hard-coded secret candidate redacted" "uppercase secret finding stays redacted"
assert_not_contains "$uppercase_secret_output" "committed-uppercase-secret-value" "uppercase secret value never reaches output"

make_scanner_fixture log-redaction '.env'
printf 'PRINT("TOKEN raw-log-secret-value")\n' > "$SCANNER_FIXTURE/src/greet.py"
set +e
log_redaction_output="$(cd "$SCANNER_FIXTURE" && bash "$REPO/security/scripts/scan-secrets.sh" 2>&1)"
log_redaction_rc=$?
set -e
assert_eq "0" "$log_redaction_rc" "uppercase secret-log candidate remains a non-blocking warning"
assert_contains "$log_redaction_output" "src/greet.py" "secret-log warning retains its file location"
assert_contains "$log_redaction_output" "secret-log candidate redacted" "secret-log warning retains a useful category"
assert_not_contains "$log_redaction_output" "raw-log-secret-value" "secret-log warning redacts the source content"

make_scanner_fixture structured-json-log '.env'
printf 'print(json.dumps(payload, indent=2, sort_keys=True))\n' > "$SCANNER_FIXTURE/src/greet.py"
set +e
structured_log_output="$(cd "$SCANNER_FIXTURE" && bash "$REPO/security/scripts/scan-secrets.sh" 2>&1)"
structured_log_rc=$?
set -e
assert_eq "0" "$structured_log_rc" "structured JSON output remains a clean scanner run"
assert_contains "$structured_log_output" "CLEAR: no obvious secret-log candidates" "sort_keys does not create a secret-log warning"
assert_not_contains "$structured_log_output" "WARN: review possible secrets in logs" "structured JSON output stays warning-free"

make_scanner_fixture staged-redaction '.env'
printf "%s = '%s'\n" password staged-real-secret-value > "$SCANNER_FIXTURE/src/greet.py"
git -C "$SCANNER_FIXTURE" add src/greet.py
set +e
staged_redaction_output="$(cd "$SCANNER_FIXTURE" && bash "$REPO/security/scripts/scan-secrets.sh" 2>&1)"
staged_redaction_rc=$?
set -e
assert_neq "0" "$staged_redaction_rc" "secret scanner catches a staged secret"
assert_contains "$staged_redaction_output" "src/greet.py:" "staged finding retains its file and line location"
assert_contains "$staged_redaction_output" "staged secret candidate redacted" "staged finding retains a useful category"
assert_not_contains "$staged_redaction_output" "staged-real-secret-value" "staged finding redacts the secret value"

make_scanner_fixture staged-token-redaction '.env'
printf "%s = '%s'\n" token realstagedtokenvalue123 > "$SCANNER_FIXTURE/src/greet.py"
git -C "$SCANNER_FIXTURE" add src/greet.py
set +e
staged_token_output="$(cd "$SCANNER_FIXTURE" && bash "$REPO/security/scripts/scan-secrets.sh" 2>&1)"
staged_token_rc=$?
set -e
assert_neq "0" "$staged_token_rc" "secret scanner preserves staged token-name coverage"
assert_contains "$staged_token_output" "staged secret candidate redacted" "staged token finding stays categorized"
assert_not_contains "$staged_token_output" "realstagedtokenvalue123" "staged token value stays redacted"

non_git="$TMP/scanner/non-git"
mkdir -p "$non_git/.agent" "$non_git/src"
printf '%s\n' \
  '## Paths' '- source_roots: src' \
  '## Stack' '- source_extensions: py' '- has_ui: false' \
  > "$non_git/.agent/project-manifest.md"
printf '.env\n' > "$non_git/.gitignore"
printf 'value = "safe"\n' > "$non_git/src/main.py"
set +e
non_git_output="$(cd "$non_git" && bash "$REPO/security/scripts/scan-secrets.sh" 2>&1)"
non_git_rc=$?
set -e
assert_neq "0" "$non_git_rc" "secret scanner rejects a non-Git workspace"
assert_not_contains "$non_git_output" "CLEAR:" "non-Git workspace fails before scan results"

for env_case in example-only comment-only negated; do
  case "$env_case" in
    example-only) env_rule='.env.example' ;;
    comment-only) env_rule='# ignore .env locally' ;;
    negated) env_rule='.env
!.env' ;;
  esac
  make_scanner_fixture "env-$env_case" "$env_rule"
  set +e
  env_output="$(cd "$SCANNER_FIXTURE" && bash "$REPO/security/scripts/scan-secrets.sh" 2>&1)"
  env_rc=$?
  set -e
  assert_neq "0" "$env_rc" "secret scanner rejects $env_case as proof that .env is ignored"
  assert_contains "$env_output" ".env is not excluded" "secret scanner reports Git ignore semantics for $env_case"
done

make_scanner_fixture grep-error '.env'
mkdir -p "$SCANNER_FIXTURE/fakebin"
cat > "$SCANNER_FIXTURE/fakebin/grep" <<'EOF'
#!/usr/bin/env bash
exit 2
EOF
chmod +x "$SCANNER_FIXTURE/fakebin/grep"
set +e
grep_error_output="$(cd "$SCANNER_FIXTURE" && PATH="$SCANNER_FIXTURE/fakebin:$PATH" bash "$REPO/security/scripts/scan-secrets.sh" 2>&1)"
grep_error_rc=$?
set -e
assert_neq "0" "$grep_error_rc" "secret scanner blocks when grep cannot complete"
assert_contains "$grep_error_output" "grep failed" "secret scanner distinguishes grep errors from no matches"

make_scanner_fixture staged-diff-error '.env'
mkdir -p "$SCANNER_FIXTURE/fakebin"
real_git="$(command -v git)"
cat > "$SCANNER_FIXTURE/fakebin/git" <<'EOF'
#!/usr/bin/env bash
if [ "${1:-}" = "diff" ] && [ "${2:-}" = "--cached" ]; then
  exit 128
fi
exec "$REAL_GIT" "$@"
EOF
chmod +x "$SCANNER_FIXTURE/fakebin/git"
set +e
staged_error_output="$(cd "$SCANNER_FIXTURE" && REAL_GIT="$real_git" PATH="$SCANNER_FIXTURE/fakebin:$PATH" bash "$REPO/security/scripts/scan-secrets.sh" 2>&1)"
staged_error_rc=$?
set -e
assert_neq "0" "$staged_error_rc" "secret scanner blocks when staged diff cannot be read"
assert_contains "$staged_error_output" "staged diff failed" "secret scanner reports staged diff execution failure"

# The artifact contract documents a forward-only adoption stance so introducing
# a shape gate never retroactively fails existing history.
artifacts_doc="$(cat "$REPO/ARTIFACTS.md")"
assert_contains "$artifacts_doc" "## Schema evolution and adoption" "ARTIFACTS documents the schema evolution and adoption stance"
assert_contains "$artifacts_doc" "grandfathered" "ARTIFACTS documents that existing artifacts are grandfathered"
assert_contains "$artifacts_doc" "sweep is opt-in" "ARTIFACTS documents that a repository-wide gate sweep is opt-in"

finish
