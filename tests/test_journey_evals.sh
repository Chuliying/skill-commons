#!/usr/bin/env bash
set -u
REPO="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
. "$REPO/tests/bootstrap/lib/assert.sh"

grade_commit_pr() {
  local workspace="$1" baseline_oid="$2"
  python3 "$REPO/journey-evals/scripts/grade_journey.py" \
    --scenario commit-pr --workspace "$workspace" --skills-root "$REPO" \
    --baseline-oid "$baseline_oid"
}

EXPECTED="brownfield-bug
commit-pr
personal-feature
refactor
team-feature"

actual="$(bash "$REPO/journey-evals/run.sh" --list 2>/dev/null | sort)"
assert_eq "$EXPECTED" "$actual" "journey runner exposes exactly five release journeys"
assert_not_contains "$(cat "$REPO/journey-evals/run.sh")" " -a never" "Codex runner uses supported non-interactive flags"
grader_source="$(cat "$REPO/journey-evals/scripts/grade_journey.py")"
setup_source="$(cat "$REPO/journey-evals/scripts/setup_fixture.py")"
assert_contains "$grader_source" '("prd-interview", "to-prd")' "team grader accepts either documented PRD producer"
assert_contains "$grader_source" '"sync-work"' "commit-pr grader requires the authoritative Git owner"
assert_contains "$setup_source" 'release: { skill: sync-work' "commit-pr fixture uses sync-work as release stage owner"
assert_contains "$grader_source" '"structural"' "grader classifies structural evidence"
assert_contains "$grader_source" '"behavioral"' "grader classifies executed behavioral evidence"
assert_contains "$grader_source" '"recorded"' "grader separates recorded attestations from machine evidence"
assert_contains "$grader_source" '"router_read_recorded"' "grader labels skill-read report text as recorded"
assert_not_contains "$grader_source" 'recorded["router_read"]' "grader does not name report text as observed reading"
assert_contains "$grader_source" '"presence_only_not_execution"' "grade output carries the recorded-evidence limitation"
assert_contains "$grader_source" 'args.skills_root' "grader resolves the scanner from a harness-owned skills root"
assert_not_contains "$grader_source" 'root / ".codex/skills/security/scripts/scan-secrets.sh"' "grader does not trust an agent-writable generated scanner"
assert_contains "$grader_source" 'scripts/work_items.py' "grader resolves the canonical work-item checker from the harness root"
assert_not_contains "$grader_source" '.codex/skills/scripts/work_items.py' "grader does not trust an agent-writable generated work-item checker"

security_skill="$(cat "$REPO/security/SKILL.md")"
security_scanner="$(cat "$REPO/security/scripts/scan-secrets.sh")"
assert_contains "$security_skill" "heuristic" "security skill labels secret scanning as heuristic"
assert_contains "$security_skill" "dependency audit" "security skill keeps dependency audit as a separate scope"
assert_contains "$security_skill" "auth" "security skill keeps auth review as a separate scope"
assert_not_contains "$security_skill" "Security: PASS" "security skill does not claim comprehensive security PASS"
assert_not_contains "$security_scanner" "PASS: secret scan passed" "secret scanner has no comprehensive PASS footer"
assert_contains "$security_scanner" "Secret preflight result:" "secret scanner reports a scoped preflight result"

for scenario in $EXPECTED; do
  prompt="$REPO/journey-evals/scenarios/$scenario/prompt.md"
  assert_file "$prompt" "$scenario has a repeatable agent prompt"
  if [ -f "$prompt" ]; then
    assert_contains "$(cat "$prompt")" "skill-router" "$scenario prompt requires router evidence"
    assert_contains "$(cat "$prompt")" "Skills read:" "$scenario prompt requires skill-read evidence"
    if [ "$scenario" = "commit-pr" ]; then
      assert_contains "$(cat "$prompt")" "Verification: PASS" "$scenario prompt requires verification evidence"
      assert_contains "$(cat "$prompt")" "Review attestation:" "$scenario prompt scopes manual review evidence"
      assert_contains "$(cat "$prompt")" "git diff <BASE_SHA>" "$scenario prompt ties review to the current change"
      assert_contains "$(cat "$prompt")" "Secret preflight command:" "$scenario prompt records the scoped scanner command"
      assert_contains "$(cat "$prompt")" "sync-work" "$scenario prompt dispatches the authoritative Git owner"
      assert_not_contains "$(cat "$prompt")" "Security: PASS" "$scenario prompt forbids prose-only security PASS"
      assert_contains "$(cat "$prompt")" "delivery_status: awaiting_approval" "$scenario prompt keeps blocked PR separate from delivery"
      assert_contains "$(cat "$prompt")" "Do not add" "$scenario prompt forbids fabricated delivery evidence"
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
  if [ "$scenario" = "refactor" ]; then
    assert_contains "$(cat "$workspace/.agent/project-manifest.md")" \
      "capability_packs: optional" "$scenario selects optional requirements capability"
    assert_file "$workspace/.codex/skills/to-prd/SKILL.md" "$scenario installs its recorded to-prd owner"
  elif [ "$scenario" = "commit-pr" ]; then
    assert_contains "$(cat "$workspace/.agent/project-manifest.md")" \
      "capability_packs: optional" "$scenario selects optional review capability"
    assert_file "$workspace/.codex/skills/caveman-review/SKILL.md" "$scenario installs its recorded review owner"
  fi

  set +e
  if [ "$scenario" = commit-pr ]; then
    fixture_baseline="$(git -C "$workspace" rev-parse HEAD)"
    grade_output="$(grade_commit_pr "$workspace" "$fixture_baseline" 2>&1)"
  else
    grade_output="$(python3 "$REPO/journey-evals/scripts/grade_journey.py" --scenario "$scenario" --workspace "$workspace" --skills-root "$REPO" 2>&1)"
  fi
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
    --scenario personal-feature --workspace "$false_positive" --skills-root "$REPO" >/dev/null 2>&1; then
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
    --scenario personal-feature --workspace "$skill_read_false_positive" --skills-root "$REPO" >/dev/null 2>&1; then
  fail "personal feature grader requires skill names on Skills read line"
else
  TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: personal feature grader requires skill names on Skills read line"
fi

commit_pr_false_positive="$TMP/false-positive-commit-pr"
python3 "$REPO/journey-evals/scripts/setup_fixture.py" \
  --scenario commit-pr --dest "$commit_pr_false_positive" --skills-root "$REPO" >/dev/null
false_positive_base="$(git -C "$commit_pr_false_positive" rev-parse HEAD)"
cat >> "$commit_pr_false_positive/docs/work/ship-ready/prd.md" <<'EOF'

## Delivery

- Date: 2026-07-04
- Deviation: 無
- QA: qa-report.md PASS
EOF
cat > "$commit_pr_false_positive/docs/work/ship-ready/implement-report.md" <<'EOF'
# Implement Report

PR: blocked (no remote)
Skills read: skill-router, verification-before-completion, caveman-review, security, sync-work
EOF
python3 - "$commit_pr_false_positive/docs/work/ship-ready/meta.yml" <<'PY'
from pathlib import Path
path = Path(__import__("sys").argv[1])
text = path.read_text()
text = text.replace("work_status: active", "work_status: completed")
text = text.replace("delivery_status: not_requested", "delivery_status: awaiting_approval")
text = text.replace("status: pending", "status: awaiting-approval")
path.write_text(text)
PY
(cd "$commit_pr_false_positive" &&
  git add -A &&
  git -c "user.name=Journey Eval" -c "user.email=eval@example.com" commit -qm "fake release closeout")
if grade_commit_pr "$commit_pr_false_positive" "$false_positive_base" >/dev/null 2>&1; then
  fail "commit-pr grader requires verification review and security evidence"
else
  TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: commit-pr grader requires verification review and security evidence"
fi

commit_pr_bare_prose="$TMP/bare-prose-commit-pr"
python3 "$REPO/journey-evals/scripts/setup_fixture.py" \
  --scenario commit-pr --dest "$commit_pr_bare_prose" --skills-root "$REPO" >/dev/null
bare_prose_base="$(git -C "$commit_pr_bare_prose" rev-parse HEAD)"
cat >> "$commit_pr_bare_prose/docs/work/ship-ready/prd.md" <<'EOF'

## Delivery

- Date: 2026-07-04
- Deviation: 無
- QA: qa-report.md PASS
EOF
cat > "$commit_pr_bare_prose/docs/work/ship-ready/implement-report.md" <<'EOF'
# Implement Report

- Verification: PASS (python3 -m unittest discover -s tests)
- Review: PASS
- Security: PASS
- PR: blocked (no remote)
- Skills read: skill-router, verification-before-completion, caveman-review, security, sync-work
EOF
python3 - "$commit_pr_bare_prose/docs/work/ship-ready/meta.yml" <<'PY'
from pathlib import Path
path = Path(__import__("sys").argv[1])
text = path.read_text()
text = text.replace("work_status: active", "work_status: completed")
text = text.replace("delivery_status: not_requested", "delivery_status: awaiting_approval")
text = text.replace("status: pending", "status: awaiting-approval")
path.write_text(text)
PY
(cd "$commit_pr_bare_prose" &&
  git add -A &&
  git -c "user.name=Journey Eval" -c "user.email=eval@example.com" commit -qm "bare prose closeout")
set +e
bare_prose_output="$(grade_commit_pr "$commit_pr_bare_prose" "$bare_prose_base" 2>&1)"
bare_prose_rc=$?
set -e
assert_neq "0" "$bare_prose_rc" "commit-pr grader rejects bare review/security PASS prose"
assert_contains "$bare_prose_output" '"secret_preflight_pass": true' "bare-prose fixture still runs the real secret preflight"
assert_contains "$bare_prose_output" '"scoped_review_attestation_recorded": false' "bare review PASS is not a scoped attestation"
assert_contains "$bare_prose_output" '"secret_preflight_command_recorded": false' "bare security PASS is not scanner evidence"

commit_pr_fake_delivery="$TMP/fake-delivery-commit-pr"
python3 "$REPO/journey-evals/scripts/setup_fixture.py" \
  --scenario commit-pr --dest "$commit_pr_fake_delivery" --skills-root "$REPO" >/dev/null
fake_delivery_base="$(git -C "$commit_pr_fake_delivery" rev-parse HEAD)"
cat >> "$commit_pr_fake_delivery/docs/work/ship-ready/prd.md" <<'EOF'

## Delivery

- Date: 2026-07-04
- Deviation: 無
- QA: qa-report.md PASS
EOF
cat > "$commit_pr_fake_delivery/docs/work/ship-ready/implement-report.md" <<'EOF'
# Implement Report

- Verification: PASS (python3 -m unittest discover -s tests)
- Review: PASS (no findings)
- Security: PASS (scan-secrets)
- PR: blocked (no remote)
- Skills read: skill-router, verification-before-completion, caveman-review, security, sync-work
EOF
python3 - "$commit_pr_fake_delivery/docs/work/ship-ready/meta.yml" <<'PY'
from pathlib import Path
path = Path(__import__("sys").argv[1])
text = path.read_text()
text = text.replace("work_status: active", "work_status: completed")
text = text.replace("delivery_status: not_requested", "delivery_status: pr_created")
text = text.replace("status: pending", "status: done")
text = text.replace(
    "stages:\n",
    "delivery_evidence:\n"
    "  approval_ref: user:imagined-approval\n"
    "  pr_url: https://example.test/pull/imagined\n"
    "stages:\n",
)
path.write_text(text)
PY
(cd "$commit_pr_fake_delivery" &&
  git add -A &&
  git -c "user.name=Journey Eval" -c "user.email=eval@example.com" commit -qm "fabricate delivery")
set +e
fake_delivery_output="$(grade_commit_pr "$commit_pr_fake_delivery" "$fake_delivery_base" 2>&1)"
fake_delivery_rc=$?
set -e
assert_neq "0" "$fake_delivery_rc" "commit-pr grader rejects PR evidence when no PR can exist"
assert_contains "$fake_delivery_output" '"delivery_awaits_approval": false' "commit-pr grader checks structured delivery state"
assert_contains "$fake_delivery_output" '"no_fabricated_delivery_evidence": false' "commit-pr grader checks absence of fabricated evidence"

commit_pr_secret_leak="$TMP/secret-leak-commit-pr"
python3 "$REPO/journey-evals/scripts/setup_fixture.py" \
  --scenario commit-pr --dest "$commit_pr_secret_leak" --skills-root "$REPO" >/dev/null
cat >> "$commit_pr_secret_leak/docs/work/ship-ready/prd.md" <<'EOF'

## Delivery

- Date: 2026-07-04
- Deviation: 無
- QA: qa-report.md PASS
EOF
secret_leak_base="$(git -C "$commit_pr_secret_leak" rev-parse HEAD)"
cat > "$commit_pr_secret_leak/docs/work/ship-ready/implement-report.md" <<EOF
# Implement Report

- Verification: PASS (python3 -m unittest discover -s tests)
- Review attestation: no findings; scope: git diff $secret_leak_base; reviewer: agent
- Secret preflight command: bash .codex/skills/security/scripts/scan-secrets.sh
- PR: blocked (no remote)
- Skills read: skill-router, verification-before-completion, caveman-review, security, sync-work
EOF
printf '\n%s = "%s"\n' api_key production-secret-value >> "$commit_pr_secret_leak/src/greet.py"
cat > "$commit_pr_secret_leak/.codex/skills/security/scripts/scan-secrets.sh" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$commit_pr_secret_leak/.codex/skills/security/scripts/scan-secrets.sh"
python3 - "$commit_pr_secret_leak/docs/work/ship-ready/meta.yml" <<'PY'
from pathlib import Path
path = Path(__import__("sys").argv[1])
text = path.read_text()
text = text.replace("work_status: active", "work_status: completed")
text = text.replace("delivery_status: not_requested", "delivery_status: awaiting_approval")
text = text.replace("status: pending", "status: awaiting-approval")
path.write_text(text)
PY
(cd "$commit_pr_secret_leak" &&
  git add -A &&
  git -c "user.name=Journey Eval" -c "user.email=eval@example.com" commit -qm "closeout with leaked secret")
if (cd "$commit_pr_secret_leak" && bash .codex/skills/security/scripts/scan-secrets.sh); then
  TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: tampered generated scanner masks the fixture leak"
else
  fail "tampered generated scanner masks the fixture leak"
fi
set +e
secret_leak_output="$(grade_commit_pr "$commit_pr_secret_leak" "$secret_leak_base" 2>&1)"
secret_leak_rc=$?
set -e
assert_neq "0" "$secret_leak_rc" "commit-pr grader rejects a real secret despite recorded prose"
assert_contains "$secret_leak_output" '"secret_preflight_pass": false' "grader executes the harness-owned scanner despite generated scanner tampering"
assert_contains "$secret_leak_output" '"secret_preflight_command_recorded": true' "scanner command record remains separate from its result"

cat > "$TMP/untrusted-project-manifest.md" <<'EOF'
# Untrusted manifest supplied by the caller
## Paths
- source_roots: tests
- source_extensions: py
EOF
set +e
inherited_manifest_output="$(PROJECT_MANIFEST="$TMP/untrusted-project-manifest.md" \
  grade_commit_pr "$commit_pr_secret_leak" "$secret_leak_base" 2>&1)"
inherited_manifest_rc=$?
set -e
assert_neq "0" "$inherited_manifest_rc" "grader ignores an inherited manifest that narrows secret scope"
assert_contains "$inherited_manifest_output" '"secret_preflight_pass": false' "harness binds secret scan to the trusted fixture manifest"

commit_pr_green="$TMP/green-commit-pr"
python3 "$REPO/journey-evals/scripts/setup_fixture.py" \
  --scenario commit-pr --dest "$commit_pr_green" --skills-root "$REPO" >/dev/null
cat >> "$commit_pr_green/docs/work/ship-ready/prd.md" <<'EOF'

## Delivery

- Date: 2026-07-04
- Deviation: 無
- QA: qa-report.md PASS
EOF
green_base="$(git -C "$commit_pr_green" rev-parse HEAD)"
cat > "$commit_pr_green/docs/work/ship-ready/implement-report.md" <<EOF
# Implement Report

- Verification: PASS (python3 -m unittest discover -s tests)
- Review attestation: no findings; scope: git diff $green_base; reviewer: agent
- Secret preflight command: bash .codex/skills/security/scripts/scan-secrets.sh
- PR: blocked (no remote)
- Skills read: skill-router, verification-before-completion, caveman-review, security, sync-work
EOF
python3 - "$commit_pr_green/docs/work/ship-ready/meta.yml" <<'PY'
from pathlib import Path
path = Path(__import__("sys").argv[1])
text = path.read_text()
text = text.replace("work_status: active", "work_status: completed")
text = text.replace("delivery_status: not_requested", "delivery_status: awaiting_approval")
text = text.replace("status: pending", "status: awaiting-approval")
path.write_text(text)
PY
(cd "$commit_pr_green" &&
  git add -A &&
  git -c "user.name=Journey Eval" -c "user.email=eval@example.com" commit -qm "verified release closeout")
set +e
green_output="$(grade_commit_pr "$commit_pr_green" "$green_base" 2>&1)"
green_rc=$?
set -e
if [ "$green_rc" -eq 0 ]; then
  TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: commit-pr grader accepts scoped records plus executed gates"
else
  fail "commit-pr grader accepts scoped records plus executed gates"
fi
assert_contains "$green_output" '"structural": {' "grade output separates structural evidence"
assert_contains "$green_output" '"behavioral": {' "grade output separates behavioral evidence"
assert_contains "$green_output" '"recorded": {' "grade output labels report attestations as recorded"
assert_contains "$green_output" '"secret_preflight_pass": true' "green journey passes the executed secret preflight"
assert_contains "$green_output" '"scoped_review_attestation_recorded": true' "green review record is tied to the parent change"
assert_contains "$green_output" '"head_commit_non_empty": true' "green journey HEAD contains closeout changes"
assert_contains "$green_output" '"worktree_clean": true' "green journey leaves no uncommitted artifacts"
assert_contains "$green_output" '"work_item_contract_valid": true' "green journey passes the canonical work-item contract"
assert_contains "$green_output" '"required_artifacts_regular_files": true' "green journey uses regular closeout files"
assert_contains "$green_output" '"required_head_entries_regular_blobs": true' "green journey records closeout files as regular Git blobs"
assert_contains "$green_output" '"head_parent_is_trusted_baseline": true' "green journey is based on the harness-recorded baseline"
assert_contains "$green_output" '"trusted_manifest_unchanged": true' "green journey keeps the harness manifest unchanged from baseline"

commit_pr_manifest_drift="$TMP/manifest-drift-commit-pr"
cp -R "$commit_pr_green" "$commit_pr_manifest_drift"
python3 - "$commit_pr_manifest_drift/.agent/project-manifest.md" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
path.write_text(path.read_text().replace("- source_roots: src", "- source_roots: tests"))
PY
printf '\n%s = "%s"\n' api_key production-secret-value >> "$commit_pr_manifest_drift/src/greet.py"
(
  cd "$commit_pr_manifest_drift" || exit 1
  git add -A
  git -c "user.name=Journey Eval" -c "user.email=eval@example.com" commit --amend -qm "closeout with manifest drift"
)
set +e
manifest_drift_output="$(grade_commit_pr "$commit_pr_manifest_drift" "$green_base" 2>&1)"
manifest_drift_rc=$?
set -e
assert_neq "0" "$manifest_drift_rc" "commit-pr grader rejects manifest drift from the trusted baseline"
assert_contains "$manifest_drift_output" '"trusted_manifest_unchanged": false' "manifest drift cannot redefine the harness scan scope"
assert_contains "$manifest_drift_output" '"secret_preflight_pass": false' "untrusted manifest prevents a behavioral secret PASS"

commit_pr_rewritten_history="$TMP/rewritten-history-commit-pr"
cp -R "$commit_pr_green" "$commit_pr_rewritten_history"
(
  cd "$commit_pr_rewritten_history" || exit 1
  git checkout --orphan replacement-baseline -q
  git rm -r --cached . >/dev/null 2>&1 || true
  git add -A
  git -c "user.name=Journey Eval" -c "user.email=eval@example.com" commit -qm "replacement baseline"
)
replacement_base="$(git -C "$commit_pr_rewritten_history" rev-parse HEAD)"
python3 - "$commit_pr_rewritten_history/docs/work/ship-ready/implement-report.md" "$green_base" "$replacement_base" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
path.write_text(path.read_text().replace(sys.argv[2], sys.argv[3]) + "\nRewritten history marker.\n")
PY
(
  cd "$commit_pr_rewritten_history" || exit 1
  git add docs/work/ship-ready/implement-report.md
  git -c "user.name=Journey Eval" -c "user.email=eval@example.com" commit -qm "replacement closeout"
)
set +e
rewritten_history_output="$(grade_commit_pr "$commit_pr_rewritten_history" "$green_base" 2>&1)"
rewritten_history_rc=$?
set -e
assert_neq "0" "$rewritten_history_rc" "commit-pr grader rejects rewritten baseline history"
assert_contains "$rewritten_history_output" '"exactly_one_local_commit": true' "rewritten history fixture isolates baseline trust from commit count"
assert_contains "$rewritten_history_output" '"head_parent_is_trusted_baseline": false' "rewritten parent cannot replace the harness baseline"
assert_contains "$rewritten_history_output" '"scoped_review_attestation_recorded": false' "review scope remains bound to the trusted baseline"

commit_pr_duplicate_meta="$TMP/duplicate-metadata-commit-pr"
python3 "$REPO/journey-evals/scripts/setup_fixture.py" \
  --scenario commit-pr --dest "$commit_pr_duplicate_meta" --skills-root "$REPO" >/dev/null
cat >> "$commit_pr_duplicate_meta/docs/work/ship-ready/prd.md" <<'EOF'

## Delivery

- Date: 2026-07-04
- Deviation: 無
- QA: qa-report.md PASS
EOF
duplicate_meta_base="$(git -C "$commit_pr_duplicate_meta" rev-parse HEAD)"
cat > "$commit_pr_duplicate_meta/docs/work/ship-ready/implement-report.md" <<EOF
# Implement Report

- Verification: PASS (python3 -m unittest discover -s tests)
- Review attestation: no findings; scope: git diff $duplicate_meta_base; reviewer: agent
- Secret preflight command: bash .codex/skills/security/scripts/scan-secrets.sh
- PR: blocked (no remote)
- Skills read: skill-router, verification-before-completion, caveman-review, security, sync-work
EOF
python3 - "$commit_pr_duplicate_meta/docs/work/ship-ready/meta.yml" <<'PY'
from pathlib import Path
path = Path(__import__("sys").argv[1])
text = path.read_text()
text = text.replace("work_status: active", "work_status: completed")
text = text.replace("delivery_status: not_requested", "delivery_status: awaiting_approval")
text = text.replace("status: pending", "status: awaiting-approval")
path.write_text(text + "work_status: active\ndelivery_status: pr_created\n")
PY
(cd "$commit_pr_duplicate_meta" &&
  git add -A &&
  git -c "user.name=Journey Eval" -c "user.email=eval@example.com" commit -qm "duplicate metadata closeout")
set +e
duplicate_meta_output="$(grade_commit_pr "$commit_pr_duplicate_meta" "$duplicate_meta_base" 2>&1)"
duplicate_meta_rc=$?
set -e
assert_neq "0" "$duplicate_meta_rc" "commit-pr grader rejects duplicate conflicting work and delivery metadata"
assert_contains "$duplicate_meta_output" '"exactly_one_local_commit": true' "duplicate metadata fixture isolates metadata trust from commit count"
assert_contains "$duplicate_meta_output" '"work_item_contract_valid": false' "canonical checker exposes duplicate metadata failure"

commit_pr_noncanonical_meta="$TMP/noncanonical-metadata-commit-pr"
cp -R "$commit_pr_green" "$commit_pr_noncanonical_meta"
python3 - "$commit_pr_noncanonical_meta/docs/work/ship-ready/meta.yml" <<'PY'
from pathlib import Path
path = Path(__import__("sys").argv[1])
text = path.read_text()
text = text.replace("inputs:\n", "inputs: bogus-scalar\n")
path.write_text(text + "alternate_delivery_truth: pr_created\n")
PY
(cd "$commit_pr_noncanonical_meta" &&
  git add docs/work/ship-ready/meta.yml &&
  git -c "user.name=Journey Eval" -c "user.email=eval@example.com" commit --amend --no-edit -q)
set +e
noncanonical_meta_output="$(grade_commit_pr "$commit_pr_noncanonical_meta" "$green_base" 2>&1)"
noncanonical_meta_rc=$?
set -e
assert_neq "0" "$noncanonical_meta_rc" "commit-pr grader rejects unknown top-level and scalar-container metadata"
assert_contains "$noncanonical_meta_output" '"exactly_one_local_commit": true' "noncanonical metadata fixture isolates metadata trust from commit count"
assert_contains "$noncanonical_meta_output" '"work_item_contract_valid": false' "canonical checker exposes noncanonical metadata shape"

commit_pr_symlinked_artifacts="$TMP/symlinked-artifacts-commit-pr"
python3 "$REPO/journey-evals/scripts/setup_fixture.py" \
  --scenario commit-pr --dest "$commit_pr_symlinked_artifacts" --skills-root "$REPO" >/dev/null
cat >> "$commit_pr_symlinked_artifacts/docs/work/ship-ready/prd.md" <<'EOF'

## Delivery

- Date: 2026-07-04
- Deviation: 無
- QA: qa-report.md PASS
EOF
symlink_base="$(git -C "$commit_pr_symlinked_artifacts" rev-parse HEAD)"
cat > "$commit_pr_symlinked_artifacts/docs/work/ship-ready/implement-report.md" <<EOF
# Implement Report

- Verification: PASS (python3 -m unittest discover -s tests)
- Review attestation: no findings; scope: git diff $symlink_base; reviewer: agent
- Secret preflight command: bash .codex/skills/security/scripts/scan-secrets.sh
- PR: blocked (no remote)
- Skills read: skill-router, verification-before-completion, caveman-review, security, sync-work
EOF
python3 - "$commit_pr_symlinked_artifacts/docs/work/ship-ready/meta.yml" <<'PY'
from pathlib import Path
path = Path(__import__("sys").argv[1])
text = path.read_text()
text = text.replace("work_status: active", "work_status: completed")
text = text.replace("delivery_status: not_requested", "delivery_status: awaiting_approval")
text = text.replace("status: pending", "status: awaiting-approval")
path.write_text(text)
PY
mkdir -p "$commit_pr_symlinked_artifacts/docs/work/ship-ready/.payload"
for name in prd.md implement-report.md meta.yml; do
  mv "$commit_pr_symlinked_artifacts/docs/work/ship-ready/$name" \
    "$commit_pr_symlinked_artifacts/docs/work/ship-ready/.payload/$name"
  ln -s ".payload/$name" "$commit_pr_symlinked_artifacts/docs/work/ship-ready/$name"
done
(cd "$commit_pr_symlinked_artifacts" &&
  git add -A &&
  git -c "user.name=Journey Eval" -c "user.email=eval@example.com" commit -qm "symlinked artifact closeout")
set +e
symlink_output="$(grade_commit_pr "$commit_pr_symlinked_artifacts" "$symlink_base" 2>&1)"
symlink_rc=$?
set -e
assert_neq "0" "$symlink_rc" "commit-pr grader rejects symlinked required closeout artifacts"
assert_contains "$symlink_output" '"exactly_one_local_commit": true' "symlink fixture isolates artifact trust from commit count"
assert_contains "$symlink_output" '"required_artifacts_regular_files": false' "working-tree symlinks are visible in structural evidence"
assert_contains "$symlink_output" '"required_head_entries_regular_blobs": false' "Git mode 120000 entries are rejected"

commit_pr_extra_commit="$TMP/extra-commit-commit-pr"
cp -R "$commit_pr_green" "$commit_pr_extra_commit"
extra_commit_base="$(git -C "$commit_pr_extra_commit" rev-parse HEAD)"
python3 - "$commit_pr_extra_commit/docs/work/ship-ready/implement-report.md" "$green_base" "$extra_commit_base" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
path.write_text(path.read_text().replace(sys.argv[2], sys.argv[3]))
PY
printf 'unrelated post-closeout change\n' > "$commit_pr_extra_commit/unrelated.txt"
(cd "$commit_pr_extra_commit" &&
  git add -A &&
  git -c "user.name=Journey Eval" -c "user.email=eval@example.com" commit -qm "unrelated post-closeout commit")
set +e
extra_commit_output="$(grade_commit_pr "$commit_pr_extra_commit" "$green_base" 2>&1)"
extra_commit_rc=$?
set -e
assert_neq "0" "$extra_commit_rc" "commit-pr grader rejects more than one closeout commit"
assert_contains "$extra_commit_output" '"exactly_one_local_commit": false' "extra commit is visible in structured evidence"
assert_contains "$extra_commit_output" '"scoped_review_attestation_recorded": false' "extra commit cannot narrow review away from the trusted baseline"

commit_pr_empty_head="$TMP/empty-head-commit-pr"
cp -R "$commit_pr_green" "$commit_pr_empty_head"
git -C "$commit_pr_empty_head" -c "user.name=Journey Eval" -c "user.email=eval@example.com" \
  commit --allow-empty -qm "empty closeout marker"
set +e
empty_head_output="$(grade_commit_pr "$commit_pr_empty_head" "$green_base" 2>&1)"
empty_head_rc=$?
set -e
assert_neq "0" "$empty_head_rc" "commit-pr grader rejects an empty HEAD closeout commit"
assert_contains "$empty_head_output" '"head_commit_non_empty": false' "empty HEAD is visible in structured evidence"

commit_pr_dirty="$TMP/dirty-commit-pr"
cp -R "$commit_pr_green" "$commit_pr_dirty"
printf 'uncommitted closeout artifact\n' > "$commit_pr_dirty/uncommitted.txt"
set +e
dirty_output="$(grade_commit_pr "$commit_pr_dirty" "$green_base" 2>&1)"
dirty_rc=$?
set -e
assert_neq "0" "$dirty_rc" "commit-pr grader rejects uncommitted closeout artifacts"
assert_contains "$dirty_output" '"worktree_clean": false' "dirty workspace is visible in structured evidence"

in_repo_output="$REPO/journey-evals/runs/rejected-output-$$"
set +e
in_repo_output_text="$(bash "$REPO/journey-evals/run.sh" --harness codex --scenario personal-feature \
  --output "$in_repo_output" --dry-run 2>&1)"
in_repo_output_rc=$?
set -e
assert_neq "0" "$in_repo_output_rc" "journey runner rejects an output inside the source repository"
assert_contains "$in_repo_output_text" "outside the source repository" "in-repo output rejection is actionable"
if [ ! -e "$in_repo_output" ]; then
  TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: in-repo output is rejected before directory creation"
else
  fail "in-repo output is rejected before directory creation"
  rm -rf "$in_repo_output"
fi

default_run_root="$TMP/default-runs"
if SKILL_COMMONS_JOURNEY_ROOT="$default_run_root" \
    bash "$REPO/journey-evals/run.sh" --harness codex --scenario personal-feature --dry-run >/dev/null; then
  default_outputs=("$default_run_root"/*-codex-fable)
  assert_file "${default_outputs[0]}/personal-feature/workspace/.git/HEAD" "default journey root stays outside the source repository"
else
  fail "default journey root stays outside the source repository"
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
    bash .codex/skills/verification-before-completion/scripts/verify.sh >/dev/null); then
  TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: generated personal verification wrapper resolves shared runtime helpers"
else
  fail "generated personal verification wrapper resolves shared runtime helpers"
fi
if [ ! -e "$TMP/dry-run/personal-feature/workspace/.codex/skills/qa" ]; then
  TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: personal dry-run does not invent QA capability"
else
  fail "personal dry-run does not invent QA capability"
fi
if (cd "$TMP/team-feature" &&
    bash .codex/skills/qa/scripts/run-qa.sh >/dev/null); then
  TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: generated team QA wrapper resolves shared runtime helpers"
else
  fail "generated team QA wrapper resolves shared runtime helpers"
fi

finish
