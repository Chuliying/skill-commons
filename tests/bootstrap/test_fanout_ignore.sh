#!/usr/bin/env bash
# T13 option F: generated skill copies are ignored, not committed, and the session-start
# check regenerates them. Covers install, a teammate's fresh clone, a moved submodule,
# a deleted unit, migration of copies committed before, uninstall and failure paths.
set -u
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
TMP="$(mktemp -d)" || { echo "cannot create a temp directory"; exit 1; }; trap 'rm -rf "$TMP"' EXIT
. "$(dirname "$0")/lib/assert.sh"
export GIT_CONFIG_NOSYSTEM=1
G() { git -c core.excludesFile=/dev/null -c user.name=t -c user.email=t@example.invalid -c protocol.file.allow=always "$@"; }

# The submodule source is the working tree, committed in a throwaway repo.
SRC="$TMP/src"; mkdir -p "$SRC"
python3 - "$REPO" "$SRC" <<'PY'
import shutil, subprocess, sys
from pathlib import Path
repo, src = Path(sys.argv[1]), Path(sys.argv[2])
names = subprocess.run(["git", "-C", str(repo), "ls-files", "-co", "--exclude-standard", "-z"], capture_output=True, check=True).stdout.split(b"\0")
for raw in filter(None, names):
    path = repo / raw.decode()
    if path.is_file() or path.is_symlink():
        target = src / raw.decode()
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(path, target, follow_symlinks=False)
PY
G -C "$SRC" init -q && G -C "$SRC" add -A && G -C "$SRC" commit -q -m src

new_project() { # dir
  mkdir -p "$1" && G -C "$1" init -q
  printf 'dist/\n' > "$1/.gitignore"
  mkdir -p "$1/.claude/skills/my-skill" && printf -- '---\nname: my-skill\ndescription: mine\n---\n' > "$1/.claude/skills/my-skill/SKILL.md"
  mkdir -p "$1/.codex" && printf 'model = "x"\n' > "$1/.codex/config.toml"
  G -C "$1" add -A && G -C "$1" commit -q -m init
  ( cd "$1" && G submodule add -q "$SRC" .agent/skills/_shared ) </dev/null
}
status_of() { G -C "$1" status --porcelain --untracked-files=all; }
hook() { bash "$1/.agent/skills/_shared/bootstrap/check.sh" --platform claude-code --project-root "$1"; }

P="$TMP/project"
new_project "$P"
out="$(cd "$P" && bash .agent/skills/_shared/bootstrap/onboard.sh </dev/null 2>&1)"; rc=$?
assert_eq "0" "$rc" "onboard succeeds"
ign="$(cat "$P/.gitignore")"
assert_contains "$ign" "dist/" "the user's own ignore lines are kept"
assert_contains "$ign" "# >>> skill-commons generated skill copies" "onboard writes the ignore block"
assert_contains "$ign" "/.claude/skills/implement/SKILL.md" "a generated skill is ignored"
assert_contains "$ign" "/.agents/skills/scripts/work_items.py" "a generated script is ignored by file, not the whole scripts folder"
assert_not_contains "$ign" "my-skill" "the user's own skill is not ignored"
st="$(status_of "$P")"
assert_not_contains "$st" ".claude/skills/implement" "generated Claude copies are not shown to Git"
assert_not_contains "$st" ".agents/skills" "generated Codex copies are not shown to Git"
assert_not_contains "$st" ".skill-commons-fanout" "the state file is not shown to Git"
assert_contains "$(cat "$P/.agent/.skill-commons-fanout")" "submodule=$(G -C "$SRC" rev-parse HEAD)" "the state records the submodule commit"
before="$(cat "$P/.gitignore")"
(cd "$P" && bash .agent/skills/_shared/bootstrap/onboard.sh </dev/null >/dev/null 2>&1)
assert_eq "$before" "$(cat "$P/.gitignore")" "a second onboard leaves the ignore block unchanged"
assert_eq "1" "$(grep -Fxc '# >>> skill-commons generated skill copies (written by onboard.sh; do not edit)' "$P/.gitignore")" "there is one ignore block"
G -C "$P" add -A && G -C "$P" commit -q -m "install skill-commons"
assert_eq "" "$(G -C "$P" ls-files .claude/skills/implement .agents/skills)" "the install commit holds no generated copies"
assert_contains "$(G -C "$P" ls-files .codex)" ".codex/config.toml" "the user's own Codex config stays tracked"

# A teammate's fresh clone: no copies until the session-start check regenerates them.
C="$TMP/clone"
G clone -q --recurse-submodules "$P" "$C" 2>/dev/null
assert_eq "0" "$([ -e "$C/.claude/skills/implement" ] && echo 1 || echo 0)" "a fresh clone has no generated copies"
hook_out="$(hook "$C")"; hook_rc=$?
assert_eq "0" "$hook_rc" "the session-start check exits 0"
printf '%s' "$hook_out" | python3 -c 'import json,sys; json.load(sys.stdin)' 2>/dev/null; assert_eq "0" "$?" "the hook output stays valid JSON"
assert_file "$C/.claude/skills/implement/SKILL.md" "the check regenerates the Claude copies"
assert_file "$C/.agents/skills/implement/SKILL.md" "the check regenerates the Codex copies"
assert_file "$C/.claude/skills/my-skill/SKILL.md" "the user's own skill is untouched"
assert_eq "" "$(status_of "$C")" "the clone stays clean after regeneration"
touch -t 200001010000 "$C/.claude/skills/implement/SKILL.md"
hook "$C" >/dev/null
assert_eq "200001010000" "$(date -r "$C/.claude/skills/implement/SKILL.md" +%Y%m%d%H%M 2>/dev/null || stat -c %y "$C/.claude/skills/implement/SKILL.md")" "a current install is not regenerated"
rm -rf "$C/.claude/skills/implement"
hook "$C" >/dev/null
assert_file "$C/.claude/skills/implement/SKILL.md" "a deleted unit is regenerated"
printf 'submodule=0000000000000000000000000000000000000000\nstamp=000000000000\n' > "$C/.agent/.skill-commons-fanout"
hook "$C" >/dev/null
assert_contains "$(cat "$C/.agent/.skill-commons-fanout")" "submodule=$(G -C "$SRC" rev-parse HEAD)" "a moved submodule triggers regeneration"
assert_contains "$(bash "$C/.agent/skills/_shared/bootstrap/manage.sh" doctor "$C" 2>&1)" "doctor: healthy" "doctor is healthy after regeneration"

# A user's own file inside the generated scripts folder is neither ignored nor regenerated away.
printf 'x = 1\n' > "$C/.claude/skills/scripts/own.py"
assert_contains "$(status_of "$C")" ".claude/skills/scripts/own.py" "a user's own file next to generated scripts stays visible to Git"
rm -f "$C/.claude/skills/scripts/own.py"

# A symlinked path to the project still regenerates.
ln -s "$C" "$TMP/clone-link"
rm -rf "$C/.claude/skills/implement"
hook "$TMP/clone-link" >/dev/null
assert_file "$C/.claude/skills/implement/SKILL.md" "a symlinked project path regenerates"

# A stale shim keeps the drift warning and the hook does not rewrite tracked files.
cp "$C/CLAUDE.md" "$TMP/claude.orig"
sed -i.bak -E 's/skill-commons-stamp: [a-f0-9]{12}/skill-commons-stamp: 000000000000/' "$C/CLAUDE.md" && rm -f "$C/CLAUDE.md.bak"
rm -rf "$C/.claude/skills/implement"
drift_out="$(hook "$C")"
assert_contains "$drift_out" "configuration is out of date" "a stale shim still shows the drift warning"
assert_contains "$(cat "$C/CLAUDE.md")" "000000000000" "the hook does not rewrite a stale shim"
assert_eq "0" "$([ -e "$C/.claude/skills/implement" ] && echo 1 || echo 0)" "the hook leaves regeneration to the person when the shim is stale"
cp "$TMP/claude.orig" "$C/CLAUDE.md"; hook "$C" >/dev/null

# Refresh uses committed configuration and must not rewrite tracked project files.
printf '\n' >> "$C/.claude/settings.json"
settings_before="$(shasum "$C/.claude/settings.json")"
rm -rf "$C/.claude/skills/implement"
hook "$C" >/dev/null
assert_eq "$settings_before" "$(shasum "$C/.claude/settings.json")" "the hook preserves an edited Claude settings file byte for byte"
G -C "$C" checkout -q -- .claude/settings.json
printf '\n' >> "$C/.agent/project-manifest.md"
rm -rf "$C/.claude/skills/implement"
assert_contains "$(hook "$C")" "project manifest has local changes" "the hook asks before using an edited manifest"
assert_eq "0" "$([ -e "$C/.claude/skills/implement" ] && echo 1 || echo 0)" "an edited manifest does not trigger fan-out"
G -C "$C" checkout -q -- .agent/project-manifest.md
hook "$C" >/dev/null

printf 'mine\n' > "$C/.claude/skills/implement/own.txt"
rm -rf "$C/.claude/skills/security"
assert_contains "$(status_of "$C")" ".claude/skills/implement/own.txt" "an added file within a generated skill stays visible to Git"
assert_contains "$(hook "$C")" "locally changed generated path" "the hook reports a collision inside a generated unit"
assert_file "$C/.claude/skills/implement/own.txt" "the hook preserves a user file within a generated skill"
rm -f "$C/.claude/skills/implement/own.txt"
hook "$C" >/dev/null

# Running a generated Python helper can write its own bytecode cache. Apple's system
# python3 sets sys.pycache_prefix, which would put the cache under the user's Caches
# directory instead; -X pycache_prefix= clears it so the cache lands beside the source.
python3 -X pycache_prefix= -m py_compile "$C/.claude/skills/security/scripts/extract-secrets.py"
cache_dir="$C/.claude/skills/security/scripts/__pycache__"
printf 'mine\n' > "$cache_dir/own.txt"
rm -rf "$C/.claude/skills/implement"
assert_contains "$(hook "$C")" "__pycache__/own.txt" "a user file in a cache directory still blocks replacement"
assert_file "$cache_dir/own.txt" "refresh preserves the user file in the cache directory"
rm -f "$cache_dir/own.txt"
cache_out="$(hook "$C")"
assert_not_contains "$cache_out" "locally changed generated path" "a generated Python cache does not block refresh"
assert_file "$C/.claude/skills/implement/SKILL.md" "refresh can replace copies after generated Python code has run"

# A held lock stays intact and the hook tells the caller how to recover a stale lock.
LOCK="$(cd "$C" && pwd -P | tr -d '\n' | cksum | awk '{print $1}')"; LOCK="/tmp/skill-commons-install-$(id -u)-$LOCK.lock"
rm -rf "$C/.claude/skills/implement"; mkdir -p "$LOCK"; printf '%s\n' "$$" > "$LOCK/pid"
lock_out="$(hook "$C")"; lock_rc=$?
assert_eq "0" "$lock_rc" "a held lock does not abort the session"
assert_contains "$lock_out" "installation is locked" "a held lock is reported"
printf '%s' "$lock_out" | python3 -c 'import json,sys; json.load(sys.stdin)' 2>/dev/null; assert_eq "0" "$?" "the warning keeps the hook output valid JSON"
printf '999999\n' > "$LOCK/pid"
assert_contains "$(hook "$C")" "remove the stale lock directory" "a stale lock has recovery guidance"
assert_file "$LOCK/pid" "the hook does not race another lock owner by reclaiming the lock"
rm -rf "$LOCK"
hook "$C" >/dev/null
assert_file "$C/.claude/skills/implement/SKILL.md" "regeneration resumes once the stale lock is removed"

# The submodule checkout differs from the commit the repository records.
G -C "$C/.agent/skills/_shared" commit -q --allow-empty -m local
assert_contains "$(hook "$C")" "not at the commit this repository records" "a submodule that moved away from the recorded commit is reported"
G -C "$C/.agent/skills/_shared" reset -q --hard HEAD~1
assert_not_contains "$(hook "$C")" "not at the commit" "the recorded commit gives no warning"

# An actual toolkit upgrade: Git records the new revision while the old ignored
# files stay on disk. The refresh compares those files to the earlier revision.
printf '\nUpdated by toolkit commit.\n' >> "$C/.agent/skills/_shared/implement/SKILL.md"
G -C "$C/.agent/skills/_shared" add implement/SKILL.md
G -C "$C/.agent/skills/_shared" commit -q -m "update generated payload"
G -C "$C" add .agent/skills/_shared && G -C "$C" commit -q -m "pin new toolkit"
hook "$C" >/dev/null
assert_contains "$(cat "$C/.claude/skills/implement/SKILL.md")" "Updated by toolkit commit." "a pinned toolkit upgrade replaces the old generated copy"
assert_eq "" "$(status_of "$C")" "refresh leaves the upgraded clone clean"

# Missing ignore coverage must not publish files or rewrite the ignore rules.
grep -Fvx '/.claude/skills/implement/SKILL.md' "$C/.gitignore" > "$TMP/incomplete-ignore"
cp "$TMP/incomplete-ignore" "$C/.gitignore"
rm -rf "$C/.claude/skills/implement"
assert_contains "$(hook "$C")" "ignore rules need an explicit update" "the hook reports missing ignore coverage"
assert_eq "0" "$([ -e "$C/.claude/skills/implement" ] && echo 1 || echo 0)" "the hook does not write an unignored copy"
assert_eq "$(cat "$TMP/incomplete-ignore")" "$(cat "$C/.gitignore")" "the hook does not update the ignore block"
G -C "$C" checkout -q -- .gitignore
hook "$C" >/dev/null

# A failed regeneration warns and still exits 0.
rm -rf "$C/.claude/skills/implement"
printf -- '- platforms: claude-code\n- platforms: codex\n' >> "$C/.agent/project-manifest.md"
fail_out="$(hook "$C")"; fail_rc=$?
assert_eq "0" "$fail_rc" "a failed regeneration does not abort the session"
assert_contains "$fail_out" "could not regenerate the skill copies" "a failed regeneration is reported"
G -C "$C" checkout -q -- .agent/project-manifest.md

# A repository that was never onboarded is left alone.
N="$TMP/never"; mkdir -p "$N" && G -C "$N" init -q && cp -R "$SRC" "$N/vendored" 2>/dev/null
bash "$N/vendored/bootstrap/check.sh" --platform claude-code --project-root "$N" >/dev/null
assert_eq "0" "$([ -e "$N/.claude" ] && echo 1 || echo 0)" "the check does not install into a project that was never onboarded"

# Migration: copies committed by an earlier version are listed for untracking, unit by unit.
M="$TMP/migrate"
new_project "$M"
(cd "$M" && bash .agent/skills/_shared/bootstrap/onboard.sh </dev/null >/dev/null 2>&1)
G -C "$M" add -A && G -C "$M" add -f .claude/skills .agents/skills && G -C "$M" commit -q -m "old install committed the copies"
rm -f "$M/.agent/.skill-commons-fanout"; ign_before="$(cat "$M/.gitignore")"
pre_out="$(hook "$M")"
assert_contains "$pre_out" "generated skill copies are committed" "the hook points an earlier install at the migration"
assert_eq "$ign_before" "$(cat "$M/.gitignore")" "the hook does not edit .gitignore for an earlier install"
mig_out="$(cd "$M" && bash .agent/skills/_shared/bootstrap/onboard.sh </dev/null 2>&1)"
assert_contains "$mig_out" "git rm -r --cached --" "onboard prints how to untrack earlier copies"
assert_contains "$mig_out" ".claude/skills/implement" "the untrack list names generated units"
assert_not_contains "$mig_out" "my-skill" "the untrack list never names the user's own skill"
assert_not_contains "$mig_out" " .claude/skills " "the untrack list never names the whole skills folder"
assert_contains "$(bash "$M/.agent/skills/_shared/bootstrap/manage.sh" doctor "$M" 2>&1)" "Git still tracks generated skill copies" "doctor notes tracked copies"
cmd="$(printf '%s\n' "$mig_out" | grep -o 'git rm -r --cached --.*')"
(cd "$M" && eval "$cmd" >/dev/null) && G -C "$M" commit -q -m untrack
assert_eq "" "$(G -C "$M" ls-files .claude/skills/implement .agents/skills)" "the printed command untracks the copies"
assert_contains "$(G -C "$M" ls-files .claude/skills)" "my-skill" "the user's own skill stays tracked"
assert_file "$M/.claude/skills/implement/SKILL.md" "untracking keeps the files on disk"

# Malformed block: onboard stops before publishing; doctor reports it.
printf '# <<< skill-commons generated skill copies\n' >> "$M/.gitignore"
mal_rc=0; (cd "$M" && bash .agent/skills/_shared/bootstrap/onboard.sh </dev/null >/dev/null 2>&1) || mal_rc=$?
assert_neq "0" "$mal_rc" "onboard refuses a malformed ignore block"
doc_rc=0; bash "$M/.agent/skills/_shared/bootstrap/manage.sh" doctor "$M" >/dev/null 2>&1 || doc_rc=$?
assert_neq "0" "$doc_rc" "doctor reports a malformed ignore block"
python3 - "$M/.gitignore" <<'PY'
import sys
from pathlib import Path
p = Path(sys.argv[1]); lines = p.read_text().splitlines()
p.write_text("\n".join(lines[:-1]) + "\n")
PY

# A .gitignore that is itself ignored (a global excludes file) gets a note.
GI="$TMP/global-ignore"
new_project "$GI"
G -C "$GI" rm -q .gitignore && G -C "$GI" commit -q -m "no project .gitignore"
printf '.gitignore\n' > "$TMP/excludes"; git -C "$GI" config core.excludesFile "$TMP/excludes"
assert_contains "$(cd "$GI" && bash .agent/skills/_shared/bootstrap/onboard.sh </dev/null 2>&1)" "git add -f .gitignore" "an ignored .gitignore is reported"

# Earlier installs wrote Codex copies to .codex/skills; onboard moves them to .agents/skills,
# keeping the user's own files there and the Codex config.
L="$TMP/legacy-codex"
new_project "$L"
(cd "$L" && bash .agent/skills/_shared/bootstrap/onboard.sh </dev/null >/dev/null 2>&1)
mv "$L/.agents/skills" "$L/.codex/skills" && rmdir "$L/.agents"
mkdir -p "$L/.codex/skills/team-skill" && printf 'mine\n' > "$L/.codex/skills/team-skill/SKILL.md"
leg_doc_rc=0; leg_doc="$(bash "$L/.agent/skills/_shared/bootstrap/manage.sh" doctor "$L" 2>&1)" || leg_doc_rc=$?
assert_neq "0" "$leg_doc_rc" "doctor reports Codex copies left in .codex/skills"
assert_contains "$leg_doc" "run onboard.sh (or manage.sh update) to move them" "doctor says how to move them"
printf 'mine\n' > "$L/.codex/skills/implement/own.txt"
custom_rc=0; custom_out="$(cd "$L" && bash .agent/skills/_shared/bootstrap/onboard.sh </dev/null 2>&1)" || custom_rc=$?
assert_neq "0" "$custom_rc" "legacy migration refuses to overwrite an edited skill"
assert_contains "$custom_out" "locally changed generated path" "legacy migration identifies the local file"
assert_file "$L/.codex/skills/implement/own.txt" "legacy migration preserves the local file"
rm -f "$L/.codex/skills/implement/own.txt"
rm -rf "$L/.codex/skills/security"

leg_out="$(cd "$L" && bash .agent/skills/_shared/bootstrap/onboard.sh </dev/null 2>&1)"; leg_rc=$?
assert_eq "0" "$leg_rc" "onboard moves an earlier Codex install"
assert_contains "$leg_out" "moved the Codex skill copies from .codex/skills to .agents/skills" "the move is reported"
assert_file "$L/.agents/skills/implement/SKILL.md" "Codex copies are now in .agents/skills"
assert_eq "0" "$([ -e "$L/.codex/skills/implement" ] && echo 1 || echo 0)" "the earlier Codex copies are removed"
assert_eq "0" "$([ -e "$L/.codex/skills/.skill-commons-ownership-v1" ] && echo 1 || echo 0)" "the earlier Codex ledger is removed"
assert_file "$L/.codex/skills/team-skill/SKILL.md" "the user's own skill in .codex/skills is kept"
assert_file "$L/.codex/config.toml" "the Codex config is kept"
assert_contains "$(bash "$L/.agent/skills/_shared/bootstrap/manage.sh" doctor "$L" 2>&1)" "doctor: healthy" "doctor is healthy after the move"
assert_contains "$(cat "$L/.gitignore")" "/.agents/skills/implement/SKILL.md" "the ignore block names the new Codex location"

# An old installation may be uninstalled without first moving its copies.
U="$TMP/legacy-uninstall"
new_project "$U"
(cd "$U" && bash .agent/skills/_shared/bootstrap/onboard.sh </dev/null >/dev/null 2>&1)
mv "$U/.agents/skills" "$U/.codex/skills"
rm -rf "$U/.codex/skills/security"
printf 'mine\n' > "$U/.codex/skills/scripts/own.py"
legacy_un_rc=0; legacy_un_out="$(bash "$U/.agent/skills/_shared/bootstrap/manage.sh" uninstall "$U" 2>&1)" || legacy_un_rc=$?
assert_eq "0" "$legacy_un_rc" "uninstall accepts an old Codex installation with missing generated units"
assert_contains "$legacy_un_out" "uninstall: removed owned skills" "legacy uninstall reached cleanup"
assert_file "$U/.codex/skills/scripts/own.py" "legacy uninstall preserves a user's helper"
assert_file "$U/.codex/config.toml" "legacy uninstall preserves Codex config"

# Uninstall removes the block and the state file and keeps the user's lines.
un_rc=0; bash "$P/.agent/skills/_shared/bootstrap/manage.sh" uninstall "$P" >/dev/null 2>&1 || un_rc=$?
assert_eq "0" "$un_rc" "uninstall succeeds"
assert_not_contains "$(cat "$P/.gitignore")" "skill-commons generated skill copies" "uninstall removes the ignore block"
assert_contains "$(cat "$P/.gitignore")" "dist/" "uninstall keeps the user's ignore lines"
assert_eq "0" "$([ -e "$P/.agent/.skill-commons-fanout" ] && echo 1 || echo 0)" "uninstall removes the state file"
assert_file "$P/.claude/skills/my-skill/SKILL.md" "uninstall keeps the user's own skill"

finish
