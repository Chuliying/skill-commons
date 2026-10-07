#!/usr/bin/env bash
set -u
REPO="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
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
  TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: core profile is the released v0.10.0 seven-owner set"
else
  fail "core profile is the released v0.10.0 seven-owner set"
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
contributing_text="$(cat "$REPO/CONTRIBUTING.md")"
artifacts_text="$(cat "$REPO/ARTIFACTS.md")"
gitattributes_text="$(cat "$REPO/.gitattributes")"
export_script_text="$(cat "$REPO/scripts/export-public.sh")"

assert_contains "$readme_text" "delivery_mode: personal" "README shows an explicit delivery mode before onboarding"
assert_contains "$readme_text" "capability_packs:" "README documents composable capability packs"
for entrypoint_text in "$readme_text" "$readme_en_text"; do
  assert_contains "$entrypoint_text" ".agent/skills/_shared/scripts/project-status.sh" "README documents the v0.9.0 project-status entry"
  assert_contains "$entrypoint_text" "--json" "README documents project-status machine output"
done
assert_contains "$changelog_text" "## [Unreleased]" "changelog keeps an Unreleased section after the release cut"
assert_contains "$contributing_text" 'prerelease' "release checklist distinguishes prerelease tags"
assert_contains "$contributing_text" 'final release' "release checklist distinguishes the final version cut"
assert_contains "$contributing_text" 'git status --short' "release checklist requires a clean candidate tree"
assert_contains "$contributing_text" 'git grep -n' "release checklist discovers version pins instead of trusting a hand count"
assert_not_contains "$contributing_text" '目前散在五處' "release checklist does not preserve a stale version-pin count"
assert_contains "$contributing_text" '0.x' "release checklist defines the pre-1.0 breaking-change convention"
assert_contains "$artifacts_text" 'metadata and planning documents' "legacy migration names both metadata and planning-document work"
assert_contains "$gitattributes_text" "/website/** export-ignore" "archive attributes exclude the nested website"
assert_contains "$gitattributes_text" "**/.env export-ignore" "archive attributes exclude .env files"
assert_contains "$gitattributes_text" "**/.env.* export-ignore" "archive attributes exclude environment variants"
assert_contains "$gitattributes_text" "**/.env.example -export-ignore" "archive attributes retain synthetic env examples"
assert_contains "$export_script_text" '"website"' "public export forbidden list rejects the website"
assert_contains "$export_script_text" "public export contains environment file" "public export rejects environment files after extraction"

# T05 public product boundary: derive every Python test that imports an excluded
# runtime package from the source AST, then require exactly that set (plus the
# existing private corpus roster) to be export-ignored. The attributes remain
# the sole declaration of the boundary; this test only checks their behavior.
dependent_tests="$(python3 - "$REPO" <<'PY'
import ast
import sys
from pathlib import Path

root = Path(sys.argv[1])
excluded = {"foundation", "orchestration", "productscope"}
for path in sorted((root / "tests" / "py").rglob("test_*.py")):
    tree = ast.parse(path.read_text(encoding="utf-8"), filename=str(path))
    imported = set()
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            imported.update(alias.name.split(".", 1)[0] for alias in node.names)
        elif isinstance(node, ast.ImportFrom) and node.module:
            imported.add(node.module.split(".", 1)[0])
    if imported & excluded:
        print(path.relative_to(root).as_posix())
PY
)"
dependent_count="$(printf '%s\n' "$dependent_tests" | sed '/^$/d' | wc -l | tr -d ' ')"
expected_dependent_count=0
if [ -e "$REPO/foundation" ] || [ -L "$REPO/foundation" ] ||
   [ -e "$REPO/orchestration" ] || [ -L "$REPO/orchestration" ] ||
   [ -e "$REPO/productscope" ] || [ -L "$REPO/productscope" ]; then
  expected_dependent_count=22
fi
assert_eq "$expected_dependent_count" "$dependent_count" "AST derives the source's 22 excluded-package dependent tests"
private_tests="$(
  {
    printf '%s\n' "$dependent_tests"
    if [ -f "$REPO/tests/py/integration/test_corpus_completeness.py" ]; then
      printf '%s\n' "tests/py/integration/test_corpus_completeness.py"
    fi
  } | sed '/^$/d' | sort
)"
actual_private_tests="$(
  while IFS= read -r test_path; do
    [ -n "$test_path" ] || continue
    attr="$(git -C "$REPO" check-attr export-ignore -- "$test_path" | awk -F': ' '{print $NF}')"
    [ "$attr" = "set" ] && printf '%s\n' "$test_path"
  done < <(cd "$REPO" && find tests/py -type f -name 'test_*.py' -print)
)"
actual_private_tests="$(printf '%s\n' "$actual_private_tests" | sed '/^$/d' | sort)"
assert_eq "$private_tests" "$actual_private_tests" "only AST dependents and corpus completeness are private Python tests"
for package in foundation orchestration productscope; do
  if [ -e "$REPO/$package/__init__.py" ] || [ -L "$REPO/$package/__init__.py" ]; then
    package_attr="$(git -C "$REPO" check-attr export-ignore -- "$package/__init__.py" | awk -F': ' '{print $NF}')"
    assert_eq "set" "$package_attr" "$package is export-ignored by attributes"
  else
    TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: $package is absent from the public source tree"
  fi
done

validate_public_payload() {
  payload="$1"
  for forbidden in foundation orchestration productscope; do
    if [ -e "$payload/$forbidden" ] || [ -L "$payload/$forbidden" ]; then
      return 1
    fi
  done
  while IFS= read -r test_path; do
    [ -n "$test_path" ] || continue
    if [ -e "$payload/$test_path" ] || [ -L "$payload/$test_path" ]; then
      return 1
    fi
  done <<EOF
$private_tests
EOF
  for layer in unit integration e2e; do
    count="$(find "$payload/tests/py/$layer" -type f -name 'test_*.py' -print | wc -l | tr -d ' ')"
    [ "$count" -gt 0 ] || return 1
  done
}

public_payload="$TMP/public-payload"
bash "$REPO/scripts/export-public.sh" "$public_payload" --force --include-worktree \
  >"$TMP/export.stdout" 2>"$TMP/export.stderr"
export_rc=$?
assert_eq "0" "$export_rc" "current worktree exports a temporary public payload"
if [ "$export_rc" -eq 0 ]; then
  validate_public_payload "$public_payload"
  payload_rc=$?
  assert_eq "0" "$payload_rc" "public payload excludes private roots/tests and keeps all Python layers"

  mkdir -p "$public_payload/foundation"
  printf 'forbidden fixture\n' > "$public_payload/foundation/fixture.py"
  validate_public_payload "$public_payload"
  forbidden_rc=$?
  assert_neq "0" "$forbidden_rc" "the same public-payload validator rejects a reintroduced forbidden root"
fi

for stale_version in "v0.5.0" "v0.6.0" "v0.8.0" "v0.9.0"; do
  assert_not_contains "$readme_text" "$stale_version" "README has no stale $stale_version pin"
  assert_not_contains "$readme_en_text" "$stale_version" "English summary has no stale $stale_version pin"
  assert_not_contains "$bridge_text" "$stale_version" "submodule bridge has no stale $stale_version pin"
done

# Owner-approved 2026-07-30 entry structure: scope, capabilities (how -> canonical
# docs), verification, onboarding, references. This suite is the single owner of
# the README entry-section contract (presence and order, both languages);
# tests/test_skills_reorg.sh deliberately carries no copy.
for heading in \
  "## 專案範疇" \
  "## 專案能力" \
  "## 驗收" \
  "## Quick Start" \
  "## 安裝完成後" \
  "## References"; do
  assert_contains "$readme_text" "$heading" "README keeps minimum entry section: $heading"
done
if python3 - "$REPO/README.md" "$REPO/README.en.md" <<'PY'
from pathlib import Path
import re
import sys

expected = {
    sys.argv[1]: ("## 專案範疇", "## 專案能力", "## 驗收",
                  "## Quick Start", "## 安裝完成後", "## References"),
    sys.argv[2]: ("## Scope", "## Capabilities", "## Verification",
                  "## Quick Start", "## After installation", "## References"),
}

def h2_headings(text):
    headings = []
    fence = None
    for raw in text.splitlines():
        marker = re.match(r"^\s*(`{3,}|~{3,})(.*)$", raw)
        if marker:
            run = marker.group(1)
            kind = run[0]
            if fence is None:
                fence = (kind, len(run))
            elif (
                fence[0] == kind
                and len(run) >= fence[1]
                and not marker.group(2).strip()
            ):
                fence = None
            continue
        line = raw.rstrip()
        if fence is None and line.startswith("## ") and not line.startswith("### "):
            headings.append(line)
    return headings

def required_order(text, sections):
    headings = h2_headings(text)
    positions = [headings.index(section) if section in headings else -1 for section in sections]
    return positions, all(position >= 0 for position in positions) and positions == sorted(positions)

for name, sections in expected.items():
    text = Path(name).read_text(errors="replace")
    positions, valid = required_order(text, sections)
    if not valid:
        raise SystemExit(f"{name}: entry sections out of order: {list(zip(sections, positions))}")
    mutated = text.replace(sections[0], f"{sections[0]} details", 1)
    _, mutation_valid = required_order(mutated, sections)
    if mutation_valid:
        raise SystemExit(f"{name}: renamed heading still satisfies the exact H2 contract")
    fenced_mutation = f"````text\n```\n{sections[0]}\n```\n````\n{mutated}"
    _, fenced_mutation_valid = required_order(fenced_mutation, sections)
    if fenced_mutation_valid:
        raise SystemExit(f"{name}: heading inside a longer fenced block satisfies the H2 contract")
PY
then
  TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: entry sections follow the owner-approved order in both READMEs"
else
  fail "entry sections follow the owner-approved order in both READMEs"
fi

for core_narrative in \
  "可驗證、可接續" \
  "Spec 是施工圖" \
  "fresh verification evidence" \
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
assert_contains "$evaluation_text" "unverified narrative" "evaluation keeps historical model-run figures labelled as unverified"

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
  "## Scope" \
  "## Capabilities" \
  "## Verification" \
  "## Quick Start" \
  "## After installation" \
  "## References"; do
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
        section.find("checkout v0.12.0"),
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
assert_contains "$prototype_text" "click walkthrough" "prototype G6 leaves human judgment to click walkthrough"
assert_not_contains "$prototype_text" "G5 Stage 1" "prototype folds G5 confirmation into G4"

assert_not_contains "$(cat "$REPO/spec/SKILL.md")" "Gate 0" "Spec preflight is folded into Gate 2"
assert_contains "$(cat "$REPO/README.md")" "PRD 核可、team 設計核可、發布核可" "README names exactly three workflow human gates"
readme_en_flat="$(tr '\n' ' ' < "$REPO/README.en.md")"
assert_contains "$readme_en_flat" "PRD approval, team design approval, and release approval" "English README names exactly three workflow human gates"
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
    Path("tests/test_skills_reorg.sh"),
}
# The check guards the ACTIVE surface: skills, profiles, generated roots and the docs
# a consumer reads. Private development history is not part of it and legitimately
# names the retired owner when recording what happened -- erasing the name there would
# falsify the record. The boundary is not a hand-kept list of work items: docs/work/**
# and docs/STATUS.md are export-ignored in .gitattributes, so they are by definition
# absent from any public payload.
allowed_prefixes = (
    Path(".claude/worktrees"),
    Path("_archive"),
    Path("journey-evals/runs"),
    Path("docs/skills-reorg"),
    Path("docs/superpowers"),
    Path("docs/work"),
    Path("website"),
)
allowed_exact = allowed_exact | {Path("docs/STATUS.md")}
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

# metrics.md is private-only; on a public export it must be absent instead.
if [ -f "$REPO/docs/skills-reorg/metrics.md" ]; then
  assert_not_contains "$(cat "$REPO/docs/skills-reorg/metrics.md")" "test_dummy_pipeline.sh" "metrics no longer call artifact smoke an E2E journey"
elif [ -d "$REPO/_archive" ]; then
  fail "metrics no longer call artifact smoke an E2E journey (private repo missing docs/skills-reorg/metrics.md)"
else
  TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: metrics doc is absent on the public surface"
fi

# Public onboarding docs must pin the same reviewed submodule tag. README is the
# single source of truth for the current tag; the bridge doc must not lag behind
# and send consumers to a pre-fix contract. Compare extracted tags (do not hardcode
# a version) so this assertion keeps holding across releases.
readme_tag="$(grep -oE 'checkout v[0-9]+\.[0-9]+\.[0-9]+' "$REPO/README.md" | head -1 | sed 's/checkout //')"
bridge_tag="$(grep -oE 'checkout v[0-9]+\.[0-9]+\.[0-9]+' "$REPO/docs/skill-commons-submodule-bridge.md" | head -1 | sed 's/checkout //')"
if [ -n "$readme_tag" ] && [ "$readme_tag" = "$bridge_tag" ]; then
  TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: bridge doc pins the same submodule tag as README ($readme_tag)"
else
  fail "bridge doc pins the same submodule tag as README (README=$readme_tag bridge=$bridge_tag)"
fi

finish
