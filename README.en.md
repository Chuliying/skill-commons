# skill-commons

skill-commons is a repository-native workflow kit for AI-assisted engineering. It keeps
requirements, Spec, Plan, implementation state, and verification evidence in Git so
developers, Claude Code, Codex, and Cursor can resume from the same latest work state.

Describe a task in natural language and Router selects the shortest viable workflow.
Work that must survive another session stays in the repository. `v0.9.0` adds
`project-status`, a deterministic, read-only, no-LLM view of current state and next action.

[zh-TW](README.md) · [Spec-state protocol](docs/spec-state-protocol.md) ·
[Evaluation](docs/evaluation.md) · [Skill index](INDEX.md)

## Why it exists

The product is a verifiable, resumable shared engineering state. Spec is the blueprint,
Plan is the work sequence, `meta.yml` is the progress board, tests are inspection records,
and Git preserves change history. A new collaborator can find the next task, blockers,
changed intent, stale evidence, and proof behind completion or delivery claims.

`project-status` reads bootstrap, work-item, Plan, and Git state, then reports attention
points and the next rule-based action. It does not modify the project or guess which
active work item should win.

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
git -C .agent/skills/_shared checkout v0.9.0

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

`v0.9.0` installs the current seven-skill core. Add the `optional` pack before
onboarding when you need discovery, a personal PRD, review, or onboarding skills.
Repositories that have not migrated may retain the `v0.7.1` legacy pin; see
[Bootstrap](bootstrap/README.md), [Profile support](docs/profile-platform-support.md), and the
[Submodule bridge](docs/skill-commons-submodule-bridge.md).

```bash
bash .agent/skills/_shared/bootstrap/onboard.sh
bash .agent/skills/_shared/bootstrap/manage.sh doctor
```

### Read project state

From the consuming repository root:

```bash
bash .agent/skills/_shared/scripts/project-status.sh
bash .agent/skills/_shared/scripts/project-status.sh --json
```

The default output is for people; `--json` provides a stable machine-readable schema.
Both read bootstrap health, work items, canonical Plans, the Git working tree, and
active-work ambiguity without changing the project.

## After installation

Describe the task in natural language. For example, “add an export CSV feature” lets
Router choose the smallest workflow; work that must survive another session is recorded
under `docs/work/<slug>/`. To name a skill explicitly, say “use `implement`” or “use
`sync-work`.” See [INDEX.md](INDEX.md) for the complete list.

## Execution and trust model

Router selects an explore, build, fix, understand, or release flow for each task. Plans
and evidence that must survive a session live under `docs/work/<slug>/`; Git delivery
still waits for explicit authorization after the work is complete.

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

The maintainer gate checks source, generated adapters, artifact/Plan/profile contracts,
bootstrap safety, secret preflight, and the clean public export. `bash tests/run-all.sh`
is the complete release gate.

These checks establish repository conformance. Team speed, model-output quality, and
cross-tool handoff value remain unproven. Historical benchmark figures without private
replay artifacts are retained only as unverified narrative. The next product test is a
transcript-free, cross-tool cold-start handoff with Spec drift; see
[Evaluation](docs/evaluation.md) for methods, data, and limits.

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
