# skill-commons

skill-commons is a repository-native workflow kit for AI-assisted engineering. It keeps
requirements, Spec, Plan, implementation state, verification evidence, and delivery
authorization in Git so developers, Claude Code, Codex, and Cursor resume from the same
latest work state.

What it adds: **done and approved stay true only while the content they covered is unchanged.** Change the code after a work item passed, and its verification turns stale. Change an acceptance criterion after someone approved it, and the approval turns stale. `project-status` reports this for completed, undelivered work items, and for active items once evidence is recorded, without rerunning the tests.

[zh-TW](README.md) · [Interactive Repo Map](https://skill-commons-map.vercel.app) · [Quick Start](#quick-start) · [References](#references)

## Scope

The product is a verifiable, resumable shared engineering state: Spec is the blueprint,
Plan is the work sequence, `meta.yml` is the progress board, tests and review are the
acceptance evidence, and Git preserves change history. Use it for work that crosses sessions,
agents, tools, developers, or formal review gates; factual lookups and bounded
micro-tasks take the shortest path without durable ceremony. The full model of Spec drift and
handoff boundaries is in the [Spec-state protocol](docs/spec-state-protocol.md).

Upstream ecosystems ([Agent Skills](https://agentskills.io/specification),
[Superpowers](https://github.com/obra/superpowers)) cover portable skills and
development methods; this project adds the shared contract layer above them —
repository artifacts, Plans, evidence, and the delivery contract. External sources,
pinned commits, and local patches live in [SOURCES.md](SOURCES.md).

How it compares: in a pre-registered test in October 2026 (a small Python CLI and one feature, then a one-line code change and a one-sentence criterion change after "done"), SpecWeave 3.1.15's status still said Completed after both changes, and Spec Kit 1.2.5's status command showed no per-item state. SpecWeave's `verify` does catch the code change when you rerun it, and an LLM convergence step in one Spec Kit run flagged both changes; the difference tested here is a status command that, when run again, flags the change without rerunning tests or an LLM review. Neither core flow produced an approval with approver, scope and content fingerprint (Spec Kit's optional review gates were not exercised; SpecWeave records commit SHAs on task evidence). At commit `6f7ae22`, skill-commons flagged both changes in all three recorded runs; two completed the prescribed install and the third's install was inconclusive. Earlier versions failed parts of this test and were fixed against it; the competitor runs were not repeated. In November 2026 the same test was run once each on two agent-verification tools: Lians 0.5.0 also marked the work stale after the code change, but for any change in the workspace, including a sentence outside the criteria; ProofFlow v0.1.8 kept reporting `ready_for_review` after the tests broke, because it reads what the agent recorded. Details: [Evaluation](docs/evaluation.md#competitor-comparison-october-2026).

Content-sensitive review is established practice, for example [Doorstop's suspect links](https://doorstop.readthedocs.io/en/v3.2/cli/validation.html) and [GitHub's dismissal of stale approvals](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-protected-branches/about-protected-branches). skill-commons brings it to agent work items and acceptance criteria. SpecWeave also records which agent claimed a task and when, so tool and time tracking is shared ground.

## Capabilities

| Capability | In one line | How |
|---|---|---|
| Done expires with content | Verification evidence fingerprints the verified files and acceptance criteria; for completed, undelivered work items a later change shows as stale, and missing or failed evidence shows as attention | [verification](verification-before-completion/SKILL.md) · [ARTIFACTS.md](ARTIFACTS.md) |
| Approval bound to content | `approve` records who approved which acceptance criteria and their fingerprints, and whether a person confirmed it in a terminal or an agent reported it; editing a criterion makes the approval stale (whitespace is collapsed and punctuation counts as a word break; a recorded `reaffirm` accepts an edit with a reason) | [ARTIFACTS.md](ARTIFACTS.md) |
| One list of all work | `project-status.sh --ledger` lists every work item, backlog included, with stage files, the verification and approval state where they apply, and the latest activity with its AI tool and session; `--ledger --json` has the full per-command history | [ARTIFACTS.md](ARTIFACTS.md) |
| Allowed scope | Optional `allowed_paths` in a work item's `meta.yml`; `verify.sh --work-item` and `project-status` list changes outside it since the item started, including a committed `__pycache__` | [ARTIFACTS.md](ARTIFACTS.md) |
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

Known limits: in the test's fresh two-agent repository, the install added six root entries (`.agent/` with the submodule inside, `.gitmodules`, `.claude/`, `.agents/`, `AGENTS.md`, `CLAUDE.md`), plus `.gitignore` when the repository had none; the install added 8 tracked entries, including the submodule gitlink (10 total with the two starter files). The installed checkout held 466 files. Spec Kit's Claude-only install added two. Counts vary with the selected platforms. The AI tool and session are what the agent environment reports (Cursor reports no session), and an approval records whether a person confirmed it in a terminal or an agent reported it; a process that gets a terminal and clears the agent variables can still record `terminal`, so treat neither as identity verification. Approval covers the criteria text; verification covers the code. Generated files and the first-use path are English; some installed skills, including `security`, still contain Traditional Chinese. In one cloud run onboarding stopped without output and could not be reproduced; check that `AGENTS.md` exists after the second command. A separate fresh cloud clone left the submodule uninitialized. A local probe found that the hook generated files after initial skill discovery. See [fresh-clone setup](docs/skill-commons-submodule-bridge.md#layout).

Maintainer full verification (commit, tag, push, PR, merge, and publication require
separate authorization):

```bash
PROFILE=all bash bootstrap/generate.sh
bash tests/verify.sh
```

## Quick Start

You need Git and Bash 3.2+; the Claude Code platform needs `jq`. `project-status`, `work-items` and verification evidence need Python 3.10+; the onboarding scan also needs Node.js 18+. Run two commands in your project root:

```bash
git submodule add https://github.com/Chuliying/skill-commons.git .agent/skills/_shared
bash .agent/skills/_shared/bootstrap/onboard.sh
```

No SSH key and no questions. The first run creates a default manifest (`personal` plus the `optional` pack; platforms follow the repository's existing `.claude`, `.codex` or `.cursor`, otherwise Claude Code and Codex), derives the test command and source roots from project files, and writes `.agent/`, each platform's skill directory, `AGENTS.md`, and a `CLAUDE.md` that imports `AGENTS.md`. The skill directories are generated copies: onboarding lists their files in `.gitignore`, so they stay out of commits and pull requests, and once the submodule is initialised (`git submodule update --init`), the session-start check can regenerate them from the committed manifest and existing ignore rules (in Codex, run `check.sh` first, as `AGENTS.md` says). Earlier installs committed the copies; see the [bridge document](docs/skill-commons-submodule-bridge.md) for the one-commit migration. Start the first piece of work with `bash .agent/skills/_shared/scripts/work-items.sh new <slug>`. The submodule stays pinned to the commit it was added at.

### Advanced setup

- Pin a release: `git -C .agent/skills/_shared checkout v0.13.0`, then run `onboard.sh` again. The content-bound verification, approvals, ledger and work-item commands described here ship in `v0.13.0`.
- Change platforms, `delivery_mode` or capability packs: edit the generated `.agent/project-manifest.md`, then run `onboard.sh` again. The example below enables all three platforms; remove `optional` for the smallest skill set:

```yaml
- submodule_path: .agent/skills/_shared
- platforms: claude-code, codex, cursor
- delivery_mode: personal
- capability_packs: optional
```

- Check the installation: `bash .agent/skills/_shared/bootstrap/manage.sh doctor`.

## After installation

Describe the task in natural language — for example, “add an export CSV feature and
run verification before finishing” — and Router picks the shortest workflow. The installed
`AGENTS.md` gives the agent these commands; each belongs to a stage, run from the project root:

```bash
S=.agent/skills/_shared
bash "$S/scripts/work-items.sh" new export-csv            # creates meta.yml, a PRD skeleton and a report stub
bash "$S/scripts/work-items.sh" new later-idea --queued   # backlog item
bash "$S/scripts/work-items.sh" start later-idea          # when you begin the backlog item
# fill the PRD, implement with tests, then:
bash "$S/verification-before-completion/scripts/verify.sh" --work-item export-csv
# the person approves in their own terminal (types yes); an agent with no shell to hand over adds
# --by user:sam --agent-reported --quote "<their words>"
python3 "$S/scripts/verification_evidence.py" approve --work-item export-csv
bash "$S/scripts/work-items.sh" complete export-csv --na "no project document needs an update"
bash "$S/verification-before-completion/scripts/verify.sh" --work-item export-csv
```

Use `complete ... --doc README.md` instead of `--na` when the work updated a project document.

For state:

```bash
bash .agent/skills/_shared/scripts/project-status.sh
bash .agent/skills/_shared/scripts/project-status.sh --json
bash .agent/skills/_shared/scripts/project-status.sh --ledger   # one row per item: stages, verification, approval, AI tool and session
```

Operational flows — missing submodule, selection errors, doctor drift, uninstall, and
legacy adoption — live in the
[Submodule bridge](docs/skill-commons-submodule-bridge.md) and
[Bootstrap](bootstrap/README.md).

## Contributors

- [Chuliying](https://github.com/Chuliying): maintainer
- [Renee Wang (@ItsReneeWang)](https://github.com/ItsReneeWang): designed and built the production prototype skills that the prototype contract redesign used as a reference

## References

- Use: [Bootstrap](bootstrap/README.md) · [Submodule bridge](docs/skill-commons-submodule-bridge.md) · [Platform support](docs/profile-platform-support.md) · [Skill index](INDEX.md)
- Contract: [Spec-state protocol](docs/spec-state-protocol.md) · [Artifacts](ARTIFACTS.md) · [Protocol registry](protocol-registry.json) · [Cross-repo contract](docs/cross-repo-contract.md) · [Discovery/plan](docs/discovery-and-planning.md)
- Evidence: [Evaluation](docs/evaluation.md) · [Journey evals](journey-evals/README.md)
- Sources: [SOURCES](SOURCES.md) · [Agent Skills spec](https://agentskills.io/specification) · [Superpowers](https://github.com/obra/superpowers)
- Maintenance: [CONTRIBUTING](CONTRIBUTING.md) · [CHANGELOG](CHANGELOG.md) · [STYLE](STYLE.md) · [Gate package](GATE-PACKAGE.md) · [Decisions](docs/skills-reorg/decisions.md)
