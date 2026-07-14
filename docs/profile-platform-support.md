# Profile and platform support

The consuming profile contract has two independent parts:

- `delivery_mode`: exactly one of `personal` or `team-sprint`;
- `capability_packs`: zero or more of `frontend` and `optional`.

`core` is included by either delivery mode. An omitted selection does not mean
“install everything”: onboarding stops until a delivery mode is explicit. The
legacy `profile: personal optional` form remains available as a migration path.
`PROFILE=all` is reserved for an explicit maintainer fan-out and is never an
implicit consuming default.

| Platform | Skill discovery | Adapter boundary |
|---|---|---|
| Claude Code | Skill fan-out | Generated `.claude/skills/` entries plus the Claude bootstrap shim |
| Codex | Skill fan-out | Generated `.codex/skills/` entries plus `AGENTS.md` |
| Cursor | No skill fan-out | Cursor rule + AGENTS adapter; this is not equivalent to Claude Code or Codex skill discovery |

## Bundle-size fact and frontend rationale

The audited pre-W6 baseline was `personal = 16` skills (about 540 KB) and
`team-sprint = 19` skills (about 836 KB). Personal was not the larger bundle.
`design-taste-frontend` moved to the `frontend` capability pack for relevance:
non-frontend work should not load frontend-only instructions. The change is not
justified by a size inversion.

The current generated membership is derived from `profiles/`; do not preserve
the baseline counts as a hand-maintained product claim after membership changes.

## v0.8.0 membership and compatibility boundary

The checked profile files resolve to `current personal = 7`,
`current team-sprint = 12`, and `current optional = 10`. This 7-owner core is the
released `v0.8.0` core. `sync-work` is the sole Git-delivery owner.
Consuming repositories that still require the legacy 13-owner core stay pinned
to `v0.7.1`.

`v0.8.0` adopters add `optional` to the manifest's `capability_packs` (or use
`CAPABILITY_PACKS=optional` with direct generation) when they need personal
discovery, PRD publication, terse review, or shared-skill onboarding. This
profile change makes no effectiveness or quality claim.
