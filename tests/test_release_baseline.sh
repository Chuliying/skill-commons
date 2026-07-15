#!/usr/bin/env bash
set -u

REPO="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0
FAIL=0

pass() {
  PASS=$((PASS + 1))
  printf '  ok: %s\n' "$1"
}

fail() {
  FAIL=$((FAIL + 1))
  printf '  FAIL: %s\n' "$1" >&2
}

assert_file() {
  if test -f "$REPO/$1"; then pass "$2"; else fail "$2"; fi
}

assert_absent() {
  if test ! -e "$REPO/$1"; then pass "$2"; else fail "$2"; fi
}

assert_contains() {
  if grep -Fq -- "$2" "$REPO/$1"; then pass "$3"; else fail "$3"; fi
}

assert_profile_omits() {
  if grep -Fxq -- "$2" "$REPO/$1"; then fail "$3"; else pass "$3"; fi
}

assert_not_tracked() {
  if test -z "$(git -C "$REPO" ls-files -- "$1")"; then pass "$2"; else fail "$2"; fi
}

assert_no_hardcoded_runtime_mounts() {
  matches="$(find \
    "$REPO/qa" \
    "$REPO/security" \
    "$REPO/verification-before-completion" \
    -type f -name '*.md' \
    -exec grep -nE '\.agent/skills/_shared/(qa|security|verification-before-completion)/(scripts|hooks)' {} + 2>/dev/null || true)"
  if test -z "$matches"; then
    pass "runtime commands do not assume the default submodule mount"
  else
    fail "runtime commands do not assume the default submodule mount"
  fi
}

echo "release baseline contract"

assert_file "protocol-registry.json" "v0.8 protocol registry is present"
assert_file "bootstrap/manage.sh" "v0.8 bootstrap lifecycle manager is present"
assert_file "plan-sync/scripts/planctl.py" "canonical-v2 planctl is present"
assert_file "scripts/check-prd.py" "v0.6+ canonical PRD gate is preserved"
assert_contains "ARTIFACTS.md" "work-item/v3" "work-item/v3 is the durable lifecycle contract"
assert_contains "plan-sync/SKILL.md" "canonical-v2" "plan-sync documents canonical-v2"
assert_contains "tests/run-all.sh" "tests/test_release_baseline.sh" "root verification runs the release baseline contract"
assert_contains "tests/run-all.sh" "tests/test_project_status.sh" "root verification runs project-status in private and public payloads"
assert_contains "qa/SKILL.md" "不得假設固定 fan-out 或 submodule mount" "QA commands define runtime path resolution"
assert_contains "security/SKILL.md" "不得假設固定 fan-out 或 submodule mount" "security commands define runtime path resolution"
assert_contains "verification-before-completion/SKILL.md" "不得假設固定 fan-out 或 submodule mount" "verification commands define runtime path resolution"
assert_no_hardcoded_runtime_mounts

assert_absent "plan-sync/scripts/init_plan.py" "retired init_plan command stays removed"
assert_absent "plan-sync/scripts/sync_tasks.py" "retired sync_tasks command stays removed"

for optional_skill in brainstorming grilling caveman-review shared-skill-onboarder; do
  assert_profile_omits "profiles/core" "$optional_skill" "core omits optional skill $optional_skill"
done

for deferred_path in \
  config-master/SKILL.md \
  page-composer/SKILL.md \
  prod-prototype-builder/SKILL.md \
  prototype-reviser/SKILL.md \
  profiles/prod-like-prototype; do
  assert_not_tracked "$deferred_path" "deferred release surface is not tracked: $deferred_path"
done

printf 'PASS=%s FAIL=%s\n' "$PASS" "$FAIL"
test "$FAIL" -eq 0
