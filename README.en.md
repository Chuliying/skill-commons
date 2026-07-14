# skill-commons

skill-commons keeps one verifiable, resumable engineering state for developers,
agents, tools, and sessions. Requirements, Spec, Plan, implementation state, and
verification evidence live in the repository instead of one chat transcript.

It is a portable feature-delivery protocol. Claude Code, Codex, and Cursor use their
supported adapters to read the same latest work state; the consuming repository and host
retain language, framework, scheduling, and runtime decisions.

[zh-TW](README.md) · [Spec-state protocol](docs/spec-state-protocol.md) ·
[Evaluation](docs/evaluation.md) · [Skill index](INDEX.md)

## Why it exists

Spec is the blueprint, Plan is the work sequence, `meta.yml` is the progress board,
tests are inspection records, and Git preserves change history. The shared state lets a
new collaborator determine the next task, blockers, changed intent, stale evidence, and
the proof behind completion or delivery claims.

Use it for work that crosses sessions, agents, tools, developers, or formal review
gates. Factual lookup and bounded micro-tasks take the shortest path without durable
ceremony. See [Spec-state protocol](docs/spec-state-protocol.md) and
[Discovery and planning](docs/discovery-and-planning.md).

## Quick Start

Git and Bash 3.2+ are required. The Claude Code settings merge uses `jq`. Plan Sync,
Repo Map, and full maintainer verification use Python 3.10+; the onboarding scan uses
Node.js 18+.

```bash
git submodule add git@github.com:Chuliying/skill-commons.git .agent/skills/_shared
git -C .agent/skills/_shared checkout v0.8.0

mkdir -p .agent
cp .agent/skills/_shared/shared-skill-onboarder/templates/project-manifest.md \
  .agent/project-manifest.md
${EDITOR:-vi} .agent/project-manifest.md
```

Select one delivery mode before onboarding:

```yaml
## skill-commons bootstrap

- submodule_path: .agent/skills/_shared
- platforms: claude-code, cursor, codex
- delivery_mode: personal
- capability_packs: # add frontend or optional when needed
```

`delivery_mode` is `personal` or `team-sprint`. Add `frontend` or `optional` capability
packs only when needed. Missing selection stops onboarding.

`v0.8.0` installs the current seven-skill core. Add the `optional` pack before
onboarding when you need discovery, a personal PRD, review, or onboarding skills.
Repositories that have not migrated may retain the `v0.7.1` legacy pin; see
[Bootstrap](bootstrap/README.md), [Profile support](docs/profile-platform-support.md), and the
[Submodule bridge](docs/skill-commons-submodule-bridge.md).

```bash
bash .agent/skills/_shared/bootstrap/onboard.sh
bash .agent/skills/_shared/bootstrap/manage.sh doctor
```

## After installation

Describe the task in natural language. For example, “add an export CSV feature” lets
Router choose the smallest workflow; work that must survive another session is recorded
under `docs/work/<slug>/`. To name a skill explicitly, say “use `implement`” or “use
`sync-work`.” See [INDEX.md](INDEX.md) for the complete list.

## Execution and trust model

| Selection | Surface |
|---|---|
| `personal` | implementation, debugging, verification, security, Git delivery |
| `team-sprint` | formal PRD, Spec, QA, prototype, and domain modeling |
| `frontend` pack | frontend design |
| `optional` pack | discovery, personal PRD, review, onboarding, and utilities |

`delivery_mode` selects the installed skill set.
`execution_mode` is the Router choice for one task and needs no manual setup; it
determines which documents that task needs.
Work and delivery states remain separate. See [ARTIFACTS.md](ARTIFACTS.md).

- Completion requires fresh verification evidence.
- PRD approval, team design approval, and release approval are human gates.
- Passing tests do not imply that a PR, merge, or deployment occurred.
- Push, merge, destructive recovery, discard, and publication require explicit
  authorization before the event.
- Top-level skills are the only source; generated discovery roots are fan-out outputs.

## Evidence boundary

The 2026-07-13 convergence checkpoint recorded 1,520 deterministic assertions with no
failures across artifact, Plan, profile, adapter generation, bootstrap, and release
contracts. That checkpoint establishes repository conformance only; team speed and
cross-tool handoff value remain unmeasured.

In the frozen replay, all-preload used 64.9% more mean input tokens than no workflow;
Router-first used 37.5% more and 16.6% fewer than all-preload. Earlier quality scores
were invalidated because anonymous packets leaked arm identity. In the repaired blind
scoring of eight cases, all-preload and Router-first passed 60/60 rubric items and no
workflow passed 57/60, while no workflow had the best mean preference rank. This small
descriptive sample proves no general quality advantage, so quality and usability remain
outside product claims. The final adversarial review also found a self-verification
timing defect, so the complete ten-session protocol did not pass.

The next product test is a transcript-free cold-start handoff with Spec drift. See
[Evaluation](docs/evaluation.md).

## Documentation

- [Spec-state protocol](docs/spec-state-protocol.md)
- [Discovery and planning](docs/discovery-and-planning.md)
- [Evaluation and evidence](docs/evaluation.md)
- [Skill index](INDEX.md)
- [Artifact contract](ARTIFACTS.md)
- [Bootstrap and local management](bootstrap/README.md)
- [Platform support](docs/profile-platform-support.md)
- [Changelog](CHANGELOG.md) and [contributing guide](CONTRIBUTING.md)

## Maintainer verification

```bash
PROFILE=all bash bootstrap/generate.sh
bash tests/run-all.sh
```

Release, push, PR, merge, tag, and publication require separate authorization.
