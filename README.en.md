# skill-commons

skill-commons is a repository-resident, portable feature-delivery protocol and
skill toolkit for Claude Code, Codex, and Cursor. v0.7.0 stores execution state
in versioned project artifacts, keeps machine contracts declarative, and
provides local conformance tools. Portability covers the artifacts and protocol.
Host capabilities still vary.

The skill sources are maintained in zh-TW. This page summarizes the public
contract for English readers. Automated fixtures cover Python CLI and
TypeScript/Web repository shapes. Other languages, frameworks, and deployment
environments require their own validation.

## Scope and boundaries

- Claude Code and Codex receive selected skills through generated discovery
  roots. Cursor receives a rule plus `AGENTS.md` only.
- `protocol-registry.json` describes execution modes, artifact requirements,
  lifecycle evidence, and profiles. Conformance checks consume this data;
  execution and scheduling stay with the host and user.
- Artifacts are conditional. A team feature requires the formal PRD, Spec,
  Plan, QA plan/report, and implementation report chain. Personal features,
  bug fixes, and refactors deliberately omit or make some of those artifacts
  optional.
- `work_status` records completion of requested work. `delivery_status`
  separately records approval, PR, merge, and deployment events using actual
  evidence. Delivery evidence begins with an approval or remote event record.
- The built-in scanner performs a heuristic secret preflight. Comprehensive
  security coverage also requires separate dependency, auth, and operation
  reviews where applicable.

## Delivery selection and platforms

Every consuming repository selects exactly one `delivery_mode`: `personal` or
`team-sprint`. It may add the `frontend` and `optional` capability packs.
Omitting the delivery mode stops onboarding before installation.
The legacy `profile` form exists only for migration, and `PROFILE=all` is an
explicit maintainer command.

| Platform | Adapter |
|---|---|
| Claude Code | `.claude/skills/` fan-out, `CLAUDE.md`, and SessionStart hook |
| Codex | `.codex/skills/` fan-out and `AGENTS.md` |
| Cursor | Cursor rule plus `AGENTS.md`; no skill fan-out |

Fan-out copies selected top-level sources and shared runtime files into host
discovery roots. An ownership ledger limits later updates and uninstall to
managed entries, preserving foreign skills and files.

## Requirements and Quick Start

Git with submodule support and Bash 3.2+ are the base requirements; the macOS
system Bash is sufficient. `jq` is needed for the Claude Code settings merge.
Python 3.10+ is required for Plan Sync, Repo Map, some optional utilities, and
full repository verification. Node.js 18+ is limited to the onboarding scan and
maintainer fixtures. Base fan-out uses the shell tooling above.

Pin the `v0.7.0` tag when adding the submodule:

```bash
git submodule add git@github.com:Chuliying/skill-commons.git .agent/skills/_shared
git -C .agent/skills/_shared checkout v0.7.0

mkdir -p .agent
cp .agent/skills/_shared/shared-skill-onboarder/templates/project-manifest.md \
  .agent/project-manifest.md
${EDITOR:-vi} .agent/project-manifest.md
```

Confirm the selection before onboarding:

```yaml
## skill-commons bootstrap

- submodule_path: .agent/skills/_shared
- platforms: claude-code, cursor, codex
- delivery_mode: personal
- capability_packs:
```

Then run:

```bash
bash .agent/skills/_shared/bootstrap/onboard.sh
bash .agent/skills/_shared/bootstrap/manage.sh doctor
```

## Brainstorming qualification and cost

`brainstorming` loads only for material ambiguity that would change scope,
architecture, public behavior, or acceptance criteria when repository evidence
leaves the answer open. Clear
micro-tasks, bug diagnosis, reviews, approved-spec implementation, and read-only
questions skip it.

The interaction budget is explicit: Skip asks nothing, Quick asks at most one
question, Standard asks at most three questions with at most two options per
decision and one final confirmation, and Deep requires an explained scope and
explicit user agreement. A durable `brainstorm.md` is conditional on a
cross-session, cross-agent, formal team handoff, or user request.

Contract tests verify these written boundaries and fixture coverage. Claims
about model trigger accuracy, token or time savings, and outcomes require
repeated with-skill/without-skill runs
under the same prompt, model, and host, followed by human adjudication; v0.7
makes no such empirical claim.

## Plan Sync and host Goal Mode

Plan Sync owns the durable, repository-local execution contract. Host Goal Mode
owns continuation, budget, pause/resume, and host completion. They can be used
together. The host retains its Goal API and completion lifecycle. Plan Sync
reports `host_goal=unmanaged` so repository completion and host completion stay
separate.

v0.7 supports canonical-v2 `plan/plan.md` only. A lite-v1 plan or retired
`implementation.md`/`tasks.md`/`notes.md` input fails closed with two choices:
migrate current truth to canonical-v2, or stay pinned to skill-commons v0.6
until migration is possible.

`planctl` validates recorded-evidence references, shape, and consistency.
Executed Verify or QA gates provide behavioral evidence and authorship context.
Repository plan state is a portable handoff record; release confidence still
depends on separately executed Verify or QA gates.

## Repo Map and optional visualization

Repo Map provides deterministic `scan` and `status` commands using a Git
worktree and the Python standard library. Python imports are AST-derived.
JS/TS edges are line-oriented literal `textual_candidate` records: a multiline
`} from "x"` tail is detectable; a specifier split onto another line may be
missed. An unresolved `module_reference` remains a textual candidate until a
separate resolver establishes dependency, caller/callee, impact, or semantic graph
meaning.

Status is currently O(repo), and v1 uses full rebuilds rather than an
incremental database. Understand-Anything remains an external, optional
visualization reference. Repo Map owns freshness, and repository gates own
release decisions.

## Upgrade and local management

Before running the v0.7 tools, edit the consuming repository's
`.agent/project-manifest.md`. Remove the blank `- profile:` from the v0.6
template and replace it with an explicit selection. Legacy and new fields are
mutually exclusive:

```yaml
## skill-commons bootstrap

- submodule_path: .agent/skills/_shared
- platforms: claude-code, cursor, codex
- delivery_mode: personal
- capability_packs:
```

Use `team-sprint` where the formal team flow is required, and add `frontend`
or `optional` packs deliberately. Then move the submodule to a reviewed
revision.

`manage.sh update` re-runs onboarding from the submodule revision already
checked out. Fetch and select a reviewed tag first:

```bash
git -C .agent/skills/_shared fetch --tags
git -C .agent/skills/_shared checkout v0.7.0
bash .agent/skills/_shared/bootstrap/manage.sh update
bash .agent/skills/_shared/bootstrap/manage.sh doctor
```

For changed pre-ledger v0.6 output, review the target before one explicit
adoption run:

```bash
SKILL_COMMONS_ADOPT_LEGACY=1 \
  bash .agent/skills/_shared/bootstrap/onboard.sh
```

`doctor` is a strict read-only health check. `uninstall` removes validated
ledger-owned entries and managed adapter blocks while preserving foreign
content, the project manifest, guardrails, and the submodule:

```bash
bash .agent/skills/_shared/bootstrap/manage.sh doctor [project-root]
bash .agent/skills/_shared/bootstrap/manage.sh update [project-root]
bash .agent/skills/_shared/bootstrap/manage.sh uninstall [project-root]
```

Platform shrink is explicit. If a deselected platform still has managed
artifacts, `doctor`, `update`, and `uninstall` stop before mutation. Restore the
previous selection, run `uninstall`, then choose the smaller set and run
`onboard.sh` again.

`submodule_path` must stay project-relative. Existing path components may not
be symlinks or non-directories; bootstrap rejects them before publishing a
SessionStart hook.

See the [zh-TW README](README.md), [artifact contract](ARTIFACTS.md),
[skill index](INDEX.md), and [submodule bridge](docs/skill-commons-submodule-bridge.md)
for the complete operating contract.
