---
name: skill-router
description: |
  AI task dispatcher. Read first on each new task; five flows pick minimal skills and Execution Mode.
  Trigger keywords: conversation start, new task
source_kind: original
stage: skill
---

# Skill Router

Route intent to the smallest workflow; utilities trigger from their `description`. This file keeps only
cross-stage flows. Execution Mode machine source: [`../protocol-registry.json`](../protocol-registry.json);
it is a declarative contract, not runtime or scheduling.

## Global Iron Laws

1. Persist state and handoff results to files, not only in context.
2. Success claims must have fresh verification evidence.
3. Irreversible or external side effects (e.g. push, merge, delete, history rewrite) must get explicit confirmation first.

Before writing files, running commands, changing Git or calling external services, read guardrails and manifest;
if absent, probe repo conventions; ask only if irreversible actions stay unclear. Before dispatch, read needed `SKILL.md` and relevant
Domain Skill; resolve relative refs from that skill. Read-only tasks: no skeleton.

## Profile boundaries

- `personal`: seven core owners; light artifacts, direct verification.
- `team-sprint`: core plus formal PRD / Spec / QA / prototype / domain modeling.
- `frontend`: frontend work. `optional`: personal discovery, PRD, review, onboarding, utilities.

**personal profile hard rule**: `prd-interview`, `spec`, `qa`, `prototype`, `domain-modeling` are not in the bundle.

`brainstorming`, `grilling`, `to-prd`, `caveman-review`, `shared-skill-onboarder` and
utilities dispatch only with `CAPABILITY_PACKS=optional`; if absent, explain the selection; never simulate that
owner. `skill-creator` is maintainer-only.

## Task routing table

| Intent | Signal | Flow |
|---|---|---|
| Explore | Material ambiguity changing implementation, requirement interview, plan stress test | [Explore](#flow-explore) |
| Build | New feature, requirement change, refactor, implementation start | [Build](#flow-build) |
| Fix | bug, test failure, unexpected behavior | [Fix](#flow-fix) |
| Release | review, commit, PR, merge, branch recovery | [Release](#flow-release) |
| Understand | explore codebase, architecture, dependencies, domain | [Understand](#flow-understand) |

## Flow: Explore

To clarify "what to build" or stress-test decisions, with `optional` installed. `brainstorming` only handles material ambiguity that repo
evidence cannot answer and that changes scope, architecture, public behavior or acceptance.

```text
brainstorming (qualified discovery; artifact only for a durable handoff)
  → to-prd (consensus snapshot) or prd-interview (formal team interview)
  → grilling (stress test per question if high risk; durable docs mode only for handoff)
  → domain-modeling (if installed, writes `CONTEXT.md` / `docs/adr/`)
```

- Pick Skip / Quick / Standard / Deep by cost; Standard: at most three questions; Deep needs user consent.
- Skip clear micro-tasks, bugs, reviews, existing-spec work, repo-answerable questions.
- Answer facts from repo or authoritative source; Research only for qualified Standard / Deep decisions.
- Unresolved cross-session Fog enters Deep Wayfinding only with user consent; plan-sync only after the route is clear.
- personal hands off to optional `to-prd` only for durable consensus; team uses `prd-interview`.
- `grilling` stress-tests only high-risk options.

## Flow: Build

### Team feature

Execution Mode: `team-feature`.

```text
prd-interview → Human gate: PRD approval
  → spec → Human gate: team design approval
  → qa plan → plan-sync canonical plan → implement
  → qa validate → verification-before-completion
```

QA traceability and Plan Sync consistency: machine gates.

### Personal feature

Execution Mode: `personal-feature`.

```text
optional `to-prd` (if durable consensus needed) → plan-sync canonical (if multi-step or cross-session)
  → implement → verification-before-completion
```

### Refactor

Execution Mode: `refactor`.

```text
existing PRD or optional `to-prd` → spec (team, or high design risk)
  → implement → verification-before-completion
```

### Micro-task direct path

Native direct path only if all three hold:

| Condition | Objective boundary |
|---|---|
| One or few files | At most 3 related implementation files; tests and generated output not counted |
| No new dependency | No new package, plugin, service or dependency graph |
| No schema/API change | Persisted format, public API, events and cross-service contracts unchanged |

If any fails or is unsure: personal feature. Direct path: native implementation (failing
test first) → `verification-before-completion`; no work item or plan,
no `implement` dispatch.

Plan selection: work needing multi-step, handoff, resume or
drift tracking uses canonical `plan/plan.md`.

## Flow: Fix

Execution Mode: `bug-fix`. Conditional artifacts and handoff follow the registry.

```text
systematic-debugging (reproduction and root cause)
  → implement (observed failing test → fix)
  → verification-before-completion
```

Build, integration, test failures use it too; if anything is missing, record symptom, minimal repro, evidence.

## Flow: Release

```text
verification-before-completion
  → optional caveman-review (if needed and installed)
  → security
  → Human gate: release approval
  → sync-work
```

- `sync-work` is the single Git delivery entry for Scoped Save, Integrate, Finish, Recovery;
  its modes handle branch / commit / push / merge / PR / keep / discard.
- Verify review findings first; rerun evidence after Critical/Important fixes. Missing remote, permission or
  artifact: stop safely; never create a remote or bypass protected branches.

## Flow: Understand

If optional `codebase-understanding` is installed:

```text
codebase-understanding → architecture map / domain candidates
  → update manifest pointers if needed
```

Else use repo search and docs; onboarding shared skills needs optional
`shared-skill-onboarder`.

## Utility self-triggers

If installed and the description matches, read: for doc conversion use optional `markdown`; for shared skill
onboarding, optional `shared-skill-onboarder`; for lo-fi, team `prototype`; for multi-task subagent
work, optional `subagent-driven-development`; for skill creation or evals, maintainer
`skill-creator`.

## Dispatch Checklist

```text
□ One flow and Execution Mode chosen
□ Side-effect tasks read guardrails / manifest or logged fallback
□ Each dispatched skill actually read
□ No conditional artifact faked
□ Human gates stop only at PRD, team design, release
□ Completion claims have a fresh test report; a work item's `meta.yml` fills `documentation_impact` (see ARTIFACTS.md)
```
