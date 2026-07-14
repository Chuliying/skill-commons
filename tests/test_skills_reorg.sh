#!/usr/bin/env bash
set -u
REPO="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
HASH1="$(mktemp)"
HASH2="$(mktemp)"
trap 'rm -rf "$TMP"; rm -f "$HASH1" "$HASH2"' EXIT
. "$REPO/tests/bootstrap/lib/assert.sh"

active_names() {
  find "$REPO" -mindepth 2 -maxdepth 2 -type f -name SKILL.md \
    -not -path "$REPO/_archive/*" \
    -not -path "$REPO/.claude/*" \
    -not -path "$REPO/.codex/*" \
    -not -path "$REPO/.agents/*" \
    -print | sed "s#^$REPO/##;s#/SKILL.md##" | sort
}

bash -n "$REPO/bootstrap/generate.sh" || fail "generate.sh syntax"
bash -n "$REPO/bootstrap/onboard.sh" || fail "onboard.sh syntax"
changed_shells="$REPO/bootstrap/generate.sh
$REPO/bootstrap/onboard.sh
$REPO/verification-before-completion/scripts/verify.sh
$REPO/qa/scripts/run-qa.sh
$REPO/scripts/run-gate.sh
$REPO/scripts/manifest-stack.sh
$REPO/scripts/export-public.sh"
if printf '%s\n' "$changed_shells" | while IFS= read -r script; do
  [ -z "$script" ] || bash -n "$script" || exit 1
done; then
  TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: shared runner shell syntax"
else
  fail "shared runner shell syntax"
fi

if [ ! -e "$REPO/finishing-a-development-branch" ]; then
  TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: retired Git owner has no top-level source tree"
else
  fail "retired Git owner has no top-level source tree"
fi

mkdir -p "$TMP/claude" "$TMP/codex" "$TMP/agents"
PROFILE=all bash "$REPO/bootstrap/generate.sh" "$TMP/claude" "$TMP/codex" "$TMP/agents" >/dev/null

active="$(active_names | grep -vx 'skill-creator')"
for target in claude codex agents; do
  generated="$(find "$TMP/$target" -mindepth 2 -maxdepth 2 -type f -name SKILL.md -print |
    sed "s#^$TMP/$target/##;s#/SKILL.md##" | sort)"
  assert_eq "$active" "$generated" "active skills match generated $target skills"
  if [ ! -e "$TMP/$target/finishing-a-development-branch" ]; then
    TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: generated $target omits the retired Git owner"
  else
    fail "generated $target omits the retired Git owner"
  fi
done

for generated_root in .claude/skills .codex/skills .agents/skills; do
  if [ ! -e "$REPO/$generated_root/finishing-a-development-branch" ]; then
    TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: $generated_root removes the retired Git owner directory"
  else
    fail "$generated_root removes the retired Git owner directory"
  fi
  assert_not_contains "$(cat "$REPO/$generated_root/.skill-commons-ownership-v1")" \
    "finishing-a-development-branch" "$generated_root ledger removes the retired Git owner"
done

find "$TMP" -type f -print0 | sort -z | xargs -0 shasum -a 256 > "$HASH1"
PROFILE=all bash "$REPO/bootstrap/generate.sh" "$TMP/claude" "$TMP/codex" "$TMP/agents" >/dev/null
find "$TMP" -type f -print0 | sort -z | xargs -0 shasum -a 256 > "$HASH2"
if diff -u "$HASH1" "$HASH2" >/dev/null; then
  TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: generate is content-idempotent"
else
  fail "generate is content-idempotent"
fi

# Unknown entries have no skill-commons ownership evidence and must survive.
mkdir -p "$TMP/claude/qa-validator" "$TMP/codex/_archive/stale"
printf stale > "$TMP/claude/qa-validator/SKILL.md"
printf stale > "$TMP/codex/_archive/stale/SKILL.md"
PROFILE=all bash "$REPO/bootstrap/generate.sh" "$TMP/claude" "$TMP/codex" "$TMP/agents" >/dev/null
assert_file "$TMP/claude/qa-validator/SKILL.md" "generate preserves an unowned skill directory"
assert_file "$TMP/codex/_archive/stale/SKILL.md" "generate preserves an unowned support directory"

# A profile shrink removes entries recorded in the ownership ledger, while an
# unrelated foreign skill remains untouched.
PROFILE_TARGET="$TMP/profile-shrink"
PROFILE="core optional" bash "$REPO/bootstrap/generate.sh" "$PROFILE_TARGET" >/dev/null
assert_file "$PROFILE_TARGET/codebase-understanding/SKILL.md" "optional skill exists before profile shrink"
mkdir -p "$PROFILE_TARGET/foreign-skill"
printf foreign > "$PROFILE_TARGET/foreign-skill/KEEP"
PROFILE=core bash "$REPO/bootstrap/generate.sh" "$PROFILE_TARGET" >/dev/null
if [ ! -e "$PROFILE_TARGET/codebase-understanding" ]; then
  TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: profile shrink removes a previously managed skill"
else
  fail "profile shrink left a previously managed skill"
fi
assert_file "$PROFILE_TARGET/foreign-skill/KEEP" "profile shrink preserves a foreign skill"
assert_file "$PROFILE_TARGET/.skill-commons-ownership-v1" "generate records managed ownership"

for path in .claude/skills .codex .agents; do
  if git -C "$REPO" check-ignore -q "$path"; then
    TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: $path is gitignored"
  else
    fail "$path is gitignored"
  fi
done

if [ -z "$(git -C "$REPO" ls-files '.claude/skills/**' '.codex/**' '.agents/**')" ]; then
  TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: generated trigger dirs are untracked"
else
  fail "generated trigger dirs are untracked"
fi

OLD_NAMES='qa-generator|qa-validator|prototype-tuner|prototype-builder|api-doc-parser|repo-investigator|change-tracker|project-onboarding|executing-plans|writing-plans|code-reviewer'
if python3 - "$REPO" "$OLD_NAMES" <<'PY'
from pathlib import Path
import re
import sys

repo = Path(sys.argv[1])
pattern = re.compile(sys.argv[2])
excluded = {"_archive", ".claude", ".codex", ".agents"}
files = [repo / "graph-context-check.md"]
files.extend(
    p for p in repo.glob("*/SKILL.md")
    if p.parent.name not in excluded
)
hits = []
for path in files:
    for line_no, line in enumerate(path.read_text(errors="replace").splitlines(), 1):
        if pattern.search(line):
            hits.append(f"{path.relative_to(repo)}:{line_no}:{line}")
if hits:
    print("\n".join(hits))
    raise SystemExit(1)
PY
then
  TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: active skill content has no legacy skill references"
else
  fail "active skill content has no legacy skill references"
fi

active_sources_text="$(sed '/^## Optional runtime adapters/,$d' "$REPO/SOURCES.md")"
retired_sources_text="$(sed -n '/^## Retired source provenance/,/^## /p' "$REPO/SOURCES.md")"
assert_not_contains "$active_sources_text" "finishing-a-development-branch" "metadata active provenance excludes the retired owner"
assert_contains "$retired_sources_text" "finishing-a-development-branch" "metadata retains retired owner provenance"
assert_contains "$retired_sources_text" "handoff-only compatibility notice" "metadata retains retired local-patch history"

python3 - "$REPO" "$TMP/claude" <<'PY'
from collections import Counter
from pathlib import Path
import json
import re
import sys

repo = Path(sys.argv[1])
generated = Path(sys.argv[2])
excluded = {"_archive", ".claude", ".codex", ".agents"}
skills = sorted(
    p for p in repo.glob("*/SKILL.md")
    if p.parts[-2] not in excluded
)
required_stages = {"skill", "plan", "docs", "design", "implement", "qa", "review"}
stages = Counter()
sources = []
source_kinds = Counter()
vendored = []
outputs = []
errors = []
expected_outputs = {
    "brainstorming": "<work_root>/<slug>/brainstorm.md",
    "prd-interview": "<work_root>/<slug>/prd.md",
    "grilling": "<work_root>/<slug>/{adr.md,glossary.md}",
    "implement": "<work_root>/<slug>/implement-report.md",
    "markdown": "<docs_root>/reference/<name>.md",
    "plan-sync": "<work_root>/<slug>/plan/plan.md",
    "prototype": "<work_root>/<slug>/prototype/index.html",
    "qa": "<work_root>/<slug>/{qa-plan,qa-report}.md",
    "spec": "<work_root>/<slug>/spec.md",
    "to-prd": "<work_root>/<slug>/prd.md",
}
required_body_tokens = {
    "brainstorming": ["<work_root>/<slug>/brainstorm.md"],
    "prd-interview": ["<work_root>/<slug>/prd.md"],
    "grilling": ["<work_root>/<slug>/", "adr.md", "glossary.md"],
    "implement": ["<work_root>/<slug>/implement-report.md"],
    "markdown": ["<docs_root>/reference/<name>.md"],
    "plan-sync": ["<work_root>/<slug>/plan/plan.md", "journal.md", "canonical-v2"],
    "prototype": ["<work_root>/<slug>/prototype/index.html"],
    "qa": ["<work_root>/<slug>/qa-plan.md", "<work_root>/<slug>/qa-report.md"],
    "spec": ["<work_root>/<slug>/spec.md"],
    "to-prd": ["<work_root>/<slug>/", "prd.md"],
}

for path in skills:
    lines = path.read_text(errors="replace").splitlines()
    if not lines or lines[0] != "---":
        errors.append(f"{path}: missing frontmatter")
        continue
    try:
        end = lines.index("---", 1)
    except ValueError:
        errors.append(f"{path}: unclosed frontmatter")
        continue
    fields = {}
    for line in lines[1:end]:
        if ":" in line and not line.startswith((" ", "\t")):
            key, value = line.split(":", 1)
            fields[key.strip()] = value.strip()
    for key in ("name", "description", "stage", "source_kind"):
        if key not in fields:
            errors.append(f"{path}: missing {key}")
    if fields.get("name") != path.parent.name:
        errors.append(f"{path}: name does not match directory")
    stages[fields.get("stage", "<missing>")] += 1
    source_kind = fields.get("source_kind", "<missing>")
    source_kinds[source_kind] += 1
    if source_kind not in {"original", "adapted", "vendored"}:
        errors.append(f"{path}: invalid source_kind={source_kind!r}")
    if "source" in fields:
        sources.append(fields["name"])
        if source_kind == "original":
            errors.append(f"{path}: original skill must not declare external source")
    elif source_kind in {"adapted", "vendored"}:
        errors.append(f"{path}: {source_kind} skill must declare source")
    if source_kind == "vendored":
        vendored.append(fields.get("name"))

    body = "\n".join(lines[end + 1:])
    has_adaptation_signal = bool(re.search(r"改編自|adapted from", body, re.IGNORECASE))
    has_bundled_license = any(path.parent.glob("LICENSE*"))
    if has_adaptation_signal or has_bundled_license:
        if "source" not in fields or source_kind not in {"adapted", "vendored"}:
            errors.append(
                f"{path}: adaptation text or bundled license requires source and adapted/vendored source_kind"
            )
    if "output" in fields:
        outputs.append(path)
        text = "\n".join(lines)
        if "meta.yml" not in text or "../ARTIFACTS.md" not in text:
            errors.append(f"{path}: output skill lacks meta.yml/ARTIFACTS contract")
        expected = expected_outputs.get(fields.get("name"))
        if expected is None:
            errors.append(f"{path}: unexpected output-producing skill")
        elif fields["output"] != expected:
            errors.append(
                f"{path}: output={fields['output']!r}, expected={expected!r}"
            )
        for token in required_body_tokens.get(fields.get("name"), []):
            if token not in body:
                errors.append(f"{path}: body missing output token {token!r}")

missing_outputs = sorted(set(expected_outputs) - {p.parent.name for p in outputs})
if missing_outputs:
    errors.append(f"missing output skills: {missing_outputs}")

missing_stages = sorted(required_stages - set(stages))
if missing_stages:
    errors.append(f"missing stages: {missing_stages}")

table_names = []
table_kinds = {}
active_source_table = (repo / "SOURCES.md").read_text().split(
    "## Optional runtime adapters", 1
)[0]
for line in active_source_table.splitlines():
    match = re.match(r"^\|\s*([a-z][a-z0-9-]*)(?:\s+_\(dep\)_)?\s*\|", line)
    if match and match.group(1) != "skill":
        table_names.append(match.group(1))
        cells = [cell.strip() for cell in line.strip().strip("|").split("|")]
        if len(cells) >= 4:
            table_kinds[match.group(1)] = cells[3]
if sorted(sources) != sorted(table_names):
    errors.append(f"source mismatch: frontmatter={sorted(sources)} table={sorted(table_names)}")
expected_table_kinds = {
    path.parent.name: next(
        line.split(":", 1)[1].strip()
        for line in path.read_text(errors="replace").splitlines()
        if line.startswith("source_kind:")
    )
    for path in skills
    if path.parent.name in sources
}
if table_kinds != expected_table_kinds:
    errors.append(f"source kind mismatch: SOURCES={table_kinds} frontmatter={expected_table_kinds}")

lock_names = sorted(json.loads((repo / "skills-lock.json").read_text())["skills"])
if lock_names != sorted(vendored):
    errors.append(f"lockfile mismatch: lock={lock_names} vendored={sorted(vendored)}")

link_pattern = re.compile(r"(?<![\w/])\.\./[^\s)`>\"\]]+\.md(?:#[^\s)`>\"\]]+)?")
for path in generated.rglob("*.md"):
    for line_no, line in enumerate(path.read_text(errors="replace").splitlines(), 1):
        for match in link_pattern.finditer(line):
            raw = match.group(0).rstrip(".,;:")
            target = (path.parent / raw.split("#", 1)[0]).resolve()
            if not target.exists():
                errors.append(f"{path}:{line_no}: broken {raw}")

if errors:
    print("\n".join(errors))
    raise SystemExit(1)

print(
    f"metadata ok: skills={len(skills)} stages={dict(stages)} "
    f"source_kinds={dict(source_kinds)} sources={len(sources)} outputs={len(outputs)}"
)
PY
if [ "$?" = 0 ]; then
  TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: metadata, provenance, stages, outputs, and generated links"
else
  fail "metadata, provenance, stages, outputs, and generated links"
fi

if ! grep -rn '\.agent/artifacts' --include='SKILL.md' \
  "$REPO"/*/SKILL.md >/dev/null &&
   grep -q '<work_root>/<slug>/' "$REPO/ARTIFACTS.md" &&
   grep -q 'schema_version: work-item/v3' "$REPO/ARTIFACTS.md" &&
   grep -q 'work_status: active | completed | abandoned' "$REPO/ARTIFACTS.md" &&
   grep -q 'delivery_status: not_requested | awaiting_approval | approved | pr_created | merged | deployed' "$REPO/ARTIFACTS.md"; then
  TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: v3 work-item artifact contract has no active legacy paths"
else
  fail "v3 work-item artifact contract has no active legacy paths"
fi

# `_archive/` only exists in the private development repo; a public export
# legitimately has no docs/STATUS.md, but CLAUDE.md must stay free of volatile
# status sections on both surfaces.
if { [ ! -d "$REPO/_archive" ] || [ -f "$REPO/docs/STATUS.md" ]; } &&
   grep -q 'docs/STATUS.md' "$REPO/CLAUDE.md" &&
   ! grep -q '^## \(目前狀態\|計劃\|TODO\|Backlog\)$' "$REPO/CLAUDE.md"; then
  TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: volatile status is split out of CLAUDE.md"
else
  fail "volatile status is split out of CLAUDE.md"
fi

if [ ! -f "$REPO/AGENTS.md" ] || {
     grep -q 'docs/STATUS.md' "$REPO/AGENTS.md" &&
     ! grep -q '^## \(目前狀態\|計劃\|TODO\|Backlog\)$' "$REPO/AGENTS.md"
   }; then
  TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: root AGENTS.md is optional and stable when present"
else
  fail "root AGENTS.md is optional and stable when present"
fi

# --- Leakage guard: self-authored shared skills must not hardcode project-unique
#     literals. Externalize via manifest (paths/stack/git_workflow). See
#     docs/skills-reorg/project-pattern-externalization.md.
python3 - "$REPO" <<'PY'
import re
import sys
from pathlib import Path

repo = Path(sys.argv[1])
excluded_dirs = {"_archive", ".claude", ".codex", ".agents", ".git", "docs",
                 "bootstrap", "tests", "scripts"}
external_names = set()
active_source_table = (repo / "SOURCES.md").read_text().split(
    "## Optional runtime adapters", 1
)[0]
for line in active_source_table.splitlines():
    match = re.match(r"^\|\s*([a-z][a-z0-9-]*)(?:\s+_\(dep\)_)?\s*\|", line)
    if match and match.group(1) != "skill":
        external_names.add(match.group(1))

# Denylisted project-unique literals (project pattern leakage).
# Each entry: (pattern, reason, exempt file names). Exemptions are for
# framework-conditional reference docs whose framework terms ARE the content.
denylist = [
    (re.compile(r"src/__tests__"), "test path literal (use paths.tests_root)", set()),
    (re.compile(r"src/design-system"), "design path literal (use paths.mockup_root)", set()),
    (re.compile(r"/" + "Users" + r"/"), "personal absolute path", set()),
    (re.compile(r"\b(?:vitest|playwright|msw)\b", re.I), "test framework literal (use stack.framework/stack.e2e_cmd)", set()),
    (re.compile(r"\bnpx\s+(?:tsc|playwright|ts-node)\b", re.I), "toolchain command literal (use stack.* cmd)", set()),
    (re.compile(r"\b(?:git checkout\s+|git pull origin\s+|git merge(?!-)\s+|git rebase origin/|origin/)(?:dev|develop|main|master)\b"),
     "fixed branch literal (use git_workflow.base_branch)", set()),
    # Package-manager commands belong in manifest Stack.
    (re.compile(r"\bnpm (?:test|run|audit|view)\b"), "bare npm command (use stack.* cmd / package-manager audit)", set()),
    # Source-project auth paths: resolve via manifest Domain Skill Names or ask.
    (re.compile(r"src/(?:utils|constants)/auth"), "source-project auth path (use manifest domain skill / ask user)", set()),
    # Framework-specific client env prefix: allowed only as an example (例：...)
    # or when describing what scan-secrets.sh detects; framework reference docs
    # (conditionally loaded per manifest stack.framework) are exempt by name.
    (re.compile(r"^(?!.*(?:例[:：]|scan-secrets)).*NEXT_PUBLIC"),
     "framework env prefix literal (write as 例：Next.js 的 NEXT_PUBLIC_，或移入 framework reference)",
     {"nextjs-security-patterns.md"}),
    # Hardcoded scan root in commands: read manifest Paths or ask.
    (re.compile(r"src/ --include|\ssrc/\s*$"), "hardcoded src/ scan root (use manifest paths / ask user)", set()),
    # Shared skills must not assume the host repo already has a pre-commit hook.
    (re.compile(r"本專案的 pre-commit"), "assumes host pre-commit hook (check repo evidence instead)", set()),
]
local_denylist = repo / ".local-leakage-patterns"
if local_denylist.exists():
    for raw in local_denylist.read_text(errors="replace").splitlines():
        pattern = raw.strip()
        if pattern and not pattern.startswith("#"):
            denylist.append((re.compile(pattern, re.I), "local private marker", set()))
# Provenance/creation logs document upstream origin, not consuming-project leakage.
skip_files = {"CREATION-LOG.md"}

def is_external(skill_dir: Path) -> bool:
    sk = skill_dir / "SKILL.md"
    if not sk.exists() or skill_dir.name not in external_names:
        return False
    head = sk.read_text(errors="replace").splitlines()[:30]
    return any(re.match(r"^source\s*:", ln) for ln in head)

violations = []
for skill_dir in sorted(p for p in repo.iterdir() if p.is_dir()):
    if skill_dir.name in excluded_dirs or skill_dir.name.startswith("."):
        continue
    if not (skill_dir / "SKILL.md").exists():
        continue
    if is_external(skill_dir):
        continue
    for md in sorted(skill_dir.rglob("*.md")):
        if md.name in skip_files:
            continue
        for line_no, line in enumerate(md.read_text(errors="replace").splitlines(), 1):
            for rx, why, exempt in denylist:
                if md.name in exempt:
                    continue
                if rx.search(line):
                    rel = md.relative_to(repo)
                    violations.append(f"{rel}:{line_no}: {why}: {line.strip()}")

if violations:
    print("project-pattern leakage detected (externalize via manifest/domain skill):")
    print("\n".join(violations))
    raise SystemExit(1)
print("leakage guard ok: no project-unique literals in self-authored shared skills")
PY
if [ "$?" = 0 ]; then
  TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: no project-pattern leakage in self-authored shared skills"
else
  fail "no project-pattern leakage in self-authored shared skills"
fi

# Public-release hygiene: tracked product examples are synthetic, personal
# absolute paths are absent, and git archive excludes private history material.
python3 - "$REPO" <<'PY'
from pathlib import Path
import re
import subprocess
import sys

# Resolve symlinks (e.g. macOS /var -> /private/var) so resolved link targets
# stay comparable with relative_to() below.
repo = Path(sys.argv[1]).resolve()
skip = {".git", ".agents", ".claude", ".codex"}
errors = []

def export_ignored(relative: Path) -> bool:
    output = subprocess.check_output(
        ["git", "-C", str(repo), "check-attr", "export-ignore", "--", str(relative)],
        text=True,
    ).strip()
    return output.rsplit(": ", 1)[-1] == "set"

raw_paths = subprocess.check_output(
    ["git", "-C", str(repo), "ls-files", "--cached", "--others", "--exclude-standard", "-z"]
)
for raw in raw_paths.split(b"\0"):
    if not raw:
        continue
    relative = Path(raw.decode())
    path = repo / relative
    if not path.is_file() or any(part in skip for part in path.parts):
        continue
    if export_ignored(relative) or "__pycache__" in relative.parts:
        continue
    text = path.read_text(errors="replace")
    if ("/" + "Users" + "/") in text:
        errors.append(f"{path.relative_to(repo)}: personal absolute path")

# `_archive/` marks the private development repo. On a public export the
# private-only material must be absent, and its content checks do not apply.
private_dev = (repo / "_archive").is_dir()

synthetic = "/acme/dashboard/sales/overview"
for rel in (
    "shared-skill-onboarder/references/project-init.md",
    "_archive/project-onboarding/SKILL.md",
):
    path = repo / rel
    if not path.is_file():
        if private_dev or not rel.startswith("_archive/"):
            errors.append(f"{rel}: missing synthetic sitemap example")
        continue
    if synthetic not in path.read_text(errors="replace"):
        errors.append(f"{rel}: missing synthetic sitemap example")

sample = (repo / "prd-interview/examples/good-prd-sample.md").read_text(errors="replace")
if "使用數據" not in sample:
    errors.append("prd-interview/examples/good-prd-sample.md: sample is not industry-neutral")
for token in ("FR-001", "ERR-001", "AC-001", "## 4. Flow", "Mockup evidence", "Design tokens"):
    if token not in sample:
        errors.append(f"prd-interview/examples/good-prd-sample.md: sample missing {token!r}")
for stale in ("FR-01", "ERR-02", "AC-02", "至少 3 個 ERR", "版本歷史"):
    if stale in sample:
        errors.append(f"prd-interview/examples/good-prd-sample.md: sample keeps stale pattern {stale!r}")

release_plan_rel = "docs/skills-reorg/public-release-plan.md"
handoff_rel = "docs/work/public-release/reviews/fable-final-review-handoff.md"
if private_dev:
    release_plan = (repo / release_plan_rel).read_text(errors="replace")
    handoff = (repo / handoff_rel).read_text(errors="replace")
    active_release_docs = {
        release_plan_rel: release_plan,
        handoff_rel: handoff,
    }
    for rel, text in active_release_docs.items():
        if "GitHub repo `agent-playbook` → rename 為 `skill-commons`" in text:
            errors.append(f"{rel}: must not instruct direct history-bearing repo rename")
    if "clean-history" not in release_plan or "public `skill-commons`" not in release_plan:
        errors.append(f"{release_plan_rel}: missing clean-history public repo contract")
    if "history-bearing" not in handoff or "must stay private" not in handoff:
        errors.append(f"{handoff_rel}: missing private dev repo warning")
else:
    for rel in (release_plan_rel, handoff_rel):
        if (repo / rel).exists():
            errors.append(f"{rel}: private release doc must not exist on a public surface")

excluded = (
    "_archive/project-onboarding/SKILL.md",
    "docs/ai-harness-engineering-anthropic.md",
    "docs/anthropic-skill-system.md",
    "docs/superpowers/plans/2026-05-29-cross-platform-skill-bootstrap.md",
    "docs/skills-reorg/plan.md",
    "docs/work/work-item-docs/meta.yml",
    "docs/work-summary.html",
    "docs/STATUS.md",
    "docs/shared-skill-onboarding-checklist.md",
    "docs/skill-eval-sop.md",
)
included = (
    "docs/skills-reorg/decisions.md",
    "docs/skill-commons-submodule-bridge.md",
)

def export_attr(rel: str) -> str:
    output = subprocess.check_output(
        ["git", "-C", str(repo), "check-attr", "export-ignore", "--", rel],
        text=True,
    ).strip()
    return output.rsplit(": ", 1)[-1]

for rel in excluded:
    if export_attr(rel) != "set":
        errors.append(f"{rel}: must be export-ignore")
    if not private_dev and (repo / rel).exists():
        errors.append(f"{rel}: private-only path present on public surface")
for rel in included:
    if export_attr(rel) == "set":
        errors.append(f"{rel}: required public doc is export-ignored")

for root_doc in ("README.md", "INDEX.md", "SOURCES.md", "AGENTS.md", "CLAUDE.md"):
    text = (repo / root_doc).read_text(errors="replace")
    for target in re.findall(r"\[[^]]+\]\(([^)]+)\)", text):
        local = target.split("#", 1)[0]
        if not local or "://" in local:
            continue
        path = (repo / local).resolve()
        if path.is_file() and export_attr(str(path.relative_to(repo))) == "set":
            errors.append(f"{root_doc}: public link targets export-ignored {local}")

if errors:
    print("\n".join(errors))
    raise SystemExit(1)
print("public-release hygiene ok: synthetic examples, no personal paths, export boundary enforced")
PY
if [ "$?" = 0 ]; then
  TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: public-release hygiene and export boundary"
else
  fail "public-release hygiene and export boundary"
fi

candidate_index="$TMP/public-release-candidate.index"
candidate_tree=""
if GIT_INDEX_FILE="$candidate_index" git -C "$REPO" read-tree HEAD &&
   GIT_INDEX_FILE="$candidate_index" git -C "$REPO" add -A -- .; then
  candidate_tree="$(GIT_INDEX_FILE="$candidate_index" git -C "$REPO" write-tree)"
fi

if [ -n "$candidate_tree" ]; then
  archive_listing="$(git -C "$REPO" archive --worktree-attributes "$candidate_tree" | tar -tf -)"
else
  archive_listing=""
fi
private_entries="$(printf '%s\n' "$archive_listing" | grep -E \
  '^_archive/|^docs/(ai-harness-engineering-anthropic\.md|anthropic-skill-system\.md|superpowers/|work-summary\.html|work/|STATUS\.md|shared-skill-onboarding-checklist\.md|skill-eval-sop\.md)' || true)"
private_reorg_entries="$(printf '%s\n' "$archive_listing" |
  grep '^docs/skills-reorg/' |
  grep -v '^docs/skills-reorg/$' |
  grep -v '^docs/skills-reorg/decisions\.md$' || true)"
if [ -z "$private_entries" ] && [ -z "$private_reorg_entries" ] &&
   printf '%s\n' "$archive_listing" | grep -q '^docs/skills-reorg/decisions\.md$' &&
   printf '%s\n' "$archive_listing" | grep -q '^docs/skill-commons-submodule-bridge\.md$' &&
   printf '%s\n' "$archive_listing" | grep -q '^scripts/export-public\.sh$'; then
  TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: git archive smoke contains only public documentation"
else
  fail "git archive smoke contains only public documentation"
fi

EXPORT_TMP="$TMP/public-export"
if bash "$REPO/scripts/export-public.sh" "$EXPORT_TMP" --include-worktree >/dev/null &&
   [ -f "$EXPORT_TMP/README.md" ] &&
   [ -f "$EXPORT_TMP/scripts/export-public.sh" ] &&
   [ -f "$EXPORT_TMP/docs/skills-reorg/decisions.md" ] &&
   [ ! -e "$EXPORT_TMP/docs/work" ] &&
   [ ! -e "$EXPORT_TMP/docs/STATUS.md" ] &&
   [ ! -e "$EXPORT_TMP/_archive" ]; then
  TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: public export script creates clean payload"
else
  fail "public export script creates clean payload"
fi

EXPORT_GIT_TMP="$TMP/public-export-git"
mkdir -p "$EXPORT_GIT_TMP"
git -C "$EXPORT_GIT_TMP" init -q
git -C "$EXPORT_GIT_TMP" config user.email test@example.com
git -C "$EXPORT_GIT_TMP" config user.name Test
printf 'old public checkout state\n' > "$EXPORT_GIT_TMP/old.txt"
git -C "$EXPORT_GIT_TMP" add old.txt
git -C "$EXPORT_GIT_TMP" commit -q -m "old public checkout"
export_git_head="$(git -C "$EXPORT_GIT_TMP" rev-parse HEAD)"
if bash "$REPO/scripts/export-public.sh" "$EXPORT_GIT_TMP" --force --include-worktree >/dev/null &&
   [ "$(git -C "$EXPORT_GIT_TMP" rev-parse HEAD 2>/dev/null || true)" = "$export_git_head" ] &&
   git -C "$EXPORT_GIT_TMP" status --short >/dev/null &&
   [ -f "$EXPORT_GIT_TMP/README.md" ] &&
   [ -f "$EXPORT_GIT_TMP/scripts/export-public.sh" ] &&
   [ ! -e "$EXPORT_GIT_TMP/docs/work" ] &&
   [ ! -e "$EXPORT_GIT_TMP/docs/STATUS.md" ]; then
  TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: public export --force preserves target git checkout"
else
  fail "public export --force preserves target git checkout"
fi

IN_REPO_TARGET="$REPO/.tmp-public-export-reject/child"
rm -rf "$REPO/.tmp-public-export-reject"
if ! bash "$REPO/scripts/export-public.sh" "$IN_REPO_TARGET" --include-worktree >/dev/null 2>&1 &&
   [ ! -e "$REPO/.tmp-public-export-reject" ]; then
  TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: public export rejects in-repo target without creating parents"
else
  fail "public export rejects in-repo target without creating parents"
fi
rm -rf "$REPO/.tmp-public-export-reject"

SYMLINK_INSIDE_TARGET="$REPO/.tmp-public-export-symlink-target"
SYMLINK_OUTSIDE="$TMP/public-export-symlink"
rm -rf "$SYMLINK_INSIDE_TARGET" "$SYMLINK_OUTSIDE"
mkdir -p "$SYMLINK_INSIDE_TARGET"
ln -s "$SYMLINK_INSIDE_TARGET" "$SYMLINK_OUTSIDE"
if ! bash "$REPO/scripts/export-public.sh" "$SYMLINK_OUTSIDE" --force --include-worktree >/dev/null 2>&1 &&
   [ ! -e "$SYMLINK_INSIDE_TARGET/README.md" ]; then
  TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: public export rejects symlink targets inside private repo"
else
  fail "public export rejects symlink targets inside private repo"
fi
rm -rf "$SYMLINK_INSIDE_TARGET" "$SYMLINK_OUTSIDE"

EXPORT_NONGIT_TMP="$TMP/public-export-nongit"
mkdir -p "$EXPORT_NONGIT_TMP"
printf 'stale\n' > "$EXPORT_NONGIT_TMP/stale.txt"
if ! bash "$REPO/scripts/export-public.sh" "$EXPORT_NONGIT_TMP" --include-worktree >/dev/null 2>&1 &&
   [ -f "$EXPORT_NONGIT_TMP/stale.txt" ]; then
  TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: public export rejects non-empty non-git target"
else
  fail "public export rejects non-empty non-git target"
fi

# The export payload must work as a standalone public repository: committing it
# must keep every .gitignore even under a hostile global excludes file, and the
# repository test suites advertised to public users must pass without any
# private-only file. SKILL_COMMONS_PAYLOAD_CHECK=1 marks the nested run and
# stops the recursion at depth one.
if [ "${SKILL_COMMONS_PAYLOAD_CHECK:-0}" != "1" ]; then
  PAYLOAD_HOME="$TMP/payload-home"
  mkdir -p "$PAYLOAD_HOME"
  printf '.gitignore\n' > "$PAYLOAD_HOME/excludes"
  cat > "$PAYLOAD_HOME/gitconfig" <<EOF
[core]
	excludesFile = $PAYLOAD_HOME/excludes
[user]
	email = payload-check@example.com
	name = payload-check
EOF
  git -C "$EXPORT_TMP" init -q &&
    env GIT_CONFIG_GLOBAL="$PAYLOAD_HOME/gitconfig" git -C "$EXPORT_TMP" add -A &&
    env GIT_CONFIG_GLOBAL="$PAYLOAD_HOME/gitconfig" git -C "$EXPORT_TMP" commit -qm "payload check" ||
    fail "payload check repository setup"
  if git -C "$EXPORT_TMP" ls-files --error-unmatch \
       .gitignore \
       tests/fixtures/python-cli/.gitignore \
       tests/fixtures/ts-web/.gitignore >/dev/null 2>&1; then
    TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: payload commit keeps ignore files under hostile global excludes"
  else
    fail "payload commit keeps ignore files under hostile global excludes"
  fi
  PAYLOAD_LOG="$TMP/payload-suite.log"
  if (cd "$EXPORT_TMP" &&
      PROFILE=all bash bootstrap/generate.sh &&
      SKILL_COMMONS_PAYLOAD_CHECK=1 bash tests/run-all.sh) >"$PAYLOAD_LOG" 2>&1; then
    TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: payload passes its complete public test suite without private files"
  else
    fail "payload passes its complete public test suite without private files"
    grep -vE '^  ok:' "$PAYLOAD_LOG" | tail -20
  fi
fi

SECRET_SCAN_LOG="$TMP/secret-scan.log"
if (cd "$REPO" && unset PROJECT_MANIFEST && bash security/scripts/scan-secrets.sh "$REPO" >"$SECRET_SCAN_LOG" 2>&1); then
  TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: repository secret scan has no self-generated false positives"
else
  fail "repository secret scan has no self-generated false positives"
  sed -n '1,160p' "$SECRET_SCAN_LOG"
fi

# The recommended verification runner must execute manifest commands rather than
# assuming a package manager or JavaScript stack.
RUNNER_TMP="$TMP/runner-project"
mkdir -p "$RUNNER_TMP/.agent"
cat > "$RUNNER_TMP/.agent/project-manifest.md" <<'EOF'
## Paths
- work_root: docs/work
- docs_root: docs

## Stack
- typed_contracts: true
- has_e2e: true
- typecheck_cmd: printf 'typecheck\n' >> "$VERIFY_LOG"
- lint_cmd: printf 'lint\n' >> "$VERIFY_LOG"
- test_cmd: printf 'test\n' >> "$VERIFY_LOG"
- e2e_cmd: printf 'e2e\n' >> "$VERIFY_LOG"
EOF
export VERIFY_LOG="$RUNNER_TMP/commands.log"
if (cd "$RUNNER_TMP" && bash "$REPO/verification-before-completion/scripts/verify.sh" >/dev/null) &&
   assert_eq $'typecheck\nlint\ntest' "$(cat "$VERIFY_LOG")" "verification runner uses manifest stack commands"; then
  :
else
  fail "verification runner uses manifest stack commands"
fi
: > "$VERIFY_LOG"
if (cd "$RUNNER_TMP" && bash "$REPO/qa/scripts/run-qa.sh" >/dev/null) &&
   assert_eq $'typecheck\nlint\ntest\ne2e' "$(cat "$VERIFY_LOG")" "qa runner uses manifest stack commands"; then
  :
else
  fail "qa runner uses manifest stack commands"
fi
cat > "$RUNNER_TMP/.agent/project-manifest.md" <<'EOF'
## Stack
- typed_contracts: true
- typecheck_cmd: exit 3
- lint_cmd: printf 'lint\n'
- test_cmd: printf 'test\n'
EOF
if (cd "$RUNNER_TMP" && bash "$REPO/verification-before-completion/scripts/verify.sh" >/dev/null); then
  fail "configured command exit 3 remains a failure"
else
  TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: configured command exit 3 remains a failure"
fi
if grep -qE 'docs/qa|qa_root' "$REPO/qa/scripts/run-qa.sh"; then
  fail "qa runner has no legacy QA root fallback"
else
  TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: qa runner has no legacy QA root fallback"
fi

# A local main/dev branch is not proof of the repository's base branch. Only the
# remote default branch is safe to suggest without asking the user.
SCAN_TMP="$TMP/scan-project"
mkdir -p "$SCAN_TMP"
git -C "$SCAN_TMP" init -q
git -C "$SCAN_TMP" checkout -q -b main
git -C "$SCAN_TMP" -c user.name=test -c user.email=test@example.com commit --allow-empty -qm init
git -C "$SCAN_TMP" branch dev
scan_without_remote="$(cd "$SCAN_TMP" && node "$REPO/shared-skill-onboarder/scripts/scan-project.js")"
if printf '%s\n' "$scan_without_remote" | grep -qE '^- base_branch: ⚠️ not detected$'; then
  TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: scanner does not guess base branch from local names"
else
  fail "scanner does not guess base branch from local names"
fi
git -C "$SCAN_TMP" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main
cat > "$SCAN_TMP/package.json" <<'EOF'
{"scripts":{"test":"unit","lint":"lint","typecheck":"types","e2e":"browser"}}
EOF
touch "$SCAN_TMP/pnpm-lock.yaml"
mkdir -p "$SCAN_TMP/.agent/artifacts/qa"
scan_with_remote="$(cd "$SCAN_TMP" && node "$REPO/shared-skill-onboarder/scripts/scan-project.js")"
if printf '%s\n' "$scan_with_remote" | grep -qE '^- base_branch: `main`$'; then
  TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: scanner reads remote default branch"
else
  fail "scanner reads remote default branch"
fi
if printf '%s\n' "$scan_with_remote" |
   grep -qE '^- test_cmd: `pnpm test`$' &&
   printf '%s\n' "$scan_with_remote" |
   grep -qE '^- typecheck_cmd: `pnpm run typecheck`$' &&
   printf '%s\n' "$scan_with_remote" |
   grep -qE '^- e2e_cmd: `pnpm run e2e`$' &&
   printf '%s\n' "$scan_with_remote" |
   grep -qE '^- work_root: `docs/work`$' &&
   printf '%s\n' "$scan_with_remote" |
   grep -qE '^- docs_root: `docs`$' &&
   printf '%s\n' "$scan_with_remote" |
   grep -q 'legacy.*\.agent/artifacts'; then
  TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: scanner respects package manager and v2 artifact roots"
else
  fail "scanner respects package manager and v2 artifact roots"
fi

# Generated/tool-call wrapper residue is never valid shared-skill content.
wrapper_scan_targets=("$REPO/shared-skill-onboarder")
if [ -f "$REPO/docs/skills-reorg/project-pattern-externalization.md" ]; then
  wrapper_scan_targets+=("$REPO/docs/skills-reorg/project-pattern-externalization.md")
fi
if ! grep -rnE '^</?(content|invoke)>$' "${wrapper_scan_targets[@]}" >/dev/null; then
  TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: no generated wrapper residue"
else
  fail "no generated wrapper residue"
fi

# The workflow has exactly three human decisions. Plan/QA consistency checks
# remain machine gates and must not be presented as extra approvals.
router_gate_text="$(cat "$REPO/skill-router/SKILL.md")"
gate_ok=1
for gate in "PRD 核可" "team 設計核可" "發布核可"; do
  printf '%s\n' "$router_gate_text" | grep -qF "$gate" || gate_ok=0
done
if [ "$gate_ok" -eq 1 ] &&
   ! printf '%s\n' "$router_gate_text" | grep -qE 'Gate 0|Gate 3|Gate P1'; then
  TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: router exposes only the three workflow human decisions"
else
  fail "router exposes only the three workflow human decisions"
fi

# Public entry surface: Quick Start must present tools before install steps, and
# the README badge must point at a CI workflow that runs every repository
# verification suite on pushes and pull requests.
if python3 - "$REPO" <<'PY'
from pathlib import Path
import re
import sys

repo = Path(sys.argv[1])
readme = (repo / "README.md").read_text(errors="replace")
readme_en = (repo / "README.en.md").read_text(errors="replace")
codebase_skill = (repo / "codebase-understanding" / "SKILL.md").read_text(errors="replace")
bridge_path = repo / "docs/skill-commons-submodule-bridge.md"
bridge = bridge_path.read_text(errors="replace") if bridge_path.is_file() else ""
workflow_path = repo / ".github/workflows/ci.yml"
errors = []

if not bridge:
    errors.append("missing docs/skill-commons-submodule-bridge.md")

quick_start = readme.find("## Quick Start")
install = readme.find("### 1. Pin submodule", quick_start)
if quick_start < 0 or install < quick_start:
    errors.append("README Quick Start must place tools before installation")
else:
    prereq_body = readme[quick_start:install]
    for token in (
        "Git",
        "Bash 3.2+",
        "jq",
        "Python 3.10+",
        "Node.js 18+",
    ):
        if token not in prereq_body:
            errors.append(f"README prerequisites missing {token!r}")

for label, text in (("README.md", readme), ("README.en.md", readme_en)):
    if "Bash 3.2+" not in text:
        errors.append(f"{label} must state the exercised Bash 3.2+ baseline")
    if "Bash 4+" in text:
        errors.append(f"{label} must not require unnecessary Bash 4+")

if "不是" in readme or "並非" in readme:
    errors.append("README.md must state boundaries directly instead of using X-is-not-Y framing")
for pattern in (r"\b(?:is|are) not\b", r",\s+not\b"):
    if re.search(pattern, readme_en, flags=re.IGNORECASE):
        errors.append("README.en.md must state boundaries directly instead of using X-is-not-Y framing")

repo_map_command = "<codebase-understanding-dir>/scripts/repo_map.py"
if f"python3 {repo_map_command}" not in codebase_skill:
    errors.append("codebase-understanding Repo Map examples must select python3 explicitly")
if f"\npython {repo_map_command}" in codebase_skill:
    errors.append("codebase-understanding must not use ambiguous python for Repo Map")

new_url = "git@github.com:Chuliying/skill-commons.git"
if new_url not in readme or new_url not in bridge:
    errors.append("active onboarding docs must use the skill-commons repository URL")
active_docs = [
    repo / "README.md",
    *(repo / "docs").glob("*.md"),
    *(repo / "bootstrap").rglob("*"),
]
old_url = "git@github.com:Chuliying/agent-playbook.git"
for path in active_docs:
    if path.is_file() and old_url in path.read_text(errors="replace"):
        errors.append(f"active surface still contains old repository URL: {path.relative_to(repo)}")

badge = "actions/workflows/ci.yml/badge.svg"
if badge not in readme:
    errors.append("README missing ci.yml status badge")

if not workflow_path.is_file():
    errors.append("missing .github/workflows/ci.yml")
else:
    workflow = workflow_path.read_text(errors="replace")
    active_lines = [
        line for line in workflow.splitlines()
        if line.strip() and not line.lstrip().startswith("#")
    ]
    active_tokens = [line.strip() for line in active_lines]
    required_lines = (
        "push:",
        "branches: [main]",
        "pull_request:",
        "runs-on: ubuntu-latest",
        "runs-on: macos-latest",
        "run: bash tests/run-all.sh",
        "run: /bin/bash --version",
        "run: PATH=/usr/bin:/bin /bin/bash tests/bootstrap/test_generate_safety.sh",
        "run: PATH=/usr/bin:/bin /bin/bash tests/bootstrap/test_manage.sh",
        "run: PATH=/usr/bin:/bin /bin/bash tests/bootstrap/test_onboard.sh",
    )
    for line in required_lines:
        if line not in active_tokens:
            errors.append(f"ci.yml missing active line {line!r}")
    import re
    def verify_commands(name):
        text = (repo / name).read_text(errors="replace")
        match = re.search(r"^- Verify: `([^`]+)`$", text, re.MULTILINE)
        if not match:
            errors.append(f"{name} missing canonical Verify command")
            return []
        return match.group(1).split(" && ")

    agents_verify = verify_commands("AGENTS.md")
    claude_verify = verify_commands("CLAUDE.md")
    if agents_verify != claude_verify:
        errors.append("AGENTS.md and CLAUDE.md Verify chains diverge")
    if agents_verify != ["bash tests/run-all.sh"]:
        errors.append("AGENTS.md and CLAUDE.md must expose one canonical root Verify command")
    for command in agents_verify:
        if f"run: {command}" not in active_tokens:
            errors.append(f"ci.yml missing canonical Verify command {command!r}")
    if sum(token.startswith("uses: actions/checkout@") for token in active_tokens) != 2:
        errors.append("ci.yml must check out the repository once in each Verify job")

root_runner_path = repo / "tests" / "run-all.sh"
if not root_runner_path.is_file():
    errors.append("missing canonical tests/run-all.sh")
else:
    root_runner = root_runner_path.read_text(errors="replace")
    expected_suites = (
        "tests/test_skills_reorg.sh",
        "tests/test_profiles.sh",
        "tests/test_artifact_contract.sh",
        "tests/test_work_items.sh",
        "tests/test_protocol_registry.sh",
        "tests/test_plan_sync.sh",
        "tests/test_repo_map.sh",
        "tests/test_journey_evals.sh",
        "tests/test_gate_automation.sh",
        "tests/test_brainstorming.sh",
        "tests/test_release_convergence.sh",
        "tests/bootstrap/run-all.sh",
    )
    for suite in expected_suites:
        if root_runner.count(suite) != 1:
            errors.append(f"canonical root runner must invoke {suite} exactly once")
    if "ALL TESTS PASSED" not in root_runner:
        errors.append("canonical root runner must emit the final success marker")

bootstrap_runner = (repo / "tests" / "bootstrap" / "run-all.sh").read_text(errors="replace")
if "../test_" in bootstrap_runner:
    errors.append("bootstrap run-all must stay inside the bootstrap suite boundary")

if "bash tests/run-all.sh" not in readme:
    errors.append("README maintainer verification must use the canonical root runner")

if errors:
    print("\n".join(errors))
    raise SystemExit(1)
PY
then
  TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: public release README and CI entry surface"
else
  fail "public release README and CI entry surface"
fi

# Router flows and implement must share one execution-mode contract. Personal,
# bug-fix, and refactor flows intentionally omit some team artifacts; implement
# must not silently make those omitted files mandatory or forbid brownfield edits.
if python3 - "$REPO" <<'PY'
from pathlib import Path
import json
import re
import sys

repo = Path(sys.argv[1])
router = (repo / "skill-router/SKILL.md").read_text(errors="replace")
implement = (repo / "implement/SKILL.md").read_text(errors="replace")
registry = json.loads((repo / "protocol-registry.json").read_text())
errors = []

modes = tuple(registry.get("execution_modes", {}))
if set(modes) != {"team-feature", "personal-feature", "bug-fix", "refactor"}:
    errors.append(f"protocol registry execution modes are incomplete: {modes!r}")

flow_modes = {
    "### Team feature\n": "team-feature",
    "### Personal feature\n": "personal-feature",
    "## Flow: 修錯\n": "bug-fix",
    "### Refactor\n": "refactor",
}
for heading, mode in flow_modes.items():
    start = router.find(heading)
    if start < 0:
        errors.append(f"skill-router missing flow heading {heading.strip()!r}")
        continue
    next_candidates = [
        router.find(marker, start + len(heading))
        for marker in ("\n### ", "\n## Flow:")
    ]
    end = min((pos for pos in next_candidates if pos >= 0), default=len(router))
    section = router[start:end]
    if f"Execution Mode: `{mode}`" not in section:
        errors.append(f"{heading.strip()} missing explicit Execution Mode: `{mode}`")

for name, text in (("skill-router", router), ("implement", implement)):
    if "../protocol-registry.json" not in text:
        errors.append(f"{name} does not reference the protocol registry")
if re.search(r"(?m)^\| `(?:team-feature|personal-feature|bug-fix|refactor)` \|", implement):
    errors.append("implement duplicates the registry execution-mode matrix")

for forbidden in (
    "不修改既有核心入口",
    "新功能透過「新增檔案」實作",
    "修改既有程式碼而非擴充",
):
    if forbidden in implement:
        errors.append(f"implement still forbids required brownfield work: {forbidden}")

required_contract_tokens = (
    "Execution Mode",
    "條件式輸入",
    "protocol-registry.json",
    "verification-before-completion",
)
for token in required_contract_tokens:
    if token not in implement:
        errors.append(f"implement input/handoff contract missing {token!r}")

if errors:
    print("\n".join(errors))
    raise SystemExit(1)
PY
then
  TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: router and implement execution-mode contracts are aligned"
else
  fail "router and implement execution-mode contracts are aligned"
fi

# Personal micro-tasks may bypass planning artifacts only under three objective
# constraints. The branch must be explicit, test-first, and fall back to the
# normal Flow A-P whenever any constraint is false or unknown.
if python3 - "$REPO" <<'PY'
from pathlib import Path
import sys

router = (Path(sys.argv[1]) / "skill-router/SKILL.md").read_text(errors="replace")
errors = []

start = router.find("### Micro-task 直達")
ends = (
    [router.find(marker, start + 1) for marker in ("\n### ", "\n---\n")]
    if start >= 0 else []
)
end = min((position for position in ends if position >= 0), default=len(router))
section = router[start:end] if start >= 0 else ""
for token in (
    "單檔或少數檔",
    "無新依賴",
    "無 schema/API 變更",
    "任一條件不成立或不確定",
    "implement（帶 failing test）",
    "verification-before-completion",
):
    if token not in section:
        errors.append(f"router Micro-task branch missing {token!r}")
if "to-prd" in section:
    errors.append("router Micro-task direct branch must not require to-prd")

if errors:
    print("\n".join(errors))
    raise SystemExit(1)
PY
then
  TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: personal micro-task direct path has objective bounds"
else
  fail "personal micro-task direct path has objective bounds"
fi

# Public release documentation is a product surface and a governance contract.
if python3 - "$REPO" <<'PY'
from pathlib import Path
import sys

repo = Path(sys.argv[1])
errors = []

required_files = (
    "README.en.md",
    "CONTRIBUTING.md",
    "CHANGELOG.md",
    "docs/spec-state-protocol.md",
    "docs/discovery-and-planning.md",
    "docs/evaluation.md",
    "skill-creator/references/new-skill-checklist.md",
    "scripts/lint-docs.sh",
)
for relative in required_files:
    if not (repo / relative).is_file():
        errors.append(f"missing public release artifact: {relative}")

readme = (repo / "README.md").read_text(errors="replace")
artifacts = (repo / "ARTIFACTS.md").read_text(errors="replace")
spec_state = (repo / "docs/spec-state-protocol.md").read_text(errors="replace")
discovery = (repo / "docs/discovery-and-planning.md").read_text(errors="replace")
evaluation = (repo / "docs/evaluation.md").read_text(errors="replace")
codebase = (repo / "codebase-understanding/SKILL.md").read_text(errors="replace")
security = (repo / "security/SKILL.md").read_text(errors="replace")
head = "\n".join(readme.splitlines()[:35])
for token in ("Claude Code", "Codex", "Cursor", "可攜式 feature-delivery protocol"):
    if token not in head:
        errors.append(f"README first 35 lines missing positioning token {token!r}")

ordered_sections = (
    "## 核心價值",
    "## 什麼時候值得用",
    "## Quick Start",
    "## 執行模型",
    "## 信任與授權邊界",
    "## 已驗證與尚未驗證",
    "## 文件入口",
    "## Maintainer verification",
)
positions = [readme.find(section) for section in ordered_sections]
if any(position < 0 for position in positions) or positions != sorted(positions):
    errors.append(f"README public-audience section order invalid: {list(zip(ordered_sections, positions))}")

for token in ("execution_mode", "delivery_mode", "capability_packs", "submodule", "jq", "CONTRIBUTING.md", "CHANGELOG.md"):
    if token not in readme:
        errors.append(f"README missing public release content {token!r}")

owned_tokens = (
    ("canonical-v2", artifacts, "artifact contract"),
    ("host_goal=unmanaged", spec_state, "spec-state protocol"),
    ("textual_candidate", codebase, "Repo Map owner"),
    ("CLEAR/FINDINGS/SKIP", security, "security owner"),
    ("83.33%", discovery, "discovery evidence"),
    ("Luna-high scoring repair", evaluation, "evaluation evidence"),
)
for token, text, owner in owned_tokens:
    if token not in text:
        errors.append(f"{owner} missing public release content {token!r}")

for target in (
    "docs/spec-state-protocol.md",
    "docs/discovery-and-planning.md",
    "docs/evaluation.md",
    "bootstrap/README.md",
    "docs/profile-platform-support.md",
):
    if target not in readme:
        errors.append(f"README missing authoritative link {target!r}")

if len(readme.splitlines()) > 180:
    errors.append("README exceeds the 180-line entry-surface budget")

contributing_path = repo / "CONTRIBUTING.md"
if contributing_path.is_file():
    contributing = contributing_path.read_text(errors="replace")
    for heading in (
        "## 新增門檻",
        "## 成熟度標記",
        "## 新增檢查表",
        "## 修改門檻",
        "## 淘汰路徑",
        "## 健檢節奏",
    ):
        if heading not in contributing:
            errors.append(f"CONTRIBUTING missing lifecycle section {heading!r}")
    if "skill-creator/references/new-skill-checklist.md" not in contributing:
        errors.append("CONTRIBUTING must link the reusable new-skill checklist")

skill_creator = (repo / "skill-creator/SKILL.md").read_text(errors="replace")
if "references/new-skill-checklist.md" not in skill_creator:
    errors.append("skill-creator must link its local lifecycle checklist reference")

ci_path = repo / ".github/workflows/ci.yml"
root_runner_path = repo / "tests/run-all.sh"
if ci_path.is_file() and root_runner_path.is_file():
    ci = ci_path.read_text(errors="replace")
    root_runner = root_runner_path.read_text(errors="replace")
    if "bash tests/run-all.sh" not in ci or "tests/test_skills_reorg.sh" not in root_runner:
        errors.append("CI must reach full documentation lint through the canonical root runner")

valid_maturity = {"experimental", "stable"}
core = set((repo / "profiles/core").read_text().split())
for skill_path in repo.glob("*/SKILL.md"):
    lines = skill_path.read_text(errors="replace").splitlines()
    if not lines or lines[0] != "---":
        continue
    end = lines.index("---", 1)
    fields = {}
    for line in lines[1:end]:
        if ":" in line and not line.startswith((" ", "\t")):
            key, value = line.split(":", 1)
            fields[key.strip()] = value.strip()
    maturity = fields.get("maturity", "stable")
    if maturity not in valid_maturity:
        errors.append(f"{skill_path}: invalid maturity {maturity!r}")
    if maturity == "experimental" and skill_path.parent.name in core:
        errors.append(f"{skill_path}: experimental skill must not be in core profile")

if errors:
    print("\n".join(errors))
    raise SystemExit(1)
PY
then
  TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: public release documentation and skill lifecycle contract"
else
  fail "public release documentation and skill lifecycle contract"
fi

humanizer_text="$(cat "$REPO/humanizer/SKILL.md")"
assert_contains "$humanizer_text" "blader/humanizer@1b48564898e999219882660237fde01bf4843a0f" "humanizer pins upstream source"
assert_contains "$humanizer_text" "If the user's intent is to evade a required disclosure policy" "humanizer has disclosure boundary"
assert_contains "$humanizer_text" "False-positive guard" "humanizer has false-positive guard"
assert_contains "$(cat "$REPO/SOURCES.md")" "blader/humanizer" "humanizer provenance is recorded"

if [ -x "$REPO/scripts/lint-docs.sh" ] &&
   bash -n "$REPO/scripts/lint-docs.sh" &&
   bash "$REPO/scripts/lint-docs.sh"; then
  TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: active documentation passes full STYLE lint"
else
  fail "active documentation passes full STYLE lint"
fi

# The formal PRD skill has one concise contract and one public name.
if python3 - "$REPO" <<'PY'
from pathlib import Path
import re
import sys

repo = Path(sys.argv[1])
skill_path = repo / "prd-interview/SKILL.md"
template_path = repo / "prd-template.md"  # canonical shared PRD shape (SSOT)
field_guide_path = repo / "prd-interview/references/prd-field-guide.md"
gate_path = repo / "prd-interview/references/gate-1.md"
to_prd_path = repo / "to-prd/SKILL.md"
shared_onboarder_path = repo / "shared-skill-onboarder/SKILL.md"
spec_path = repo / "spec/SKILL.md"
spec_template_path = repo / "spec/resources/spec-template.md"
integration_spec_template_path = repo / "spec/resources/integration-spec-template.md"
spec_field_guide_path = repo / "spec/references/spec-field-guide.md"
qa_template_path = repo / "qa/resources/qa-template.md"
qa_plan_path = repo / "qa/references/qa-plan.md"
qa_validate_path = repo / "qa/references/qa-validate.md"
review_template_path = repo / "caveman-review/references/review-template.md"
errors = []

if not skill_path.is_file():
    errors.append("missing prd-interview/SKILL.md")
    skill = ""
else:
    skill = skill_path.read_text(errors="replace")
    if len(skill.splitlines()) > 250:
        errors.append(f"prd-interview/SKILL.md exceeds 250 lines: {len(skill.splitlines())}")
    for token in (
        "name: prd-interview",
        "## Phase 1: Context",
        "## Phase 2: 風險與範圍",
        "## Phase 3: 訪談",
        "## Phase 4: 產出",
        "## Phase 5: Gate 1 自檢",
        "references/prd-field-guide.md",
        "references/gate-1.md",
        "../prd-template.md",
        "sprint_tracking",
        "至少 1 個真實風險",
        "低新穎度",
        "manifest `has_ui`",
    ):
        if token not in skill:
            errors.append(f"prd-interview contract missing {token!r}")
    if re.search(r"\bStep\s+\d+\.\d+", skill):
        errors.append("prd-interview still has decimal Step numbering")

if not shared_onboarder_path.is_file():
    errors.append("missing shared-skill-onboarder/SKILL.md")
else:
    shared_onboarder = shared_onboarder_path.read_text(errors="replace")
    if re.search(r"\bStep\s+\d+\.\d+", shared_onboarder):
        errors.append("shared-skill-onboarder must use semantic process headings, not decimal Step numbering")
    for token in (
        "### Track 判斷（Light / Full）",
        "### Project Variables 填寫（Paths / Stack / Git Workflow）",
        "Track 判斷: Light / Full",
        "Light track",
        "Full track",
    ):
        if token not in shared_onboarder:
            errors.append(f"shared-skill-onboarder contract missing {token!r}")

legacy_template = repo / "prd-interview/resources/prd-template.md"
if legacy_template.is_file():
    errors.append("prd-interview/resources/prd-template.md must be removed; use canonical prd-template.md")
if not template_path.is_file():
    errors.append("missing canonical prd-template.md")
else:
    template = template_path.read_text(errors="replace")
    for token in (
        "## 1. Follow-ups",
        "## 3. Scope",
        "## 4. Flow",
        "## 5. Functional Requirements (FR)",
        "## 8. Acceptance Criteria (AC)",
        "## 12. Gate 1 Check",
        "### In scope",
        "### Out of scope",
        "使用者價值",
        "Design tokens",
        "Mockup evidence",
    ):
        if token not in template:
            errors.append(f"PRD template missing {token!r}")
    headings = re.findall(r"^## (\d+)\. ", template, flags=re.M)
    if headings != [str(n) for n in range(1, 13)]:
        errors.append(f"PRD template headings must be integer sections 1-12, got {headings!r}")
    if re.search(r"^## \d+\.\d+", template, flags=re.M):
        errors.append("PRD template still has decimal section headings")
    for stale in (
        "/spec-generator",
        "[重複上述結構]",
        "FR-002",
        "ERR-002",
        "ERR-003",
        "AC-002",
        "使用說明",
        "版本規則",
        "## 0.",
        "## 0.5",
        "## 1.2",
        "## 1.5",
    ):
        if stale in template:
            errors.append(f"PRD template keeps stale/noisy placeholder {stale!r}")

if not field_guide_path.is_file():
    errors.append("missing prd-interview/references/prd-field-guide.md")
else:
    field_guide = field_guide_path.read_text(errors="replace")
    for token in ("Flow", "Given-When-Then", "UI evidence", "Mockup evidence", "Design tokens", "Blocking", "Skipped"):
        if token not in field_guide:
            errors.append(f"PRD field guide missing {token!r}")

if not to_prd_path.is_file():
    errors.append("missing to-prd/SKILL.md")
else:
    to_prd = to_prd_path.read_text(errors="replace")
    if "<prd-template>" in to_prd:
        errors.append("to-prd must not embed an inline PRD template; reference canonical ../prd-template.md")
    for token in ("../prd-template.md", "check-prd.py"):
        if token not in to_prd:
            errors.append(f"to-prd must reference {token!r}")
    for noisy in ("A LONG", "extremely extensive", "Further Notes", "Do NOT include specific file paths"):
        if noisy in to_prd:
            errors.append(f"to-prd keeps noisy old PRD instruction {noisy!r}")

if not qa_template_path.is_file():
    errors.append("missing qa/resources/qa-template.md")
else:
    qa_template = qa_template_path.read_text(errors="replace")
    for token in (
        "## Selected Seam",
        "Spec seam ID",
        "Spec reference",
        "## 1. Traceability",
        "## 2. Test Cases",
        "Machine traceability gate",
    ):
        if token not in qa_template:
            errors.append(f"QA template missing {token!r}")
    for noisy in ("使用說明", "同上", "/reverse-prd", "TC-002", "AC-002", "ERR-002"):
        if noisy in qa_template:
            errors.append(f"QA template keeps noisy/stale placeholder {noisy!r}")

if not spec_path.is_file():
    errors.append("missing spec/SKILL.md")
else:
    spec = spec_path.read_text(errors="replace")
    if "Flow section" not in spec and "流程章節" not in spec:
        errors.append("spec must read the PRD Flow section by name, not by fixed number")
    for stale in ("§1.5 流程圖", "## 7. Flow", "找 **3 個類似實作**", "有 web search 紀錄"):
        if stale in spec:
            errors.append(f"spec keeps stale/noisy instruction {stale!r}")
    if re.search(r"\bStep\s+\d+\.\d+", spec):
        errors.append("spec must use semantic process headings, not decimal Step numbering")
    if spec_field_guide_path.is_file() and "references/spec-field-guide.md" not in spec:
        errors.append("spec/SKILL.md must explicitly reference spec-field-guide.md when it exists")

spec_template_contract = (
    "## Capability Snapshot",
    "## Files",
    "## Contracts",
    "## API Contract",
    "## UI Design",
    "## Flow / Data Flow",
    "## Errors",
    "## Decisions",
    "## Steps",
    "## Selected Seam",
    "## Test Strategy",
    "## Gate 2 自檢",
)
conditional_contract = ("has_api", "has_ui", "typed_contracts", "has_e2e")
capability_rows = (
    "| `has_ui` |",
    "| `has_api` |",
    "| `typed_contracts` |",
    "| `has_e2e` |",
)
test_strategy_levels = ("| Unit |", "| Integration |", "| Component |", "| E2E |")
for template_path in (spec_template_path, integration_spec_template_path):
    label = template_path.relative_to(repo)
    if not template_path.is_file():
        errors.append(f"missing {label}")
        continue
    template = template_path.read_text(errors="replace")
    if re.search(r"^##\s+\d+(?:\.\d+)?\.", template, flags=re.M):
        errors.append(f"{label} must use semantic top-level headings, not numbered public sections")
    if re.search(r"^##\s+\d+\.\d+", template, flags=re.M):
        errors.append(f"{label} still has decimal top-level section headings")
    for token in spec_template_contract:
        if token not in template:
            errors.append(f"{label} missing spec contract token {token!r}")
    for token in conditional_contract:
        if token not in template:
            errors.append(f"{label} missing capability contract token {token!r}")
    for token in capability_rows:
        if token not in template:
            errors.append(f"{label} missing Capability Snapshot row {token!r}")
    for token in test_strategy_levels:
        if token not in template:
            errors.append(f"{label} missing Test Strategy level {token!r}")

if spec_field_guide_path.is_file():
    field_guide = spec_field_guide_path.read_text(errors="replace")
    for token in (
        "Capability Snapshot",
        "Files",
        "Contracts",
        "API Contract",
        "UI Design",
        "Flow / Data Flow",
        "Errors",
        "Decisions",
        "Steps",
        "Selected Seam",
        "Seam ID",
        "closest stable existing boundary",
        "execution cost",
        "Test Strategy",
        "Gate 2",
        "semantic heading",
        "PRD Flow section",
    ):
        if token not in field_guide:
            errors.append(f"spec field guide missing {token!r}")

for downstream_path in (qa_plan_path, qa_validate_path):
    if downstream_path.is_file():
        downstream = downstream_path.read_text(errors="replace")
        if re.search(r"\bStep\s+\d+\.\d+", downstream):
            label = downstream_path.relative_to(repo)
            errors.append(f"{label} must use semantic headings, not decimal Step numbers")

if qa_plan_path.is_file():
    qa_plan = qa_plan_path.read_text(errors="replace")
    for forbidden in (
        "必須包含至少一個 L2",
        "如果只有 E2E，退回重寫",
        "NO E2E tests until Unit Tests pass",
        "**必做** (Gate 1)",
        "Phase 1**: 跑 Unit Test",
        "L2 Unit Test: [PASS/FAIL] (至少 1 個)",
        "Spec record 已完整複製",
    ):
        if forbidden in qa_plan:
            errors.append(f"qa/references/qa-plan.md keeps unconditional seam rule {forbidden!r}")
    for token in ("Selected Seam", "Spec seam ID", "Spec reference", "check-selected-seam.py"):
        if token not in qa_plan:
            errors.append(f"qa/references/qa-plan.md missing selected-seam contract {token!r}")

if not review_template_path.is_file():
    errors.append("missing caveman-review/references/review-template.md")
else:
    review_template = review_template_path.read_text(errors="replace")
    issues_pos = review_template.find("### Issues")
    assessment_pos = review_template.find("### Assessment")
    if issues_pos < 0 or assessment_pos < 0 or issues_pos > assessment_pos:
        errors.append("review template must put issues before assessment")
    for noisy in ("### Strengths", "### Recommendations", "Acknowledge strengths"):
        if noisy in review_template:
            errors.append(f"review template keeps verbose review section {noisy!r}")

if not gate_path.is_file():
    errors.append("missing prd-interview/references/gate-1.md")
else:
    gate = gate_path.read_text(errors="replace")
    for token in ("FR", "Given-When-Then", "ERR", "範圍外", "模糊詞", "FU", "NFR", "角色視角"):
        if token not in gate:
            errors.append(f"Gate 1 reference missing {token!r}")

for relative in ("prd-interview/SKILL.md", "spec/SKILL.md"):
    path = repo / relative
    if path.is_file() and re.search(r"\bgit\s+(?:pull|merge)\b", path.read_text(errors="replace")):
        errors.append(f"{relative} still performs git pull/merge")

finish_path = repo / "finishing-a-development-branch/SKILL.md"
sync_path = repo / "sync-work/SKILL.md"
if finish_path.exists():
    errors.append("retired finishing-a-development-branch/SKILL.md still exists")
if not sync_path.is_file():
    errors.append("missing sync-work/SKILL.md")
else:
    sync = sync_path.read_text(errors="replace")
    for mode in ("Scoped Save", "Integrate", "Finish", "Recovery"):
        if f"## Mode: {mode}" not in sync:
            errors.append(f"sync-work/SKILL.md missing authoritative {mode} mode")

if (repo / "dev-kickoff").exists():
    errors.append("active dev-kickoff directory still exists")

team_profile = (repo / "profiles/team-sprint").read_text(errors="replace")
if "prd-interview" not in team_profile or "dev-kickoff" in team_profile:
    errors.append("team-sprint profile has stale PRD skill name")

allowed_old_name = {
    Path("skill-router/SKILL.md"),
    Path("CHANGELOG.md"),
}
excluded_roots = {"_archive", ".claude", ".codex", ".agents"}
for path in repo.rglob("*.md"):
    relative = path.relative_to(repo)
    if relative.parts[0] in excluded_roots:
        continue
    if relative.parts[:2] == ("journey-evals", "runs"):
        continue
    if len(relative.parts) >= 2 and relative.parts[:2] in {
        ("docs", "skills-reorg"),
        ("docs", "superpowers"),
        ("docs", "work"),
    }:
        continue
    for line_number, line in enumerate(path.read_text(errors="replace").splitlines(), 1):
        if "dev-kickoff" not in line:
            continue
        if relative == Path("skill-router/SKILL.md") and "dev-kickoff（舊名）" in line:
            continue
        if relative == Path("CHANGELOG.md") and "prd-interview" in line:
            continue
        errors.append(f"stale active dev-kickoff reference: {relative}:{line_number}")

if errors:
    print("\n".join(errors))
    raise SystemExit(1)
PY
then
  TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: prd-interview refactor and active-surface rename"
else
  fail "prd-interview refactor and active-surface rename"
fi

finish
