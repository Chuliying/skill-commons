# skill-commons bootstrap

Cross-platform auto-load for the skill-commons skill set (Claude Code / Cursor / Codex).

## How a consuming project uses it

1. Add skill-commons as a submodule at the conventional path `.agent/skills/_shared`:
   `git submodule add <repo-url> .agent/skills/_shared`
2. Create `.agent/project-manifest.md` (this is the same manifest skill-router and
   shared-skill-onboarder use). Bootstrap reads these optional keys:
   ```
   ## skill-commons bootstrap
   - submodule_path: .agent/skills/_shared
   - platforms: claude-code, cursor, codex
   - profile: team-sprint
   ```
   Defaults: `submodule_path` → `.agent/skills/_shared`, `platforms` → all three.
   `profile` selects which skill bundle gets fanned out (lists live in `profiles/`):
   `team-sprint` (core + team overlay, full pipeline), `personal` (core + personal
   overlay, lightweight flow), or a composition such as `personal optional`.
   Leave it out to fan all workflow skills (backward compatible).
3. Generate the per-platform shims:
   `bash .agent/skills/_shared/bootstrap/onboard.sh`

This writes/updates `AGENTS.md` (Codex+Cursor), `CLAUDE.md` + a `.claude/settings.json`
SessionStart hook (Claude Code), and `.cursor/rules/skill-commons.mdc` (Cursor).
User content outside the `skill-commons:start/end` fences is preserved.
For enabled Claude Code and Codex platforms it also regenerates `.claude/skills/`
and `.codex/skills/`. Skill generation failure makes onboarding fail instead of
reporting a partial success.

## Files

- `directive.md` — canonical instruction (single source of truth). Stamp is derived from its content.
- `onboard.sh` — idempotent generator. Re-run after editing `directive.md` or changing platforms.
- `generate.sh` — clears and fans top-level skills into per-agent trigger directories.
- `check.sh` — self-check + directive injection. The CC hook runs it every session; on Cursor/Codex
  the always-loaded shim asks the agent to run it. Verifies: submodule initialized, shim drift, platform coverage.
- `lib/` — `stamp.sh`, `platform.sh`, `render.sh`, `manifest.sh`.

## Notes

- `jq` is required for the Claude Code `settings.json` merge.
- This complements `shared-skill-onboarder` (which builds the manifest + domain skills);
  bootstrap only generates the cross-platform auto-load shims.
- If you also have the superpowers plugin installed, consider disabling it for this project to avoid two routers.
