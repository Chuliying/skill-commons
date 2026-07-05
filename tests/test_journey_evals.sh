#!/usr/bin/env bash
set -u
REPO="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
. "$REPO/tests/bootstrap/lib/assert.sh"

EXPECTED="brownfield-bug
commit-pr
personal-feature
refactor
team-feature"

actual="$(bash "$REPO/journey-evals/run.sh" --list 2>/dev/null | sort)"
assert_eq "$EXPECTED" "$actual" "journey runner exposes exactly five release journeys"
assert_not_contains "$(cat "$REPO/journey-evals/run.sh")" " -a never" "Codex runner uses supported non-interactive flags"
assert_contains "$(cat "$REPO/journey-evals/scripts/grade_journey.py")" '("prd-interview", "to-prd")' "team grader accepts either documented PRD producer"

for scenario in $EXPECTED; do
  prompt="$REPO/journey-evals/scenarios/$scenario/prompt.md"
  assert_file "$prompt" "$scenario has a repeatable agent prompt"
  if [ -f "$prompt" ]; then
    assert_contains "$(cat "$prompt")" "skill-router" "$scenario prompt requires router evidence"
    assert_contains "$(cat "$prompt")" "Skills read:" "$scenario prompt requires skill-read evidence"
    if [ "$scenario" = "commit-pr" ]; then
      assert_contains "$(cat "$prompt")" "Verification: PASS" "$scenario prompt requires verification evidence"
      assert_contains "$(cat "$prompt")" "Review: PASS" "$scenario prompt requires review evidence"
      assert_contains "$(cat "$prompt")" "Security: PASS" "$scenario prompt requires security evidence"
    fi
  fi

  workspace="$TMP/$scenario"
  if python3 "$REPO/journey-evals/scripts/setup_fixture.py" \
      --scenario "$scenario" --dest "$workspace" --skills-root "$REPO" >/dev/null; then
    TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: $scenario fixture setup succeeds"
  else
    fail "$scenario fixture setup succeeds"
    continue
  fi
  assert_file "$workspace/.agent/project-manifest.md" "$scenario has a manifest"
  assert_file "$workspace/.codex/skills/skill-router/SKILL.md" "$scenario has generated Codex skills"
  assert_file "$workspace/.claude/skills/skill-router/SKILL.md" "$scenario has generated Claude skills"
  assert_file "$workspace/.codex/skills/scripts/manifest-stack.sh" "$scenario has generated runtime helpers"

  set +e
  grade_output="$(python3 "$REPO/journey-evals/scripts/grade_journey.py" --scenario "$scenario" --workspace "$workspace" 2>&1)"
  grade_rc=$?
  set -e
  assert_neq "0" "$grade_rc" "$scenario unexecuted fixture fails grading"
  assert_contains "$grade_output" '"pass": false' "$scenario grader emits structured failure"
done

# A token mention is not behavior evidence: the grader must exercise the new API.
false_positive="$TMP/false-positive-personal"
python3 "$REPO/journey-evals/scripts/setup_fixture.py" \
  --scenario personal-feature --dest "$false_positive" --skills-root "$REPO" >/dev/null
mkdir -p "$false_positive/docs/work/personal-feature"
cat >> "$false_positive/src/greet.py" <<'EOF'
# punctuation is intentionally mentioned without implementing the requested API.
EOF
cat > "$false_positive/docs/work/personal-feature/implement-report.md" <<'EOF'
# Implement Report
Skills read: skill-router, implement
EOF
cat > "$false_positive/docs/work/personal-feature/meta.yml" <<'EOF'
slug: personal-feature
title: False positive fixture
created_at: 2026-07-04T00:00:00+08:00
updated_at: 2026-07-04T00:00:00+08:00
status: active
stages:
  implement: { skill: implement, file: implement-report.md, status: done }
inputs:
  - journey
EOF
if python3 "$REPO/journey-evals/scripts/grade_journey.py" \
    --scenario personal-feature --workspace "$false_positive" >/dev/null 2>&1; then
  fail "personal feature grader rejects token-only false positives"
else
  TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: personal feature grader rejects token-only false positives"
fi

skill_read_false_positive="$TMP/false-positive-skill-read"
python3 "$REPO/journey-evals/scripts/setup_fixture.py" \
  --scenario personal-feature --dest "$skill_read_false_positive" --skills-root "$REPO" >/dev/null
cat > "$skill_read_false_positive/src/greet.py" <<'EOF'
"""Minimal Python CLI fixture."""


def greet(name: str, punctuation: str = "") -> str:
    return f"hello {name}{punctuation}"
EOF
mkdir -p "$skill_read_false_positive/docs/work/personal-feature"
cat > "$skill_read_false_positive/docs/work/personal-feature/implement-report.md" <<'EOF'
# Implement Report
Skills read: skill-router

The implementation was specific and mentions implement in prose, but not on the
Skills read line.
EOF
cat > "$skill_read_false_positive/docs/work/personal-feature/meta.yml" <<'EOF'
slug: personal-feature
title: False positive skill-read fixture
created_at: 2026-07-04T00:00:00+08:00
updated_at: 2026-07-04T00:00:00+08:00
status: active
stages:
  implement: { skill: implement, file: implement-report.md, status: done }
inputs:
  - journey
EOF
if python3 "$REPO/journey-evals/scripts/grade_journey.py" \
    --scenario personal-feature --workspace "$skill_read_false_positive" >/dev/null 2>&1; then
  fail "personal feature grader requires skill names on Skills read line"
else
  TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: personal feature grader requires skill names on Skills read line"
fi

commit_pr_false_positive="$TMP/false-positive-commit-pr"
python3 "$REPO/journey-evals/scripts/setup_fixture.py" \
  --scenario commit-pr --dest "$commit_pr_false_positive" --skills-root "$REPO" >/dev/null
cat >> "$commit_pr_false_positive/docs/work/ship-ready/prd.md" <<'EOF'

## Delivery

- Date: 2026-07-04
- Deviation: 無
- QA: qa-report.md PASS
EOF
cat > "$commit_pr_false_positive/docs/work/ship-ready/implement-report.md" <<'EOF'
# Implement Report

PR: blocked (no remote)
Skills read: skill-router, verification-before-completion, caveman-review, security, finishing-a-development-branch
EOF
python3 - "$commit_pr_false_positive/docs/work/ship-ready/meta.yml" <<'PY'
from pathlib import Path
path = Path(__import__("sys").argv[1])
text = path.read_text()
path.write_text(text.replace("status: active", "status: shipped"))
PY
(cd "$commit_pr_false_positive" &&
  git add -A &&
  git -c "user.name=Journey Eval" -c "user.email=eval@example.com" commit -qm "fake release closeout")
if python3 "$REPO/journey-evals/scripts/grade_journey.py" \
    --scenario commit-pr --workspace "$commit_pr_false_positive" >/dev/null 2>&1; then
  fail "commit-pr grader requires verification review and security evidence"
else
  TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: commit-pr grader requires verification review and security evidence"
fi

commit_pr_green="$TMP/green-commit-pr"
python3 "$REPO/journey-evals/scripts/setup_fixture.py" \
  --scenario commit-pr --dest "$commit_pr_green" --skills-root "$REPO" >/dev/null
cat >> "$commit_pr_green/docs/work/ship-ready/prd.md" <<'EOF'

## Delivery

- Date: 2026-07-04
- Deviation: 無
- QA: qa-report.md PASS
EOF
cat > "$commit_pr_green/docs/work/ship-ready/implement-report.md" <<'EOF'
# Implement Report

- Verification: PASS (python3 -m unittest discover -s tests)
- Review: PASS (no findings)
- Security: PASS (scan-secrets)
- PR: blocked (no remote)
- Skills read: skill-router, verification-before-completion, caveman-review, security, finishing-a-development-branch
EOF
python3 - "$commit_pr_green/docs/work/ship-ready/meta.yml" <<'PY'
from pathlib import Path
path = Path(__import__("sys").argv[1])
text = path.read_text()
path.write_text(text.replace("status: active", "status: shipped"))
PY
(cd "$commit_pr_green" &&
  git add -A &&
  git -c "user.name=Journey Eval" -c "user.email=eval@example.com" commit -qm "verified release closeout")
if python3 "$REPO/journey-evals/scripts/grade_journey.py" \
    --scenario commit-pr --workspace "$commit_pr_green" >/dev/null 2>&1; then
  TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: commit-pr grader accepts bullet evidence records"
else
  fail "commit-pr grader accepts bullet evidence records"
fi

if bash "$REPO/journey-evals/run.sh" --harness codex --scenario personal-feature \
    --output "$TMP/dry-run" --dry-run >/dev/null; then
  TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: journey runner dry-run prepares an isolated workspace"
else
  fail "journey runner dry-run prepares an isolated workspace"
fi
assert_file "$TMP/dry-run/personal-feature/prompt.md" "dry-run captures the exact prompt"
assert_file "$TMP/dry-run/personal-feature/workspace/.git/HEAD" "dry-run workspace is an isolated git repository"
if (cd "$TMP/dry-run/personal-feature/workspace" &&
    bash .codex/skills/verification-before-completion/scripts/verify.sh >/dev/null &&
    bash .codex/skills/qa/scripts/run-qa.sh >/dev/null); then
  TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: generated verify and QA wrappers resolve shared runtime helpers"
else
  fail "generated verify and QA wrappers resolve shared runtime helpers"
fi

finish
