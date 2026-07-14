#!/usr/bin/env bash
set -u
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
. "$(dirname "$0")/lib/assert.sh"
. "$REPO/bootstrap/lib/ownership.sh"

# A missing relative path with no slash must fall back to the current directory
# instead of repeatedly applying ${cursor%/*} without making progress.
RELATIVE_PROBE_ROOT="$TMP/relative-probe-root"
RELATIVE_PROBE_MARKER="$TMP/relative-probe-complete"
mkdir -p "$RELATIVE_PROBE_ROOT"
(
  error() { printf 'ERROR: %s\n' "$*" >&2; }
  cd "$RELATIVE_PROBE_ROOT"
  preflight_writable_directory missing-relative-path "relative probe"
  printf 'complete\n' > "$RELATIVE_PROBE_MARKER"
) >/dev/null 2>&1 &
relative_probe_pid=$!
for _ in $(seq 1 20); do
  if ! kill -0 "$relative_probe_pid" 2>/dev/null; then break; fi
  sleep 0.05
done
if kill -0 "$relative_probe_pid" 2>/dev/null; then
  kill "$relative_probe_pid" 2>/dev/null || true
  wait "$relative_probe_pid" 2>/dev/null || true
  fail "relative no-slash writable preflight terminates"
else
  set +e
  wait "$relative_probe_pid"
  relative_probe_rc=$?
  set -e
  if [ "$relative_probe_rc" -eq 0 ] && [ -f "$RELATIVE_PROBE_MARKER" ]; then
    TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: relative no-slash writable preflight terminates"
  else
    fail "relative no-slash writable preflight terminates"
  fi
fi

# Direct generation must preserve entries it does not own.
TARGET="$TMP/target"
mkdir -p "$TARGET/foreign-skill" "$TARGET/scripts"
printf 'foreign\n' > "$TARGET/foreign-skill/marker"
printf 'foreign fragment\n' > "$TARGET/FOREIGN.md"
printf 'foreign helper\n' > "$TARGET/scripts/foreign-helper.sh"
PROFILE=all bash "$REPO/bootstrap/generate.sh" "$TARGET" >/dev/null
assert_file "$TARGET/foreign-skill/marker" "generate preserves foreign target entries"
assert_file "$TARGET/FOREIGN.md" "generate preserves a foreign root fragment"
assert_file "$TARGET/scripts/foreign-helper.sh" "generate preserves a foreign shared helper"
assert_file "$TARGET/.skill-commons-ownership-v1" "generate writes an ownership ledger"

# Onboarding uses the generator's real preflight before publishing any adapter.
# The preflight exercises discovery, locks, ledgers, and collisions without
# writing the target.
PREFLIGHT_TARGET="$TMP/preflight-target"
mkdir -p "$PREFLIGHT_TARGET"
printf 'keep\n' > "$PREFLIGHT_TARGET/sentinel"
SKILL_COMMONS_PREFLIGHT_ONLY=1 PROFILE=all bash "$REPO/bootstrap/generate.sh" "$PREFLIGHT_TARGET" >/dev/null
assert_file "$PREFLIGHT_TARGET/sentinel" "generate preflight preserves existing target content"
if [ ! -e "$PREFLIGHT_TARGET/skill-router" ] && [ ! -e "$PREFLIGHT_TARGET/.skill-commons-ownership-v1" ]; then
  TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: generate preflight publishes no managed output"
else
  fail "generate preflight publishes no managed output"
fi

# A target equal to the source root would delete the generator and every skill
# before the copy loop starts. It must be rejected before any mutation.
FAKE_SOURCE="$TMP/fake-source"
mkdir -p "$FAKE_SOURCE/demo" "$FAKE_SOURCE/scripts"
printf '%s\n' '---' 'name: demo' '---' > "$FAKE_SOURCE/demo/SKILL.md"
printf 'source sentinel\n' > "$FAKE_SOURCE/source-sentinel"
set +e
SKILLS_SRC="$FAKE_SOURCE" PROFILE=all bash "$REPO/bootstrap/generate.sh" "$FAKE_SOURCE" >/dev/null 2>&1
same_root_rc=$?
set -e
assert_neq "0" "$same_root_rc" "generate rejects a target equal to its source root"
assert_file "$FAKE_SOURCE/source-sentinel" "source-root rejection happens before mutation"

ANCESTOR_CASE="$TMP/ancestor-case"
ANCESTOR_SOURCE="$ANCESTOR_CASE/source"
mkdir -p "$ANCESTOR_SOURCE/demo"
printf '%s\n' '---' 'name: demo' '---' > "$ANCESTOR_SOURCE/demo/SKILL.md"
printf 'ancestor sentinel\n' > "$ANCESTOR_CASE/sentinel"
set +e
SKILLS_SRC="$ANCESTOR_SOURCE" PROFILE=all bash "$REPO/bootstrap/generate.sh" "$ANCESTOR_CASE" >/dev/null 2>&1
ancestor_rc=$?
set -e
assert_neq "0" "$ancestor_rc" "generate rejects a target that contains its source root"
assert_file "$ANCESTOR_CASE/sentinel" "source-ancestor rejection happens before mutation"

# Replacing a symlinked skill root silently changes user filesystem topology and
# can redirect future writes. Reject it and preserve both the link and target.
EXTERNAL="$TMP/external"
LINK_TARGET="$TMP/link-target"
mkdir -p "$EXTERNAL"
printf 'external\n' > "$EXTERNAL/marker"
ln -s "$EXTERNAL" "$LINK_TARGET"
set +e
PROFILE=all bash "$REPO/bootstrap/generate.sh" "$LINK_TARGET" >/dev/null 2>&1
symlink_rc=$?
set -e
assert_neq "0" "$symlink_rc" "generate rejects a symlinked target root"
if [ -L "$LINK_TARGET" ]; then
  TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: generate preserves the rejected target symlink"
else
  fail "generate replaced the rejected target symlink"
fi
assert_file "$EXTERNAL/marker" "generate does not mutate a symlink target"

# A nested symlink must not redirect installation of a managed helper outside
# the target root.
NESTED_TARGET="$TMP/nested-target"
NESTED_EXTERNAL="$TMP/nested-external"
mkdir -p "$NESTED_TARGET" "$NESTED_EXTERNAL"
printf 'nested sentinel\n' > "$NESTED_EXTERNAL/sentinel"
ln -s "$NESTED_EXTERNAL" "$NESTED_TARGET/scripts"
set +e
PROFILE=all bash "$REPO/bootstrap/generate.sh" "$NESTED_TARGET" >/dev/null 2>&1
nested_symlink_rc=$?
set -e
assert_neq "0" "$nested_symlink_rc" "generate rejects a nested managed-path symlink"
if [ -L "$NESTED_TARGET/scripts" ]; then
  TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: generate preserves a rejected nested symlink"
else
  fail "generate replaced a rejected nested symlink"
fi
assert_file "$NESTED_EXTERNAL/sentinel" "nested symlink rejection preserves external content"

# Onboard-driven generation is constrained to recognized agent discovery roots
# below the selected project.
PROJECT="$TMP/project"
WRONG_TARGET="$PROJECT/not-an-agent-root"
mkdir -p "$PROJECT"
set +e
SKILL_COMMONS_PROJECT_ROOT="$PROJECT" PROFILE=all bash "$REPO/bootstrap/generate.sh" "$WRONG_TARGET" >/dev/null 2>&1
wrong_target_rc=$?
set -e
assert_neq "0" "$wrong_target_rc" "generate rejects an unrecognized project target"
if [ ! -e "$WRONG_TARGET" ]; then
  TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: wrong-target rejection happens before mutation"
else
  fail "generate created an unrecognized project target"
fi

# Every target must pass preflight before the first target is changed.
FIRST_TARGET="$TMP/first-target"
SECOND_EXTERNAL="$TMP/second-external"
SECOND_TARGET="$TMP/second-target"
mkdir -p "$FIRST_TARGET" "$SECOND_EXTERNAL"
printf 'first sentinel\n' > "$FIRST_TARGET/sentinel"
printf 'second sentinel\n' > "$SECOND_EXTERNAL/sentinel"
ln -s "$SECOND_EXTERNAL" "$SECOND_TARGET"
set +e
PROFILE=all bash "$REPO/bootstrap/generate.sh" "$FIRST_TARGET" "$SECOND_TARGET" >/dev/null 2>&1
multi_target_rc=$?
set -e
assert_neq "0" "$multi_target_rc" "generate preflights every target before mutation"
assert_file "$FIRST_TARGET/sentinel" "later target failure leaves the first target unchanged"
assert_file "$SECOND_EXTERNAL/sentinel" "later target failure leaves external content unchanged"

# An identical legacy entry can be adopted, but a conflicting unowned entry
# must fail closed before any new payload is installed.
LEGACY_TARGET="$TMP/legacy-target"
mkdir -p "$LEGACY_TARGET"
cp -R "$REPO/skill-router" "$LEGACY_TARGET/skill-router"
PROFILE=core bash "$REPO/bootstrap/generate.sh" "$LEGACY_TARGET" >/dev/null
assert_file "$LEGACY_TARGET/.skill-commons-ownership-v1" "generate adopts an identical legacy entry"

# A complete pre-ledger root whose managed units are all byte-identical is
# safe to adopt by content, including removal of generated entries outside a
# newly narrowed profile. Unrelated entries must still survive.
IDENTICAL_LEGACY_ROOT="$TMP/identical-legacy-root"
PROFILE=all bash "$REPO/bootstrap/generate.sh" "$IDENTICAL_LEGACY_ROOT" >/dev/null
rm "$IDENTICAL_LEGACY_ROOT/.skill-commons-ownership-v1"
mkdir -p "$IDENTICAL_LEGACY_ROOT/foreign-skill"
printf 'foreign\n' > "$IDENTICAL_LEGACY_ROOT/foreign-skill/KEEP"
set +e
PROFILE=core bash "$REPO/bootstrap/generate.sh" "$IDENTICAL_LEGACY_ROOT" >/dev/null 2>&1
identical_legacy_rc=$?
set -e
assert_eq "0" "$identical_legacy_rc" "generate adopts a byte-identical pre-ledger root"
assert_file "$IDENTICAL_LEGACY_ROOT/.skill-commons-ownership-v1" "identical pre-ledger adoption publishes ownership"
if [ ! -e "$IDENTICAL_LEGACY_ROOT/prd-interview" ]; then
  TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: identical legacy profile shrink removes old generated skills"
else
  fail "identical legacy profile shrink left an old generated skill unowned"
fi
assert_file "$IDENTICAL_LEGACY_ROOT/foreign-skill/KEEP" "identical legacy profile shrink preserves foreign skills"

# Content equality for current paths is not enough to claim a retired
# historical name. That case remains fail-closed until migration is explicit.
RETIRED_WITHOUT_CONSENT="$TMP/retired-without-consent"
PROFILE=core bash "$REPO/bootstrap/generate.sh" "$RETIRED_WITHOUT_CONSENT" >/dev/null
rm "$RETIRED_WITHOUT_CONSENT/.skill-commons-ownership-v1"
mkdir -p "$RETIRED_WITHOUT_CONSENT/tdd"
printf 'historical or foreign\n' > "$RETIRED_WITHOUT_CONSENT/tdd/KEEP"
set +e
PROFILE=core bash "$REPO/bootstrap/generate.sh" "$RETIRED_WITHOUT_CONSENT" >/dev/null 2>&1
retired_without_consent_rc=$?
set -e
assert_neq "0" "$retired_without_consent_rc" "retired pre-ledger names require explicit consent"
assert_file "$RETIRED_WITHOUT_CONSENT/tdd/KEEP" "retired-name refusal preserves ambiguous content"

# Tagged v0.1-v0.4 fan-out had skill-router plus ARTIFACTS.md, but did not yet
# publish GATE-PACKAGE.md or shared scripts. The oldest tagged inventory also
# contains retired skills, which explicit migration must remove rather than
# silently leave discoverable and unowned.
LEGACY_DRIFT_TARGET="$TMP/legacy-drift-target"
V01_SKILLS=(
  brainstorming caveman-review codebase-understanding design-taste-frontend
  dev-kickoff domain-modeling finishing-a-development-branch grill-me
  grill-with-docs grilling implement markdown plan-sync ponytail prototype qa
  reducing-entropy requesting-code-review rollback security
  shared-skill-onboarder skill-creator skill-router spec
  subagent-driven-development sync-work systematic-debugging tdd to-prd
  verification-before-completion
)
mkdir -p "$LEGACY_DRIFT_TARGET/foreign-skill"
for legacy_skill in "${V01_SKILLS[@]}"; do
  mkdir -p "$LEGACY_DRIFT_TARGET/$legacy_skill"
  printf '%s\n' '---' "name: $legacy_skill" '---' 'old generated copy' > "$LEGACY_DRIFT_TARGET/$legacy_skill/SKILL.md"
done
printf 'old artifacts\n' > "$LEGACY_DRIFT_TARGET/ARTIFACTS.md"
printf 'old graph context\n' > "$LEGACY_DRIFT_TARGET/graph-context-check.md"
printf 'old sources\n' > "$LEGACY_DRIFT_TARGET/SOURCES.md"
printf 'old checklist\n' > "$LEGACY_DRIFT_TARGET/CHECKLIST-CONVENTION.md"
printf 'foreign\n' > "$LEGACY_DRIFT_TARGET/foreign-skill/KEEP"
legacy_before="$(shasum -a 256 "$LEGACY_DRIFT_TARGET/skill-router/SKILL.md" | awk '{print $1}')"
set +e
PROFILE=core bash "$REPO/bootstrap/generate.sh" "$LEGACY_DRIFT_TARGET" >/dev/null 2>&1
legacy_without_consent_rc=$?
set -e
assert_neq "0" "$legacy_without_consent_rc" "legacy drift requires explicit adoption"
assert_eq "$legacy_before" "$(shasum -a 256 "$LEGACY_DRIFT_TARGET/skill-router/SKILL.md" | awk '{print $1}')" "legacy refusal happens before mutation"
SKILL_COMMONS_ADOPT_LEGACY=1 PROFILE=core bash "$REPO/bootstrap/generate.sh" "$LEGACY_DRIFT_TARGET" >/dev/null
assert_file "$LEGACY_DRIFT_TARGET/.skill-commons-ownership-v1" "generate migrates a signed legacy fan-out root"
assert_file "$LEGACY_DRIFT_TARGET/foreign-skill/KEEP" "legacy migration preserves unrelated skills"
assert_eq "$(shasum -a 256 "$REPO/skill-router/SKILL.md" | awk '{print $1}')" "$(shasum -a 256 "$LEGACY_DRIFT_TARGET/skill-router/SKILL.md" | awk '{print $1}')" "legacy migration refreshes managed content"
for retired_skill in dev-kickoff finishing-a-development-branch grill-me grill-with-docs requesting-code-review rollback skill-creator tdd; do
  if [ ! -e "$LEGACY_DRIFT_TARGET/$retired_skill" ]; then
    TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: legacy migration removes historical $retired_skill output"
  else
    fail "legacy migration left historical $retired_skill output discoverable"
  fi
done

# Canonical generation targets may not overlap. Otherwise an outer target can
# replace a nested target created earlier in the same successful run.
OVERLAP_ROOT="$TMP/overlap-root"
OVERLAP_CHILD="$OVERLAP_ROOT/skill-router"
mkdir -p "$OVERLAP_ROOT"
printf 'overlap sentinel\n' > "$OVERLAP_ROOT/KEEP"
set +e
PROFILE=all bash "$REPO/bootstrap/generate.sh" "$OVERLAP_CHILD" "$OVERLAP_ROOT" >/dev/null 2>&1
overlap_rc=$?
set -e
assert_neq "0" "$overlap_rc" "generate rejects overlapping canonical targets"
assert_file "$OVERLAP_ROOT/KEEP" "overlap rejection happens before mutation"
if [ ! -e "$OVERLAP_CHILD" ]; then
  TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: overlap rejection leaves the nested target absent"
else
  fail "overlap rejection created the nested target"
fi

CONFLICT_TARGET="$TMP/conflict-target"
mkdir -p "$CONFLICT_TARGET/skill-router"
printf 'foreign skill-router\n' > "$CONFLICT_TARGET/skill-router/SKILL.md"
conflict_before="$(shasum -a 256 "$CONFLICT_TARGET/skill-router/SKILL.md")"
set +e
PROFILE=core bash "$REPO/bootstrap/generate.sh" "$CONFLICT_TARGET" >/dev/null 2>&1
conflict_rc=$?
set -e
conflict_after="$(shasum -a 256 "$CONFLICT_TARGET/skill-router/SKILL.md")"
assert_neq "0" "$conflict_rc" "generate rejects a conflicting unowned path"
assert_eq "$conflict_before" "$conflict_after" "conflict rejection preserves original content"
if [ ! -e "$CONFLICT_TARGET/.skill-commons-ownership-v1" ]; then
  TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: conflict rejection does not claim ownership"
else
  fail "conflict rejection wrote an ownership ledger"
fi

# A regular file at an intermediate container cannot be replaced after other
# payload units have already been installed.
FILE_PARENT_TARGET="$TMP/file-parent-target"
mkdir -p "$FILE_PARENT_TARGET"
printf 'not a directory\n' > "$FILE_PARENT_TARGET/scripts"
file_parent_before="$(shasum -a 256 "$FILE_PARENT_TARGET/scripts")"
set +e
PROFILE=all bash "$REPO/bootstrap/generate.sh" "$FILE_PARENT_TARGET" >/dev/null 2>&1
file_parent_rc=$?
set -e
assert_neq "0" "$file_parent_rc" "generate rejects a regular-file managed parent"
assert_eq "$file_parent_before" "$(shasum -a 256 "$FILE_PARENT_TARGET/scripts")" "managed-parent rejection happens before mutation"
if [ ! -e "$FILE_PARENT_TARGET/skill-router" ]; then
  TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: managed-parent failure leaves payload uninstalled"
else
  fail "managed-parent failure left a partial payload"
fi

# An existing ledger does not block adoption of a byte-identical path that was
# previously outside the selected profile.
PROFILE_GROW_TARGET="$TMP/profile-grow-target"
mkdir -p "$PROFILE_GROW_TARGET"
cp -R "$REPO/codebase-understanding" "$PROFILE_GROW_TARGET/codebase-understanding"
PROFILE=core bash "$REPO/bootstrap/generate.sh" "$PROFILE_GROW_TARGET" >/dev/null
PROFILE="core optional" bash "$REPO/bootstrap/generate.sh" "$PROFILE_GROW_TARGET" >/dev/null
assert_file "$PROFILE_GROW_TARGET/codebase-understanding/SKILL.md" "profile growth adopts an identical preserved skill"
if [ ! -e "$PROFILE_GROW_TARGET/codebase-understanding/codebase-understanding" ]; then
  TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: profile growth does not nest an adopted skill"
else
  fail "profile growth nested an adopted skill"
fi

# Ledger publication must not use a predictable PID-named file that can be
# pre-created as a symlink to an external victim.
LEDGER_TEMP_TARGET="$TMP/ledger-temp-target"
LEDGER_TEMP_VICTIM="$TMP/ledger-temp-victim"
mkdir -p "$LEDGER_TEMP_TARGET"
printf 'victim\n' > "$LEDGER_TEMP_VICTIM"
bash -c 'ln -s "$1" "$2/.skill-commons-ownership-v1.tmp.$$"; exec env PROFILE=all bash "$3" "$2"' \
  _ "$LEDGER_TEMP_VICTIM" "$LEDGER_TEMP_TARGET" "$REPO/bootstrap/generate.sh" >/dev/null
assert_eq "victim" "$(cat "$LEDGER_TEMP_VICTIM")" "exclusive ledger temp creation preserves an external victim"
if [ -f "$LEDGER_TEMP_TARGET/.skill-commons-ownership-v1" ] && [ ! -L "$LEDGER_TEMP_TARGET/.skill-commons-ownership-v1" ]; then
  TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: published ownership ledger is a regular file"
else
  fail "published ownership ledger is not a regular file"
fi

# Corrupt ownership data cannot be used as a deletion primitive.
CORRUPT_TARGET="$TMP/corrupt-target"
OUTSIDE_SENTINEL="$TMP/outside-sentinel"
mkdir -p "$CORRUPT_TARGET"
printf 'outside\n' > "$OUTSIDE_SENTINEL"
printf '%s\n' 'skill-commons-ownership-v1' $'F\t../outside-sentinel' > "$CORRUPT_TARGET/.skill-commons-ownership-v1"
set +e
PROFILE=all bash "$REPO/bootstrap/generate.sh" "$CORRUPT_TARGET" >/dev/null 2>&1
corrupt_rc=$?
set -e
assert_neq "0" "$corrupt_rc" "generate rejects an unsafe ownership ledger"
assert_file "$OUTSIDE_SENTINEL" "unsafe ledger rejection preserves outside content"

BAD_SCHEMA_TARGET="$TMP/bad-schema-target"
mkdir -p "$BAD_SCHEMA_TARGET"
printf '%s\n' 'skill-commons-ownership-v999' > "$BAD_SCHEMA_TARGET/.skill-commons-ownership-v1"
set +e
PROFILE=all bash "$REPO/bootstrap/generate.sh" "$BAD_SCHEMA_TARGET" >/dev/null 2>&1
bad_schema_rc=$?
set -e
assert_neq "0" "$bad_schema_rc" "generate rejects an unknown ownership schema"

ABSOLUTE_LEDGER_TARGET="$TMP/absolute-ledger-target"
mkdir -p "$ABSOLUTE_LEDGER_TARGET"
printf '%s\n' 'skill-commons-ownership-v1' $'F\t/tmp/outside' > "$ABSOLUTE_LEDGER_TARGET/.skill-commons-ownership-v1"
set +e
PROFILE=all bash "$REPO/bootstrap/generate.sh" "$ABSOLUTE_LEDGER_TARGET" >/dev/null 2>&1
absolute_ledger_rc=$?
set -e
assert_neq "0" "$absolute_ledger_rc" "generate rejects an absolute ownership path"

# Ledger validation for every target also finishes before the first target is
# changed, not only base path validation.
LEDGER_FIRST_TARGET="$TMP/ledger-first-target"
LEDGER_SECOND_TARGET="$TMP/ledger-second-target"
mkdir -p "$LEDGER_FIRST_TARGET" "$LEDGER_SECOND_TARGET"
printf 'first\n' > "$LEDGER_FIRST_TARGET/sentinel"
printf '%s\n' 'skill-commons-ownership-v1' $'D\t../escape' > "$LEDGER_SECOND_TARGET/.skill-commons-ownership-v1"
set +e
PROFILE=all bash "$REPO/bootstrap/generate.sh" "$LEDGER_FIRST_TARGET" "$LEDGER_SECOND_TARGET" >/dev/null 2>&1
ledger_multi_rc=$?
set -e
assert_neq "0" "$ledger_multi_rc" "generate preflights every ledger before mutation"
assert_file "$LEDGER_FIRST_TARGET/sentinel" "later ledger failure leaves the first target unchanged"

# A syntactically safe ledger record remains deletion authority after the
# corresponding source skill is removed or renamed.
UNKNOWN_LEDGER_TARGET="$TMP/unknown-ledger-target"
mkdir -p "$UNKNOWN_LEDGER_TARGET/retired-skill"
printf 'retired\n' > "$UNKNOWN_LEDGER_TARGET/retired-skill/OLD"
printf '%s\n' 'skill-commons-ownership-v1' $'D\tretired-skill' > "$UNKNOWN_LEDGER_TARGET/.skill-commons-ownership-v1"
PROFILE=all bash "$REPO/bootstrap/generate.sh" "$UNKNOWN_LEDGER_TARGET" >/dev/null
if [ ! -e "$UNKNOWN_LEDGER_TARGET/retired-skill" ]; then
  TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: historical ledger ownership removes retired managed output"
else
  fail "generate left retired managed output"
fi

# An active target lock serializes preflight through publication.
LOCK_TARGET="$TMP/lock-target"
LOCK_TMP="$TMP/locks"
mkdir -p "$LOCK_TARGET" "$LOCK_TMP"
printf 'locked\n' > "$LOCK_TARGET/sentinel"
canonical_lock_target="$(cd "$LOCK_TARGET" && pwd -P)"
lock_path_a="$(TMPDIR="$TMP/lock-a" ownership_lock_path "$canonical_lock_target")"
lock_path_b="$(TMPDIR="$TMP/lock-b" ownership_lock_path "$canonical_lock_target")"
assert_eq "$lock_path_a" "$lock_path_b" "target lock identity is independent of TMPDIR"
lock_dir="$lock_path_a"
mkdir "$lock_dir"
set +e
locked_output="$(TMPDIR="$LOCK_TMP" PROFILE=all /bin/bash "$REPO/bootstrap/generate.sh" "$LOCK_TARGET" 2>&1)"
locked_rc=$?
set -e
assert_neq "0" "$locked_rc" "generate rejects a concurrently locked target"
assert_not_contains "$locked_output" "unbound variable" "Bash 3.2 lock loser cleanup preserves the real error"
assert_file "$LOCK_TARGET/sentinel" "lock contention leaves the target unchanged"
rmdir "$lock_dir"
if find "$LOCK_TMP" -mindepth 1 -maxdepth 1 -type d | grep -q .; then
  fail "Bash 3.2 lock loser cleanup removes staged payloads"
else
  TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: Bash 3.2 lock loser cleanup removes staged payloads"
fi

finish
