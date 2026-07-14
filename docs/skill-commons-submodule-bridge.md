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
| Codex | `.codex/skills/`, `AGENTS.md` |
| Cursor | `.cursor/rules/skill-commons.mdc`, `AGENTS.md`; no skill fan-out |

## Install v0.8.0

Pin the published tag:

```bash
git submodule add git@github.com:Chuliying/skill-commons.git .agent/skills/_shared
git -C .agent/skills/_shared checkout v0.8.0

mkdir -p .agent
cp .agent/skills/_shared/shared-skill-onboarder/templates/project-manifest.md \
  .agent/project-manifest.md
${EDITOR:-vi} .agent/project-manifest.md
```

Before onboarding, select at least one platform and exactly one delivery mode:

```yaml
## skill-commons bootstrap

- submodule_path: .agent/skills/_shared
- platforms: claude-code, cursor, codex
- delivery_mode: personal
- capability_packs:
```

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
are not overwritten.

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

In `v0.8.0`, this refinement step is conditional: set
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
git -C .agent/skills/_shared checkout v0.8.0
bash .agent/skills/_shared/bootstrap/manage.sh update
bash .agent/skills/_shared/bootstrap/manage.sh doctor
```

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
