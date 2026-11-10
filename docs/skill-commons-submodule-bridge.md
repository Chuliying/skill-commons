# Skill Commons Submodule Bridge

This guide mounts `skill-commons` in a consuming repository while keeping
project-specific state and rules in that repository.

## Layout

```text
.agent/
├── project-manifest.md
├── guardrails.md
└── skills/
    ├── _shared/   # pinned skill-commons submodule
    └── project/   # optional project-specific domain skills
```

The adapters are intentionally different:

| Platform | Managed adapter |
|---|---|
| Claude Code | `.claude/skills/`, `CLAUDE.md`, SessionStart hook |
| Codex | `.agents/skills/` (the location Codex documents; earlier installs used `.codex/skills/`, and `onboard.sh` moves those copies), `AGENTS.md` |
| Cursor | `.cursor/rules/skill-commons.mdc`, `AGENTS.md`; no skill fan-out |

Onboarding lists the generated files in a fenced `.gitignore` block. The copies and
`.agent/.skill-commons-fanout`, which records their toolkit revision, stay out of Git.
Project files added inside a generated skill directory remain visible to Git.

Prepare a fresh clone before starting Claude Code if you need its skills on the first
turn. Run these commands at the project root, using your configured submodule path:

```bash
git submodule update --init
bash .agent/skills/_shared/bootstrap/check.sh --platform claude-code --project-root .
```

The SessionStart check can also regenerate missing or stale copies, but a local
fresh-clone probe found that skill discovery had already run in that session.
For Codex, pass `--platform codex` to prepare before opening it. The `AGENTS.md`
shim also tells Codex to run the check. Automatic regeneration uses the committed manifest and writes
only ignored copies and local state. It reports a mismatched submodule, tracked copies,
or insufficient ignore rules. Run onboarding explicitly after editing the manifest or
when a shim stamp is stale. If an upgrade changes generated paths, rerun onboarding and
commit its updated ignore block along with the submodule revision. If an installed
copy has local changes, move the files outside the generated path before retrying
automatic regeneration or migration. Explicit onboarding can restore a modified
generated file when that path still belongs to the current toolkit. Vendored copies outside Git have no revision to compare.
Run onboarding after upgrading a vendored copy.

For a Claude Code cloud session, arrange submodule initialization before the toolkit
check runs. A fresh single-repository cloud clone can leave it uninitialized, which
makes the hook's script unavailable. In a cloud probe with an initialized submodule,
Claude Code 2.1.318 regenerated both copies at SessionStart and listed `skill-router`
on the first turn. Preparing the copies before launch also covers the observed local
behavior. Repository hooks and skills are unavailable in Claude Code project cloud
threads. See [settings in cloud sessions](https://code.claude.com/docs/en/settings#settings-in-cloud-sessions)
and [cloud skill discovery](https://code.claude.com/docs/en/skills#use-skills-in-cowork-and-cloud-sessions).

To migrate installations with tracked copies, make one commit:

1. Update the submodule and run `onboard.sh`. It writes the ignore block and prints
   a `git rm -r --cached` command for the generated files still tracked. Review and
   run the command to leave those copies on disk. `manage.sh doctor` prints it too.
   Onboarding moves verified legacy Codex copies to `.agents/skills`. If the earlier
   copies were tracked, stage their deletions with the rest of the migration.
2. Commit the submodule update, the ignore block, and the scoped Git changes together.
3. Teammates run `git pull` and prepare the clone with the commands above before
   opening a new session. Use the newly pinned toolkit for onboarding and updates.
   An older installer can recreate copies at the legacy Codex path.

If Git ignores `.gitignore` itself, onboarding prints `git add -f .gitignore`. Onboarding
requires a regular `.gitignore` file. `manage.sh uninstall` removes the managed block and
state file. If a crashed install leaves a lock, confirm that the process in the reported
lock's `pid` file has exited, remove that lock directory, and retry.

## Install v0.13.1

The current release is v0.13.1, which carries the content-bound verification, approvals, ledger and work-item commands. Two commands, over HTTPS and without questions:

```bash
git submodule add https://github.com/Chuliying/skill-commons.git .agent/skills/_shared
bash .agent/skills/_shared/bootstrap/onboard.sh
```

When `.agent/project-manifest.md` is missing, onboarding writes a default one
(`personal` with `capability_packs: optional`; platforms as detected below, Claude Code and Codex when none is found). To pin a release instead of the commit you
added, run `git -C .agent/skills/_shared checkout v0.13.1` and onboard again.

To change the selection, edit the generated manifest and onboard again. It needs
at least one platform and exactly one delivery mode. Example with all three platforms:

```yaml
## skill-commons bootstrap

- submodule_path: .agent/skills/_shared
- platforms: claude-code, codex, cursor
- delivery_mode: personal
- capability_packs: optional
```

A manifest that onboarding creates lists the platforms it finds (`.claude` or `CLAUDE.md`,
`.codex`, `.cursor` or `.cursorrules`), and Claude Code plus Codex when it finds none. An
`AGENTS.md` on its own is a vendor-neutral file and does not select Codex. When `AGENTS.md` is also managed, `CLAUDE.md` imports it (`@AGENTS.md`) instead of
repeating the directive.

`delivery_mode` is `personal` or `team-sprint`. `capability_packs` may contain
`frontend` and/or `optional`. An omitted delivery mode fails closed. The
legacy `profile` field exists only for migration and cannot be combined with
the new fields. `submodule_path` must be project-relative and cannot traverse an
existing symlink component.

Then run:

```bash
bash .agent/skills/_shared/bootstrap/onboard.sh
bash .agent/skills/_shared/bootstrap/manage.sh doctor
```

## Ownership behavior

Onboarding creates missing manifest/guardrails skeletons, updates only the
skill-commons fenced blocks and platform adapter files, and fans selected skills
to Claude Code/Codex discovery roots. Existing manifest and guardrails files
are not overwritten. A manifest that onboarding creates gets `source_roots` and
`tests_root` derived from conventional top-level directories (for example `src`,
`tests`) and a `test_cmd` derived from project files (a `package.json` test script,
`go.mod`, `Cargo.toml`, pytest configuration, `test_*.py` files or a Makefile `test`
target); check them. For an existing manifest without them, onboarding prints
suggested lines instead.

Each generated skill root has a target-local ownership ledger. Later generation
may replace or remove only validated ledger-owned units. Unrelated skills,
runtime helpers, hooks, rules, and text outside managed fences remain foreign
content and are preserved.

For a pre-ledger installation, byte-identical current output is adopted
automatically. Changed or historical output fails closed. Inspect the target,
then opt into one migration run only if those recognized paths should become
managed:

```bash
SKILL_COMMONS_ADOPT_LEGACY=1 \
  bash .agent/skills/_shared/bootstrap/onboard.sh
```

## Refine the project manifest

After onboarding, ask the agent to read
`shared-skill-onboarder/SKILL.md` and run Scan mode. It should use repository
evidence to refine:

- source, test, docs, and work-item paths;
- test, lint, typecheck, and E2E commands;
- `has_ui`, `has_api`, `typed_contracts`, and `has_e2e` capabilities;
- Git workflow boundaries;
- candidate project-specific domain skills.

Unknown fields stay unknown until evidence exists.

In `v0.10.0`, this refinement step is conditional: set
`capability_packs: optional` before running onboarding when the agent should use
`shared-skill-onboarder`. Without that pack, maintain the manifest manually or
follow the top-level-source maintainer checklist; do not dispatch an uninstalled
owner. Repositories that still depend on the legacy 13-owner core may remain
pinned to `v0.7.1` until they migrate.

## Check, diagnose, update, and uninstall

`bootstrap/check.sh` is a session advisory and intentionally exits zero so it
does not abort the host. Use strict `doctor` for installation health:

```bash
bash .agent/skills/_shared/bootstrap/check.sh
bash .agent/skills/_shared/bootstrap/manage.sh doctor
```

When upgrading a v0.6 installation, first replace the old blank `- profile:` in
`.agent/project-manifest.md` with explicit `platforms`, one
`delivery_mode: personal|team-sprint`, and optional `capability_packs`. Do not
leave the legacy field beside the new fields; v0.7 and later reject that ambiguous shape.

Then move the submodule to a reviewed revision. `manage.sh update` does not
fetch, select, or checkout refs:

```bash
git -C .agent/skills/_shared fetch --tags
git -C .agent/skills/_shared checkout v0.13.1
bash .agent/skills/_shared/bootstrap/manage.sh update
bash .agent/skills/_shared/bootstrap/manage.sh doctor
bash .agent/skills/_shared/scripts/project-status.sh
```

`doctor` checks the installation only. `project-status` checks existing work items
against the new version's rules: a newer version can require fields that older items
lack, and the CHANGELOG lists each one with how to add it.

To remove generated adapters and skills:

```bash
bash .agent/skills/_shared/bootstrap/manage.sh uninstall
```

Uninstall preflights every selected target before the first deletion. It removes
only validated ledger units, managed blocks/rule, and the exact manifest-derived
Claude hook. It preserves foreign content, `.agent/project-manifest.md`,
`.agent/guardrails.md`, project domain skills, and the submodule itself.

To remove a platform, do not edit it out and leave its adapter hidden. Restore
the previous selection, run `manage.sh uninstall`, then set the smaller platform
list and run `onboard.sh`. Management commands fail before mutation when they
detect managed artifacts for a deselected platform.

All management commands accept an optional consuming `project-root` as their
last argument.

## Troubleshooting

- Missing submodule: `git submodule update --init --recursive`.
- Missing `jq`: install it before onboarding a Claude Code adapter.
- Doctor reports drift: inspect the path and confirm the checked-out submodule
  revision and manifest selection before running `manage.sh update`.
- Adoption is refused: do not remove the entire discovery root. Review the
  recognized pre-ledger paths, then decide whether the one-time adoption flag is
  appropriate.
- Retired Plan Sync files: migrate current state to canonical-v2
  `docs/work/<slug>/plan/plan.md`, or remain pinned to v0.6 until migration.
