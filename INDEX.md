# Skill Index

Top-level skill folders are the source of truth. `(ext)` marks external or
adapted skills tracked in [SOURCES.md](SOURCES.md). Consuming bundle membership
is defined only by [`profiles/`](profiles/) and [`profiles.json`](profiles.json).

## Delivery selection

Every consuming repository selects one `delivery_mode` and zero or more
`capability_packs`. Both delivery modes include `core`.

| Kind | Name | Added surface |
|---|---|---|
| Base | `core` | router, planning, implementation, debugging, verification, security and Git |
| Delivery mode | `personal` | core without team ceremony |
| Delivery mode | `team-sprint` | `prd-interview`, `spec`, `qa`, `prototype`, `domain-modeling` (ext) |
| Capability pack | `frontend` | `design-taste-frontend` (ext) |
| Capability pack | `optional` | `brainstorming` (ext), `grilling` (ext), `to-prd` (ext), `caveman-review` (ext), `shared-skill-onboarder`, `markdown`, `codebase-understanding`, `subagent-driven-development` (ext), `humanizer` (ext), `reducing-entropy` (ext) |

`delivery_mode` is required. `capability_packs` is optional and composable.
`PROFILE=all` is a maintainer-only full fan-out; it is not a consuming default.
`skill-creator` remains a top-level maintainer tool and is not part of consuming
profiles. Do not infer cost or quality from a hand-maintained skill count.

The 7-owner core in the checked profiles is released in `v0.9.0`, with
`sync-work` as the sole Git-delivery owner. Consumers that still need the legacy
13-owner core remain pinned to `v0.7.1`. `v0.9.0` personal users select
`CAPABILITY_PACKS=optional` for discovery, PRD, review, and onboarding owners.
This membership change makes no effectiveness or quality claim.

## Workflow skills

| Stage | Skills | Purpose |
|---|---|---|
| Route | `skill-router`; `skill-creator` (ext, maintainer) | Choose the minimum flow; maintain skill contracts |
| Explore | `brainstorming` (ext), `grilling` (ext), `domain-modeling` (ext, team) | Qualify material ambiguity, stress-test a design, maintain domain language |
| Requirements | `to-prd` (ext), `prd-interview` (team) | Create the requirement artifact appropriate to the execution mode |
| Design | `spec` (team/optional by mode), `prototype` (team), `design-taste-frontend` (ext, frontend) | Define technical or interaction contracts |
| Plan | `plan-sync` | Keep canonical-v2 execution state and evidence across sessions |
| Implement | `implement`, `systematic-debugging`; `reducing-entropy` (ext, optional) | RED→GREEN→REFACTOR, root-cause work, explicit entropy reduction |
| Verify | `verification-before-completion`, `qa` (team), `security` | Execute scoped machine gates and record evidence |
| Review/release | `caveman-review` (ext), `sync-work` | Review the change and perform authorized Git/release handoffs |
| Onboard | `shared-skill-onboarder` | Establish manifest, guardrails, and project-specific evidence |

Discovery cost, Research/Wayfinding, Selected Seam, and vertical-slice rules are
summarized in [Discovery and planning](docs/discovery-and-planning.md).

## Optional utilities

| Skill | Boundary |
|---|---|
| `codebase-understanding` | Deterministic Repo Map plus search/direct reading; not a semantic graph |
| `subagent-driven-development` (ext) | Execute a validated plan through isolated subagents and reviews |
| `markdown` | Convert and organize documentation artifacts |
| `humanizer` (ext) | Revise prose while preserving meaning and disclosure requirements |
| `reducing-entropy` (ext) | Manual-only deletion/consolidation pass measured by final code surface |

## Router flows

```text
探索 → 建造 → 發布
        ↑
修錯 ──┘
理解（read-only / optional utility）
```

Execution modes, conditional artifacts, and the three workflow human decisions
live in [`protocol-registry.json`](protocol-registry.json) and are presented by
[`skill-router/SKILL.md`](skill-router/SKILL.md). The registry is declarative
data plus conformance checks, not a runtime workflow engine.

## Historical consolidation

Private `_archive/` content and Git history retain earlier entry points. The
active surface keeps one owner for each capability; generated discovery roots
must not be edited directly. Earlier consolidation decisions are recorded in
[`docs/skills-reorg/decisions.md`](docs/skills-reorg/decisions.md).
