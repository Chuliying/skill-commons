# skill-commons bootstrap

Cross-platform auto-load for the skill-commons skill set (Claude Code / Cursor / Codex).

## How a consuming project uses it

1. Add skill-commons as a submodule at the conventional path `.agent/skills/_shared`:
   `git submodule add <repo-url> .agent/skills/_shared`
2. Create `.agent/project-manifest.md` (this is the same manifest skill-router and
   shared-skill-onboarder use). Platform and delivery selections are explicit:
   ```
   ## skill-commons bootstrap
   - submodule_path: .agent/skills/_shared
   - platforms: claude-code, cursor, codex
   - delivery_mode: personal
   - capability_packs: frontend, optional
   ```
   `submodule_path` defaults to `.agent/skills/_shared`; it must remain a
   project-relative path with no symlinked existing component. `platforms` must name at
   least one of `claude-code`, `cursor`, or `codex`; there is no implicit platform
   guess during onboarding or management. `delivery_mode` is exactly one of `personal` or
   `team-sprint`. `capability_packs` is optional and accepts `frontend` and
   `optional`. The legacy `profile` key remains a migration interface, but must
   still contain exactly one delivery mode and cannot be combined with the new
   keys. Bundle lists live in `profiles/`.
   The 7-owner core is released in `v0.9.0`, with `sync-work` as the sole
   Git-delivery owner. Repositories that still need the legacy 13-owner core
   remain pinned to `v0.7.1`. `v0.9.0` personal adopters select manifest
   `capability_packs: optional`; direct generation uses
   `DELIVERY_MODE=personal CAPABILITY_PACKS=optional`. That pack supplies
   personal discovery, PRD, review, and onboarding capabilities. This profile
   change makes no effectiveness or quality claim.
3. Generate the per-platform shims:
   `bash .agent/skills/_shared/bootstrap/onboard.sh`

This writes/updates `AGENTS.md` (Codex+Cursor), `CLAUDE.md` + a `.claude/settings.json`
SessionStart hook (Claude Code), and `.cursor/rules/skill-commons.mdc` (Cursor).
User content outside the `skill-commons:start/end` fences is preserved.
For enabled Claude Code and Codex platforms it also regenerates `.claude/skills/`
and `.codex/skills/`. Skill generation failure makes onboarding fail instead of
reporting a partial success. Missing, unknown, or duplicate platform selections
fail before any shim or generated skill is changed. Selected adapter ownership,
hook dependencies, and generated-target collisions are also preflighted before
the first managed publication.

## Manage an existing installation

Run these commands from the consuming project, or pass its path as the final
argument:

```
bash .agent/skills/_shared/bootstrap/manage.sh doctor
bash .agent/skills/_shared/bootstrap/manage.sh update
bash .agent/skills/_shared/bootstrap/manage.sh uninstall
```

- `doctor` is read-only. It fails on missing or ambiguous manifest selection,
  malformed ownership data, missing generated units, content drift, and missing
  or malformed platform shims.
- `update` delegates to the normal ownership-safe onboarding path. It does not
  fetch, select, or check out Git tags/refs; update the submodule to a reviewed
  revision first, then run this command.
- `uninstall` preflights every selected target before deleting anything. It
  removes only ledger-owned generated units and skill-commons-managed shim,
  Cursor rule, and Claude hook content. It preserves the manifest, guardrails,
  submodule, unrelated skills, rules, hooks, and text outside managed fences.

`onboard`, `update`, and `uninstall` share one project-install lock from the
first managed publication through the final ownership ledger. A concurrent
loser exits before changing the project; direct `generate.sh` calls continue to
use target-local locks. The project-lock identity uses one stable per-user
system namespace and does not vary with the caller's `TMPDIR`.

Platform shrink is explicit. If the manifest removes a platform while its
managed adapter still exists, `doctor`, `update`, and `uninstall` fail before
mutation. Restore the previous platform selection, run `uninstall`, then set the
smaller selection and run `onboard.sh` again.

If `doctor` reports generated-content drift, inspect the affected path before
running `update`; this avoids silently overwriting edits inside managed output.

## Files

- `directive.md` — canonical instruction (single source of truth). Stamp is derived from its content.
- `onboard.sh` — idempotent generator. Re-run after editing `directive.md` or changing platforms.
- `manage.sh` — read-only diagnosis plus ownership-safe update and uninstall.
- `generate.sh` — fans top-level skills into per-agent trigger directories and
  records managed entries in a target-local ownership ledger. Re-runs replace
  only recorded entries and preserve unrelated skills and shared helpers.
- `check.sh` — advisory check + directive injection. The CC hook runs it every
  session; on Cursor/Codex the always-loaded shim asks the agent to run it. It
  reports submodule/shim/platform warnings but intentionally exits zero; use
  `manage.sh doctor` for a strict health result.
- `lib/` — shared stamp, platform, render, manifest, and ownership safety helpers.

## Notes

- `jq` is required for the Claude Code `settings.json` merge.
- A pre-ledger fan-out is adopted automatically only when every recognized
  entry is current and byte-identical. If an upgrade reports changed or
  historical pre-ledger output, inspect the target first, then run one
  migration with
  `SKILL_COMMONS_ADOPT_LEGACY=1 bash .agent/skills/_shared/bootstrap/onboard.sh`.
- A v0.6 manifest with blank `profile:` must first be changed to one explicit
  `delivery_mode` plus optional `capability_packs` (or one non-empty legacy
  delivery mode). Legacy and new selection fields cannot coexist.
- A repository adopting the `v0.9.0` 7-owner core adds
  `optional` before onboarding if it depends on the personal
  discovery/PRD/review/onboarding owners. A repository deferring that migration
  keeps its `v0.7.1` pin.
- This complements `shared-skill-onboarder` (which builds the manifest + domain skills);
  bootstrap only generates the cross-platform auto-load shims.
- If you also have the superpowers plugin installed, consider disabling it for this project to avoid two routers.
