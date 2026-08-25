# skill-commons

skill-commons is a repository-native workflow kit for AI-assisted engineering. It keeps
requirements, Spec, Plan, implementation state, verification evidence, and delivery
authorization in Git so developers, Claude Code, Codex, and Cursor resume from the same
latest work state.

[zh-TW](README.md) · [Interactive Repo Map](https://skill-commons-map.vercel.app) · [Quick Start](#quick-start) · [References](#references)

## Scope

The product is a verifiable, resumable shared engineering state: Spec is the blueprint,
Plan is the work sequence, `meta.yml` is the progress board, tests are inspection
records, and Git preserves change history. Use it for work that crosses sessions,
agents, tools, developers, or formal review gates; factual lookups and bounded
micro-tasks take the shortest path without durable ceremony.

Upstream ecosystems ([Agent Skills](https://agentskills.io/specification),
[Superpowers](https://github.com/obra/superpowers)) cover portable skills and
development methods; this project adds the shared contract layer above them —
repository artifacts, Plans, evidence, and the delivery contract. External sources,
pinned commits, and local patches live in [SOURCES.md](SOURCES.md).

## Capabilities

| Capability | In one line | How |
|---|---|---|
| Task routing | Router picks the smallest execution mode and artifact set per task; clear small changes take the direct path | [skill-router](skill-router/SKILL.md) |
| Durable handoff | Dependencies, blockers, DoD, and evidence survive in `docs/work/<slug>/`; a second session resumes from repository state alone | [plan-sync](plan-sync/SKILL.md) · [Spec-state protocol](docs/spec-state-protocol.md) |
| State entry point | `project-status` reports state, attention points, and the next action — read-only, deterministic, no LLM | [ARTIFACTS.md](ARTIFACTS.md) |
| Cross-repo detection | A task depending on work outside this repo triggers detection and an explicit confirmation; participants live in the Plan and evidence stays in its own repo | [Cross-repo contract](docs/cross-repo-contract.md) |
| Cross-tool install | Top-level skills stay the single source; onboarding generates per-platform adapters, with skill fan-out covering Claude Code and Codex while Cursor receives the rule + AGENTS adapter; a consuming repo pins the version as a submodule | [Bootstrap](bootstrap/README.md) · [Platform support](docs/profile-platform-support.md) |
| Delivery authorization | Work completion and outward delivery stay separately recorded; push, merge, discard, destructive recovery, and publication require explicit authorization first | [ARTIFACTS.md](ARTIFACTS.md) · [sync-work](sync-work/SKILL.md) |

`delivery_mode` selects the installed skill set (`personal`, `team-sprint`, plus
`frontend` and `optional` capability packs);
`execution_mode` is the Router choice for one task and needs no manual setup. See [INDEX.md](INDEX.md) for the per-skill mapping and
[Discovery and planning](docs/discovery-and-planning.md) for requirement discovery.

## Verification

| Layer | What is checked | How |
|---|---|---|
| Composition | source, generated adapters, profiles, provenance | [INDEX](INDEX.md) · [SOURCES](SOURCES.md) |
| Contract | work items, registry, Plans, artifacts, links, delivery evidence | [Cross-repo contract](docs/cross-repo-contract.md) |
| Behavior | unit/integration/e2e, bootstrap safety, security, release convergence | [Evaluation](docs/evaluation.md) |
| Agent journey | isolated personal/team/bug/refactor/release scenarios | [Journey evals](journey-evals/README.md) |

Completion claims require fresh verification evidence, and every completed piece of
work records one documentation-impact result. PRD approval, team design approval, and
release approval are the three workflow human gates; push, merge, discard, destructive
recovery, and publication require explicit authorization first. Deterministic gates
establish repository conformance for the tested revision; team speed, model-output
quality, token cost, and cross-tool handoff value still require independent experiments — see
[Evaluation](docs/evaluation.md) for methods, data, and claim limits.

Maintainer full verification (commit, tag, push, PR, merge, and publication require
separate authorization):

```bash
PROFILE=all bash bootstrap/generate.sh
bash tests/verify.sh
```

## Quick Start

Git and Bash 3.2+ are required. The Claude Code settings merge uses `jq`; full
verification uses Python 3.10+; the onboarding scan uses Node.js 18+.

```bash
git submodule add git@github.com:Chuliying/skill-commons.git .agent/skills/_shared
git -C .agent/skills/_shared checkout v0.10.0
mkdir -p .agent
cp .agent/skills/_shared/shared-skill-onboarder/templates/project-manifest.md \
  .agent/project-manifest.md
```

In the manifest, choose platforms, exactly one `delivery_mode`, and add `optional` to
`capability_packs` first when you need discovery, review, or onboarding skills:

```yaml
## skill-commons bootstrap
- submodule_path: .agent/skills/_shared
- platforms: claude-code, cursor, codex
- delivery_mode: personal
- capability_packs: optional
```

```bash
bash .agent/skills/_shared/bootstrap/onboard.sh
bash .agent/skills/_shared/bootstrap/manage.sh doctor
```

## After installation

Describe the task in natural language — for example, “add an export CSV feature and
run verification before finishing” — and Router picks the shortest workflow. For a state
summary:

```bash
bash .agent/skills/_shared/scripts/project-status.sh
bash .agent/skills/_shared/scripts/project-status.sh --json
```

Operational flows — missing submodule, selection errors, doctor drift, uninstall, and
legacy adoption — live in the
[Submodule bridge](docs/skill-commons-submodule-bridge.md) and
[Bootstrap](bootstrap/README.md).

## References

- Use: [Bootstrap](bootstrap/README.md) · [Submodule bridge](docs/skill-commons-submodule-bridge.md) · [Platform support](docs/profile-platform-support.md) · [Skill index](INDEX.md)
- Contract: [Spec-state protocol](docs/spec-state-protocol.md) · [Artifacts](ARTIFACTS.md) · [Protocol registry](protocol-registry.json) · [Cross-repo contract](docs/cross-repo-contract.md) · [Discovery/plan](docs/discovery-and-planning.md)
- Evidence: [Evaluation](docs/evaluation.md) · [Journey evals](journey-evals/README.md)
- Sources: [SOURCES](SOURCES.md) · [Agent Skills spec](https://agentskills.io/specification) · [Superpowers](https://github.com/obra/superpowers)
- Maintenance: [CONTRIBUTING](CONTRIBUTING.md) · [CHANGELOG](CHANGELOG.md) · [STYLE](STYLE.md) · [Gate package](GATE-PACKAGE.md) · [Decisions](docs/skills-reorg/decisions.md)
