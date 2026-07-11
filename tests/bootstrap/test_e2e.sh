#!/usr/bin/env bash
set -u
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
. "$(dirname "$0")/lib/assert.sh"

# Fresh consuming project, default manifest (all platforms)
mkdir -p "$TMP/.agent"
printf '## skill-commons bootstrap\n- platforms: claude-code, cursor, codex\n- delivery_mode: personal\n' > "$TMP/.agent/project-manifest.md"

# onboard then check across all three platforms: healthy, no warnings
bash "$REPO/bootstrap/onboard.sh" "$TMP" >/dev/null
for plat in claude-code cursor codex; do
  out=$(bash "$REPO/bootstrap/check.sh" --platform "$plat" --project-root "$TMP")
  assert_not_contains "$out" "⚠️" "no warning for $plat after onboard"
  assert_contains "$out" "skill-router" "directive present for $plat"
done

# editing the directive (simulated drift) is caught until re-onboard
# (simulate by corrupting all stamps, then re-onboard fixes them)
sed -i.bak 's/skill-commons-stamp: [a-f0-9]*/skill-commons-stamp: 000000000000/' "$TMP/CLAUDE.md" "$TMP/AGENTS.md"
out=$(bash "$REPO/bootstrap/check.sh" --platform claude-code --project-root "$TMP")
assert_contains "$out" "⚠️" "drift detected after stamp corruption"
bash "$REPO/bootstrap/onboard.sh" "$TMP" >/dev/null
out=$(bash "$REPO/bootstrap/check.sh" --platform claude-code --project-root "$TMP")
assert_not_contains "$out" "⚠️" "re-onboard clears drift"

finish
