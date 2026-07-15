#!/usr/bin/env bash
# Profile model: one delivery mode plus zero-or-more capability packs, with
# list integrity, dependency/conflict validation, and safe fan-out defaults.
set -u
REPO="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
. "$REPO/tests/bootstrap/lib/assert.sh"

bash -n "$REPO/bootstrap/generate.sh" || fail "generate.sh syntax"
bash -n "$REPO/bootstrap/lib/manifest.sh" || fail "manifest.sh syntax"

# Active skills: top-level dirs with SKILL.md minus generate.sh's skip list
# (computed dynamically so the union check tracks skill additions/removals).
active_names() {
  local d name
  for d in "$REPO"/*/; do
    name="$(basename "$d")"
    case "$name" in _archive|_shared|docs|bootstrap|scripts|tests|profiles|node_modules) continue;; esac
    [ -f "$d/SKILL.md" ] && printf '%s\n' "$name"
  done | sort
}

# Expand a profile file: skill names, '#' comments, blank lines, '@<profile>' includes.
resolve() {
  local file="$REPO/profiles/$1" line
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%%#*}"
    line="$(printf '%s' "$line" | tr -d '[:space:]')"
    [ -z "$line" ] && continue
    case "$line" in
      @*) resolve "${line#@}";;
      *) printf '%s\n' "$line";;
    esac
  done < "$file"
}

# Names listed directly in a profile file (overlay only, no @include expansion).
overlay() {
  sed 's/#.*//' "$REPO/profiles/$1" | tr -d ' \t' | grep -vE '^(@.*)?$'
}

check_generated_markdown_links() {
  local generated_root="$1" label="$2"
  local output rc
  set +e
  output="$(python3 - "$generated_root" <<'PY'
from pathlib import Path
import re
import sys

root = Path(sys.argv[1]).resolve()
errors = []
for md in root.rglob("*.md"):
    in_fence = False
    for line in md.read_text(errors="replace").splitlines():
        stripped = line.lstrip()
        if stripped.startswith((chr(96) * 3, "~~~")):
            in_fence = not in_fence
            continue
        if in_fence:
            continue
        for match in re.finditer(r"\[[^\]]+\]\(([^)]+\.md(?:#[^)]+)?)\)", line):
            href = match.group(1).split("#", 1)[0]
            if "://" in href or href.startswith("mailto:"):
                continue
            target = (md.parent / href).resolve()
            try:
                target.relative_to(root)
            except ValueError:
                continue
            if not target.exists():
                errors.append(f"{md.relative_to(root)} -> {href}")

if errors:
    print("\n".join(errors))
    sys.exit(1)
PY
  )"
  rc=$?
  set -e
  if [ "$rc" -eq 0 ]; then
    TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: $label generated markdown links resolve"
  else
    echo "$output"
    fail "$label generated markdown links resolve"
  fi
}

# --- 1) declarative model and profile files are complete and truthful ---
assert_file "$REPO/profiles.json" "profiles.json exists"
assert_file "$REPO/docs/profile-platform-support.md" "profile/platform support matrix exists"
for p in core team-sprint personal optional frontend; do
  assert_file "$REPO/profiles/$p" "profiles/$p exists"
done
missing=""
for p in core team-sprint personal optional frontend; do
  while IFS= read -r name; do
    [ -f "$REPO/$name/SKILL.md" ] || missing="$missing $p:$name"
  done <<EOF
$(resolve "$p")
EOF
done
assert_eq "" "$missing" "every profile entry maps to a top-level skill with SKILL.md"

core="$(resolve core | sort)"
team_overlay="$(overlay team-sprint | sort)"
personal_overlay="$(overlay personal | sort)"
optional_overlay="$(overlay optional | sort)"
frontend_overlay="$(overlay frontend | sort)"
expected_core="$(printf '%s\n' \
  implement plan-sync security skill-router sync-work systematic-debugging \
  verification-before-completion | tr ' ' '\n' | sort)"
expected_optional="$(printf '%s\n' \
  brainstorming caveman-review codebase-understanding grilling humanizer markdown \
  reducing-entropy shared-skill-onboarder subagent-driven-development to-prd | tr ' ' '\n' | sort)"
assert_eq "$expected_core" "$core" "core is the released v0.9.0 seven-owner set"
assert_eq "$expected_optional" "$optional_overlay" "optional preserves personal discovery PRD review and onboarding"
assert_eq "7" "$(printf '%s\n' "$core" | sed '/^$/d' | wc -l | tr -d ' ')" "core has seven owners"
assert_eq "10" "$(printf '%s\n' "$optional_overlay" | sed '/^$/d' | wc -l | tr -d ' ')" "optional has ten capabilities"

router_text="$(cat "$REPO/skill-router/SKILL.md")"
assert_contains "$router_text" "七個 core owner" "router describes the T06 seven-owner core"
assert_contains "$router_text" "CAPABILITY_PACKS=optional" "router names the explicit optional-pack adoption route"
for optional_owner in brainstorming grilling to-prd caveman-review shared-skill-onboarder; do
  assert_contains "$router_text" "$optional_owner" "router preserves optional route for $optional_owner"
done
router_bytes="$(wc -c < "$REPO/skill-router/SKILL.md" | tr -d ' ')"
micro_bytes="$((router_bytes + $(wc -c < "$REPO/implement/SKILL.md") + $(wc -c < "$REPO/verification-before-completion/SKILL.md")))"
if [ "$router_bytes" -lt 6747 ]; then
  TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: direct factual Router payload is below 6747 bytes ($router_bytes)"
else
  fail "direct factual Router payload must be below 6747 bytes (actual=$router_bytes)"
fi
if [ "$micro_bytes" -lt 17411 ]; then
  TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: Router + Implement + Verification is below 17411 bytes ($micro_bytes)"
else
  fail "Router + Implement + Verification must be below 17411 bytes (actual=$micro_bytes)"
fi

profile_model_conformance() {
python3 - "$REPO" "$1" "$2" <<'PY'
import json
import sys
from pathlib import Path

root = Path(sys.argv[1])
model = json.loads(Path(sys.argv[2]).read_text(encoding="utf-8"))
registry = json.loads(Path(sys.argv[3]).read_text(encoding="utf-8"))
errors = []
if model.get("schema_version") != "skill-commons/profiles/v1":
    errors.append("unexpected profiles schema")
if model.get("base_profile") != "core":
    errors.append("base profile must be core")

modes = model.get("delivery_modes", {})
packs = model.get("capability_packs", {})
if set(modes) != {"personal", "team-sprint"}:
    errors.append(f"delivery mode set mismatch: {sorted(modes)}")
if set(packs) != {"frontend", "optional"}:
    errors.append(f"capability pack set mismatch: {sorted(packs)}")
for name, record in {**modes, **packs}.items():
    profile_file = record.get("profile_file")
    if profile_file != f"profiles/{name}":
        errors.append(f"{name} profile_file mismatch")
    if not (root / str(profile_file)).is_file():
        errors.append(f"{name} profile file is missing")
if model.get("contract_source") != "protocol-registry.json#/profiles":
    errors.append("profile dependency contract source mismatch")

compat = model.get("compatibility", {})
if compat.get("implicit_default") is not None:
    errors.append("implicit profile default must be null")
if compat.get("maintainer_all_token") != "all":
    errors.append("maintainer all token mismatch")

platforms = model.get("platforms", {})
expected = {
    "claude-code": (True, "skill-fan-out"),
    "codex": (True, "skill-fan-out"),
    "cursor": (False, "rule-and-agents"),
}
if set(platforms) != set(expected):
    errors.append(f"platform set mismatch: {sorted(platforms)}")
for name, (fan_out, adapter) in expected.items():
    record = platforms.get(name, {})
    if record.get("skill_fan_out") is not fan_out or record.get("adapter") != adapter:
        errors.append(f"{name} capability mismatch")

contracts = registry.get("profiles", {})
expected_contracts = {
    "core": ("base", [], []),
    "personal": ("delivery-mode", ["core"], ["team-sprint"]),
    "team-sprint": ("delivery-mode", ["core"], ["personal"]),
    "frontend": ("capability-pack", ["core"], []),
    "optional": ("capability-pack", ["core"], []),
}
if set(contracts) != set(expected_contracts):
    errors.append(f"protocol profile set mismatch: {sorted(contracts)}")
for name, (kind, requires, conflicts) in expected_contracts.items():
    record = contracts.get(name, {})
    actual = (record.get("kind"), record.get("requires"), record.get("conflicts"))
    if actual != (kind, requires, conflicts):
        errors.append(f"{name} protocol profile contract mismatch")

if errors:
    print("\n".join(errors))
    raise SystemExit(1)
print("profile model conformance ok")
PY
}

if profile_model_conformance "$REPO/profiles.json" "$REPO/protocol-registry.json"
then
  TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: profile model is declarative and host capabilities are explicit"
else
  fail "profile model is declarative and host capabilities are explicit"
fi

python3 - "$REPO/profiles.json" "$TMP/extra-platform.json" <<'PY'
import copy
import json
import sys
from pathlib import Path

model = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
mutant = copy.deepcopy(model)
mutant["platforms"]["extra-host"] = {
    "adapter": "skill-fan-out",
    "skill_fan_out": True,
}
Path(sys.argv[2]).write_text(json.dumps(mutant), encoding="utf-8")
PY
if profile_model_conformance "$TMP/extra-platform.json" "$REPO/protocol-registry.json" >/dev/null 2>&1; then
  fail "profile model rejects undeclared extra platform names"
else
  TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: profile model rejects undeclared extra platform names"
fi

# --- 2) base, delivery overlays, and capability packs are exclusive and cover
# every workflow skill. Frontend is opt-in for relevance, not bundle size. ---
# skill-creator intentionally remains a top-level maintainer tool without fan-out. ---
dups="$(printf '%s\n%s\n%s\n%s\n%s\n' "$core" "$team_overlay" "$personal_overlay" "$optional_overlay" "$frontend_overlay" | sort | uniq -d)"
assert_eq "" "$dups" "base / delivery / capability sets are mutually exclusive"
union="$(printf '%s\n%s\n%s\n%s\n%s\n' "$core" "$team_overlay" "$personal_overlay" "$optional_overlay" "$frontend_overlay" | sed '/^$/d' | sort)"
profiled_active="$(active_names | grep -vx 'skill-creator')"
assert_eq "$profiled_active" "$union" "profiles cover all active workflow skills except maintainer-only skill-creator"
if printf '%s\n' "$union" | grep -qx 'skill-creator'; then
  fail "skill-creator is absent from consuming profiles"
else
  TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: skill-creator is absent from consuming profiles"
fi
if printf '%s\n' "$personal_overlay" | grep -qx 'design-taste-frontend'; then
  fail "generic personal mode excludes design-taste-frontend"
else
  TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: generic personal mode excludes design-taste-frontend"
fi
assert_eq "design-taste-frontend" "$frontend_overlay" "frontend capability owns design-taste-frontend"

# --- 3) preferred explicit interface is one delivery mode plus capability packs ---
for p in team-sprint personal; do
  mkdir -p "$TMP/$p"
  DELIVERY_MODE="$p" bash "$REPO/bootstrap/generate.sh" "$TMP/$p" >/dev/null
  generated="$(find "$TMP/$p" -mindepth 2 -maxdepth 2 -type f -name SKILL.md -print |
    sed "s#^$TMP/$p/##;s#/SKILL.md##" | sort)"
  assert_eq "$(resolve "$p" | sort -u)" "$generated" "DELIVERY_MODE=$p fans exactly the $p list"
  check_generated_markdown_links "$TMP/$p" "DELIVERY_MODE=$p"
done

# Zero capability packs is valid; multiple packs compose with exactly one mode.
mkdir -p "$TMP/personal-optional"
DELIVERY_MODE=personal CAPABILITY_PACKS="optional frontend" \
  bash "$REPO/bootstrap/generate.sh" "$TMP/personal-optional" >/dev/null
generated_combined="$(find "$TMP/personal-optional" -mindepth 2 -maxdepth 2 -type f -name SKILL.md -print |
  sed "s#^$TMP/personal-optional/##;s#/SKILL.md##" | sort)"
expected_combined="$(printf '%s\n%s\n%s\n' "$(resolve personal)" "$(resolve optional)" "$(resolve frontend)" | sort -u)"
assert_eq "$expected_combined" "$generated_combined" "delivery mode composes with zero-or-more capability packs"
check_generated_markdown_links "$TMP/personal-optional" "personal + optional + frontend"

# --- 4) omitted selection fails; all-skills remains explicit maintainer compatibility ---
mkdir -p "$TMP/implicit"
if bash "$REPO/bootstrap/generate.sh" "$TMP/implicit" >"$TMP/implicit.out" 2>"$TMP/implicit.err"; then
  fail "generate rejects omitted delivery selection"
else
  TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: generate rejects omitted delivery selection"
fi
assert_eq "" "$(find "$TMP/implicit" -mindepth 1 -print -quit)" "omitted selection fails before target mutation"

mkdir -p "$TMP/all"
PROFILE=all bash "$REPO/bootstrap/generate.sh" "$TMP/all" >/dev/null
generated_all="$(find "$TMP/all" -mindepth 2 -maxdepth 2 -type f -name SKILL.md -print |
  sed "s#^$TMP/all/##;s#/SKILL.md##" | sort)"
assert_eq "$(active_names | grep -vx 'skill-creator')" "$generated_all" "PROFILE=all explicitly fans maintainer compatibility set"
assert_file "$TMP/all/scripts/manifest-stack.sh" "fan-out includes shared runtime helpers"
check_generated_markdown_links "$TMP/all" "explicit PROFILE=all"

# Legacy non-empty PROFILE remains a migration path, but it must still express
# one delivery mode; capability-only and conflicting compositions fail closed.
mkdir -p "$TMP/legacy"
PROFILE="personal optional" bash "$REPO/bootstrap/generate.sh" "$TMP/legacy" >/dev/null
legacy_generated="$(find "$TMP/legacy" -mindepth 2 -maxdepth 2 -type f -name SKILL.md -print |
  sed "s#^$TMP/legacy/##;s#/SKILL.md##" | sort)"
assert_eq "$(printf '%s\n%s\n' "$(resolve personal)" "$(resolve optional)" | sort -u)" "$legacy_generated" "legacy PROFILE composition remains compatible"
if PROFILE=optional bash "$REPO/bootstrap/generate.sh" "$TMP/invalid-capability-only" >/dev/null 2>&1; then
  fail "legacy capability-only PROFILE is rejected"
else
  TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: legacy capability-only PROFILE is rejected"
fi
if PROFILE="personal team-sprint" bash "$REPO/bootstrap/generate.sh" "$TMP/invalid-conflict" >/dev/null 2>&1; then
  fail "conflicting delivery modes are rejected"
else
  TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: conflicting delivery modes are rejected"
fi
if PROFILE=personal DELIVERY_MODE=personal bash "$REPO/bootstrap/generate.sh" "$TMP/invalid-mixed-interface" >/dev/null 2>&1; then
  fail "legacy and explicit profile interfaces cannot be mixed"
else
  TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: legacy and explicit profile interfaces cannot be mixed"
fi
if CAPABILITY_PACKS=optional bash "$REPO/bootstrap/generate.sh" "$TMP/invalid-pack-only" >/dev/null 2>&1; then
  fail "capability packs require a delivery mode"
else
  TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: capability packs require a delivery mode"
fi
if DELIVERY_MODE=personal CAPABILITY_PACKS="optional optional" \
  bash "$REPO/bootstrap/generate.sh" "$TMP/invalid-duplicate-pack" >/dev/null 2>&1; then
  fail "duplicate capability packs are rejected"
else
  TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: duplicate capability packs are rejected"
fi
if DELIVERY_MODE=personal CAPABILITY_PACKS=team-sprint \
  bash "$REPO/bootstrap/generate.sh" "$TMP/invalid-pack-kind" >/dev/null 2>&1; then
  fail "delivery modes cannot be selected as capability packs"
else
  TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: delivery modes cannot be selected as capability packs"
fi

# --- 5) stale/typo entry fails hard (tmp source tree; the repo stays untouched) ---
FAKE="$TMP/fake-src"
mkdir -p "$FAKE/real-skill" "$FAKE/profiles" "$TMP/broken-out"
printf -- '---\nname: real-skill\n---\n' > "$FAKE/real-skill/SKILL.md"
printf 'real-skill\nno-such-skill\n' > "$FAKE/profiles/broken"
if SKILLS_SRC="$FAKE" PROFILE="core broken" bash "$REPO/bootstrap/generate.sh" "$TMP/broken-out" >/dev/null 2>&1; then
  fail "generate.sh fails on a profile entry without a skill folder"
else
  TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: generate.sh fails on a profile entry without a skill folder"
fi
if SKILLS_SRC="$FAKE" DELIVERY_MODE=no-such-profile bash "$REPO/bootstrap/generate.sh" "$TMP/broken-out" >/dev/null 2>&1; then
  fail "generate.sh fails on an unknown profile name"
else
  TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: generate.sh fails on an unknown profile name"
fi

# --- 6) manifest reads the explicit model and retains legacy PROFILE parsing ---
. "$REPO/bootstrap/lib/manifest.sh"
cat > "$TMP/manifest.md" <<'EOF'
## skill-commons bootstrap
- platforms: claude-code
- delivery_mode: team-sprint
- capability_packs: optional, frontend
EOF
assert_eq "team-sprint" "$(get_delivery_mode "$TMP/manifest.md")" "manifest reads delivery mode"
assert_eq "optional frontend" "$(get_capability_packs "$TMP/manifest.md")" "manifest reads capability packs"
printf -- '- platforms: claude-code\n' > "$TMP/manifest-noprofile.md"
assert_eq "" "$(get_profile "$TMP/manifest-noprofile.md")" "get_profile is empty when key absent"
assert_eq "" "$(get_delivery_mode "$TMP/manifest-noprofile.md")" "delivery mode is empty when omitted"
printf '%s\n' '## skill-commons bootstrap' '- profile: personal optional' > "$TMP/manifest-legacy.md"
assert_eq "personal optional" "$(get_profile "$TMP/manifest-legacy.md")" "legacy profile remains readable"
template="$(cat "$REPO/shared-skill-onboarder/templates/project-manifest.md")"
assert_contains "$template" "delivery_mode: personal" "fresh manifest has an explicit safe delivery mode"

NO_SELECTION="$TMP/no-selection-project"
mkdir -p "$NO_SELECTION/.agent"
printf '%s\n' '## skill-commons bootstrap' '- platforms: codex' > "$NO_SELECTION/.agent/project-manifest.md"
if bash "$REPO/bootstrap/onboard.sh" "$NO_SELECTION" >/dev/null 2>&1; then
  fail "onboard rejects a manifest without delivery selection"
else
  TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: onboard rejects a manifest without delivery selection"
fi
if [ -e "$NO_SELECTION/AGENTS.md" ] || [ -e "$NO_SELECTION/.codex/skills" ]; then
  fail "missing delivery selection fails before platform fan-out"
else
  TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: missing delivery selection fails before platform fan-out"
fi

support="$(cat "$REPO/docs/profile-platform-support.md" 2>/dev/null || true)"
assert_contains "$support" "current personal = 7" "support matrix records current personal membership"
assert_contains "$support" "current team-sprint = 12" "support matrix records current team membership"
assert_contains "$support" "current optional = 10" "support matrix records current optional membership"
assert_contains "$support" "relevance" "frontend move is justified by relevance"
assert_contains "$support" "Cursor" "support matrix documents Cursor"
assert_contains "$support" "rule + AGENTS adapter" "Cursor support is not called skill fan-out"

for entrypoint in README.md README.en.md; do
  entrypoint_text="$(cat "$REPO/$entrypoint")"
  assert_contains "$entrypoint_text" "v0.9.0" "$entrypoint keeps the concrete current release pin"
  assert_contains "$entrypoint_text" "v0.7.1" "$entrypoint keeps the legacy compatibility pin"
  assert_not_contains "$entrypoint_text" "Unreleased next-major" "$entrypoint removes pre-release wording"
  assert_contains "$entrypoint_text" "docs/profile-platform-support.md" "$entrypoint links authoritative profile support"
done
for public_contract in INDEX.md bootstrap/README.md docs/profile-platform-support.md; do
  contract_text="$(cat "$REPO/$public_contract")"
  assert_contains "$contract_text" "CAPABILITY_PACKS=optional" "$public_contract documents optional-pack adoption"
  assert_contains "$contract_text" "v0.9.0" "$public_contract documents the current release pin"
  assert_contains "$contract_text" "v0.7.1" "$public_contract documents the concrete legacy-core pin"
  assert_not_contains "$contract_text" "current next-major candidate" "$public_contract removes candidate wording after release"
done
for migration_contract in \
  INDEX.md \
  bootstrap/README.md \
  docs/profile-platform-support.md; do
  migration_text="$(cat "$REPO/$migration_contract")"
  assert_contains "$migration_text" "v0.9.0" "$migration_contract names the released boundary"
  assert_contains "$migration_text" "7-owner core" "$migration_contract names the released seven-owner core"
  assert_not_contains "$migration_text" "current next-major candidate" "$migration_contract removes candidate wording after release"
  assert_not_contains "$migration_text" "non-dispatch compatibility shell" "$migration_contract removes the T05 compatibility-shell wording"
  assert_not_contains "$migration_text" "finishing-a-development-branch" "$migration_contract removes the retired owner name"
done
if [ -f "$REPO/docs/shared-skill-onboarding-checklist.md" ]; then
  migration_text="$(cat "$REPO/docs/shared-skill-onboarding-checklist.md")"
  assert_contains "$migration_text" "v0.9.0" "private onboarding checklist names the released boundary"
  assert_contains "$migration_text" "7-owner core" "private onboarding checklist names the released seven-owner core"
  assert_not_contains "$migration_text" "current next-major candidate" "private onboarding checklist removes candidate wording after release"
  assert_not_contains "$migration_text" "non-dispatch compatibility shell" "private onboarding checklist removes the T05 compatibility-shell wording"
  assert_not_contains "$migration_text" "finishing-a-development-branch" "private onboarding checklist removes the retired owner name"
else
  TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: private onboarding checklist is absent from the public payload"
fi
template_text="$(cat "$REPO/shared-skill-onboarder/templates/project-manifest.md")"
assert_contains "$template_text" "CAPABILITY_PACKS=optional" "fresh manifest explains optional personal capabilities"

prd_template_text="$(cat "$REPO/prd-template.md")"
assert_not_contains "$prd_template_text" "every profile (to-prd / personal)" "PRD template drops the pre-T04 every-profile claim"
assert_contains "$prd_template_text" "optional to-prd" "PRD template identifies the optional personal/refactor producer"
assert_contains "$prd_template_text" "team-sprint prd-interview" "PRD template identifies the formal team producer"

readme_text="$(cat "$REPO/README.md")"
if python3 - "$REPO/README.md" <<'PY'
from pathlib import Path
import sys

text = Path(sys.argv[1]).read_text(errors="replace")
start = text.find("## Quick Start")
end = text.find("## 安裝完成後", start)
section = text[start:end]
selection = section.find("`optional` 加到 `capability_packs`")
onboard = section.find("bootstrap/onboard.sh")
if start < 0 or end < 0 or selection < 0 or onboard < 0 or selection >= onboard:
    raise SystemExit("README Quick Start must select optional capability before onboarding")
PY
then
  TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: Quick Start sequences optional onboarding selection before generation"
else
  fail "Quick Start sequences optional onboarding selection before generation"
fi
assert_contains "$readme_text" "未選擇 optional pack 時，不要要求 agent 讀" "Quick Start does not dispatch an uninstalled onboarder"

if [ -f "$REPO/docs/shared-skill-onboarding-checklist.md" ]; then
  onboarding_checklist="$(cat "$REPO/docs/shared-skill-onboarding-checklist.md")"
  assert_contains "$onboarding_checklist" "v0.9.0 consuming path" "onboarding checklist names the current consuming path"
  assert_contains "$onboarding_checklist" "capability_packs: optional" "onboarding checklist selects optional before onboarding"
  assert_contains "$onboarding_checklist" "manual top-level-source maintainer path" "onboarding checklist distinguishes the manual maintainer path"
fi

bridge_text="$(cat "$REPO/docs/skill-commons-submodule-bridge.md")"
assert_contains "$bridge_text" "## Install v0.9.0" "submodule bridge installs the current release"
assert_contains "$bridge_text" "checkout v0.9.0" "submodule bridge preserves the concrete current checkout"
assert_contains "$bridge_text" "v0.7.1" "submodule bridge explains the legacy compatibility pin"
assert_not_contains "$bridge_text" "next-major" "submodule bridge removes pre-release wording"
assert_contains "$bridge_text" "capability_packs: optional" "submodule bridge conditions v0.9.0 onboarder use"

# --- 6b) Stack capabilities are strict booleans and default false ---
cat >> "$TMP/manifest.md" <<'EOF'
## Stack
- has_ui: true
- has_api: false
- typed_contracts: true
- has_e2e: false
EOF
assert_eq "true" "$(get_stack_capability "$TMP/manifest.md" has_ui)" "manifest reads enabled capability"
assert_eq "false" "$(get_stack_capability "$TMP/manifest.md" has_api)" "manifest reads disabled capability"
assert_eq "false" "$(get_stack_capability "$TMP/manifest.md" not_declared)" "missing capability defaults false"
printf '%s\n' '## Stack' '- has_ui: maybe' > "$TMP/manifest-invalid-capability.md"
if get_stack_capability "$TMP/manifest-invalid-capability.md" has_ui >/dev/null 2>&1; then
  fail "invalid capability values fail closed"
else
  TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: invalid capability values fail closed"
fi

# --- 7) skill-router's documented "personal profile 硬規則" exclusion list
# must never actually appear in the expanded personal bundle (docs/reality drift guard) ---
router_excluded="$(awk '/personal profile 硬規則/{p=1} p{print} p && /不在 bundle 內/{exit}' "$REPO/skill-router/SKILL.md" |
  grep -oE '`[a-z0-9-]+`' | tr -d '`' | sort -u)"
personal_expanded="$(resolve personal | sort -u)"
drift=""
for name in $router_excluded; do
  if printf '%s\n' "$personal_expanded" | grep -qx "$name"; then
    drift="$drift $name"
  fi
done
if [ -z "$router_excluded" ]; then
  fail "skill-router personal-profile exclusion list is empty or unparsable (test regex needs updating)"
elif [ -n "$drift" ]; then
  fail "skill-router says personal profile excludes:$drift -- but profiles/personal actually includes them"
else
  TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: skill-router personal-profile exclusions match profiles/personal reality"
fi

finish
