#!/usr/bin/env bash
# Profile split (core + team-sprint/personal overlays): list integrity,
# set exclusivity/coverage, and generate.sh PROFILE filtering.
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

# --- 1) profile files exist; every entry maps to a real skill folder ---
for p in core team-sprint personal optional; do
  assert_file "$REPO/profiles/$p" "profiles/$p exists"
done
missing=""
for p in core team-sprint personal optional; do
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
assert_contains "$optional_overlay" "humanizer" "optional profile includes humanizer"

# --- 2) consuming profiles are exclusive and cover every workflow skill.
# skill-creator intentionally remains a top-level maintainer tool without fan-out. ---
dups="$(printf '%s\n%s\n%s\n%s\n' "$core" "$team_overlay" "$personal_overlay" "$optional_overlay" | sort | uniq -d)"
assert_eq "" "$dups" "core / team / personal / optional sets are mutually exclusive"
union="$(printf '%s\n%s\n%s\n%s\n' "$core" "$team_overlay" "$personal_overlay" "$optional_overlay" | sort)"
profiled_active="$(active_names | grep -vx 'skill-creator')"
assert_eq "$profiled_active" "$union" "profiles cover all active workflow skills except maintainer-only skill-creator"
if printf '%s\n' "$union" | grep -qx 'skill-creator'; then
  fail "skill-creator is absent from consuming profiles"
else
  TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: skill-creator is absent from consuming profiles"
fi

# --- 3) PROFILE fan-out matches the resolved list exactly ---
for p in team-sprint personal optional; do
  mkdir -p "$TMP/$p"
  PROFILE="$p" bash "$REPO/bootstrap/generate.sh" "$TMP/$p" >/dev/null
  generated="$(find "$TMP/$p" -mindepth 2 -maxdepth 2 -type f -name SKILL.md -print |
    sed "s#^$TMP/$p/##;s#/SKILL.md##" | sort)"
  assert_eq "$(resolve "$p" | sort -u)" "$generated" "PROFILE=$p fans exactly the $p list"
  check_generated_markdown_links "$TMP/$p" "PROFILE=$p"
done

# Optional utilities must compose with a delivery profile instead of replacing it.
mkdir -p "$TMP/personal-optional"
PROFILE="personal optional" bash "$REPO/bootstrap/generate.sh" "$TMP/personal-optional" >/dev/null
generated_combined="$(find "$TMP/personal-optional" -mindepth 2 -maxdepth 2 -type f -name SKILL.md -print |
  sed "s#^$TMP/personal-optional/##;s#/SKILL.md##" | sort)"
expected_combined="$(printf '%s\n%s\n' "$(resolve personal)" "$(resolve optional)" | sort -u)"
assert_eq "$expected_combined" "$generated_combined" "PROFILE supports delivery + optional profile composition"
check_generated_markdown_links "$TMP/personal-optional" "PROFILE=personal optional"

# --- 4) no PROFILE fans all workflow skills, excluding maintainer-only tools ---
mkdir -p "$TMP/all"
bash "$REPO/bootstrap/generate.sh" "$TMP/all" >/dev/null
generated_all="$(find "$TMP/all" -mindepth 2 -maxdepth 2 -type f -name SKILL.md -print |
  sed "s#^$TMP/all/##;s#/SKILL.md##" | sort)"
assert_eq "$(active_names | grep -vx 'skill-creator')" "$generated_all" "without PROFILE, generate excludes maintainer-only skill-creator"
assert_file "$TMP/all/scripts/manifest-stack.sh" "fan-out includes shared runtime helpers"
check_generated_markdown_links "$TMP/all" "PROFILE=all"

# --- 5) stale/typo entry fails hard (tmp source tree; the repo stays untouched) ---
FAKE="$TMP/fake-src"
mkdir -p "$FAKE/real-skill" "$FAKE/profiles" "$TMP/broken-out"
printf -- '---\nname: real-skill\n---\n' > "$FAKE/real-skill/SKILL.md"
printf 'real-skill\nno-such-skill\n' > "$FAKE/profiles/broken"
if SKILLS_SRC="$FAKE" PROFILE=broken bash "$REPO/bootstrap/generate.sh" "$TMP/broken-out" >/dev/null 2>&1; then
  fail "generate.sh fails on a profile entry without a skill folder"
else
  TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: generate.sh fails on a profile entry without a skill folder"
fi
if SKILLS_SRC="$FAKE" PROFILE=no-such-profile bash "$REPO/bootstrap/generate.sh" "$TMP/broken-out" >/dev/null 2>&1; then
  fail "generate.sh fails on an unknown profile name"
else
  TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: generate.sh fails on an unknown profile name"
fi

# --- 6) manifest get_profile reads the bootstrap key (empty when absent) ---
. "$REPO/bootstrap/lib/manifest.sh"
cat > "$TMP/manifest.md" <<'EOF'
## skill-commons bootstrap
- platforms: claude-code
- profile: team-sprint
EOF
assert_eq "team-sprint" "$(get_profile "$TMP/manifest.md")" "get_profile reads manifest profile key"
printf -- '- platforms: claude-code\n' > "$TMP/manifest-noprofile.md"
assert_eq "" "$(get_profile "$TMP/manifest-noprofile.md")" "get_profile is empty when key absent"

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
