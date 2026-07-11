---
name: plan-sync
description: |
  建立與維護跨 session、跨 agent 的 durable execution plan。Use when work has multiple dependent steps, needs handoff/resume, or decisions and scope may drift. Skip for one-off edits and use spec for a one-time technical design that does not need execution state.
  觸發關鍵字: plan-sync, implementation plan, execution plan, task handoff, resume plan, drift check, 實作前規劃, 任務交接, 跨 session, 需求漂移
compatibility: Python 3.10+ is required for the machine validation and status CLI.
source_kind: original
stage: plan
output: <work_root>/<slug>/plan/plan.md
---

# Plan Sync

Plan Sync keeps one current execution contract in the repository so a new
session or another agent can continue without reconstructing intent from chat.

> **Announce at start:** 「我正在使用 plan-sync 來建立或維護 durable execution plan。」

## Select the smallest durable surface

| Situation | Action |
|---|---|
| One-off edit or router micro-task | Skip plan-sync |
| One-time technical design, no execution tracking | Use `spec` |
| Multiple steps, handoff, resume, or Goal Mode execution | Create canonical `plan/plan.md` |
| A durable decision, scope change, blocker, or deviation occurs | Add `plan/journal.md` |

`canonical-v2` is the only Plan Sync format for personal and team work. Complexity
adds task detail or an optional journal, not a second planning schema or runtime.
All work-item paths and `meta.yml` transitions follow
[`../ARTIFACTS.md`](../ARTIFACTS.md).

## Canonical contract

```text
<work_root>/<slug>/
├── meta.yml
└── plan/
    ├── plan.md
    └── journal.md   # optional; semantic events only
```

Start from `templates/plan.md`. Record:

- `Plan`: format, current intent, scope, non-goals, and positive integer
  `Concurrency` (new plans write `1`; older plans safely default to `1`).
- `Sources`: typed durable references using exactly one of:
  `- local: <relative-path>[#<literal-stable-id>]`,
  `- user: <durable-opaque-reference>`, or
  `- external: <URL-or-durable-opaque-ID>`.
- `Tasks`: authored execution contracts, not mechanically generated prose.
- `Change Log`: short structural history for the plan file itself.

Do not copy full PRD, Spec, or QA content into the plan. Reference upstream IDs
and write only execution-specific sequencing, dependencies, and verification.

Every canonical task has:

- stable `Txx` and title;
- `Status` and `Depends On`;
- `Intent` and `Expected Result`;
- `Definition of Done` and replayable `Verification` (an exact command when the
  check has a command-line form).

A task may become `in_progress` or `done` only after every `Depends On` task is
`done`. A `blocked` task records `Blocker Reason` and a typed `Blocker Ref` in
its task metadata. When it resumes, retain those fields and add a typed
`Unblocked Ref`; prose in the journal does not clear structured blocker state.

Before setting a task to `done`, run every Verification item and add matching
records under `#### Verification Evidence`:

```text
- PASS | external:ci-run-123 | bash tests/test_feature.sh
```

The Verification text must exactly match its evidence record, the recorded
result must be PASS, and the local/external reference must identify a durable
result. Plan Sync validates reference, shape, and consistency only. It never
executes Verification, inspects whether an external runner really ran, or turns
an authored PASS into behavioral proof. Use separately executed verification
gates for release confidence.

Allowed states are `pending`, `in_progress`, `blocked`, `needs_review`, `done`,
and `superseded`. Keep only one `in_progress` task unless concurrent execution
is explicitly enabled by `Concurrency`. The configured limit is enforced and
dependency-ready tasks determine the next action; document order cannot bypass
dependencies. `Depends On` is authoritative; do not maintain a second inverse
`Blocks` list in new plans.

## Journal without log entropy

Create `journal.md` only when a fact cannot be recovered cleanly from the current
plan and Git diff. Allowed event types are:

- `decision`
- `scope_change`
- `blocker`
- `deviation`

Do not journal routine `pending -> done` transitions, command transcripts, or
full test output. Put execution evidence in the task, implement report, or QA
report. Keep each journal event short and link to the affected task or source.

## Four operations

### `create`

1. Resolve `<work_root>/<slug>` from the manifest or repo artifact convention.
2. Create `meta.yml` if this is the first stage, otherwise update only the plan stage.
3. Create `plan/plan.md` from the canonical template.
4. Run `planctl.py check` before handoff.

### `refresh`

Update current plan content when intent, scope, sequencing, dependency, or
verification changes. Mark affected completed work `needs_review` when its
completion evidence no longer proves the current contract.

### `drift-check`

After a material user decision, blocker, task transition, or handoff:

1. Compare the new fact with Plan, Sources, Tasks, and Verification.
2. Update current truth first.
3. Add a journal event only for decision/scope/blocker/deviation semantics.
4. Run consistency check and inspect compact status.

### `resume`

1. Read `plan.md` Plan and Sources.
2. Read the active task and its dependencies.
3. Read `journal.md` only if current state remains ambiguous.
4. Run `planctl.py status` and continue from its next action.

## Machine surface

Resolve `<plan-sync-dir>` from the actual skill location:

```bash
python <plan-sync-dir>/scripts/planctl.py check --plan-dir <plan-dir>
python <plan-sync-dir>/scripts/planctl.py status --plan-dir <plan-dir>
python <plan-sync-dir>/scripts/planctl.py status --plan-dir <plan-dir> --json
python <plan-sync-dir>/scripts/planctl.py status --plan-dir <plan-dir> --goal-status
```

`check` validates format, required task fields, references, dependencies, cycles,
the sibling work-item plan stage, and optional journal structure. Local Sources
resolve from `plan.md`, remain inside the Git workspace (including through
symlinks), exist, and use an exact literal-ID anchor when one is present.
Directories are valid local Sources only without anchors. `status` returns the
derived plan state, dependency-ready tasks, structured blockers, concurrency,
remaining counts, next action, and consistency result.

For Goal Mode, the native Goal owns continuation, budget, pause/resume, and
completion lifecycle. Plan Sync owns repository state. Surface the
`--goal-status` line after meaningful turns so transcript-only evaluators can
see current repository status. `plan_state=complete` never means the host Goal
is complete; the output explicitly reports `host_goal=unmanaged`. Never call a
platform Goal API from this skill.

## Handoff gate

Before `implement` or `subagent-driven-development` starts:

- plan reflects the latest user intent;
- every non-superseded task has valid dependencies and verification;
- blockers and deviations are visible;
- `planctl.py check` exits zero;
- sibling `meta.yml` has exactly one `plan` stage whose skill is `plan-sync` and
  whose file resolves to the current `plan/plan.md`.

Failure means repair the plan, not bypass the gate.

## Final response

```text
Planning artifact updated.

Mode: {create|refresh|drift-check|resume}
Plan: <work_root>/<slug>/plan/plan.md
Active task: {Txx|none}
Key change: {one line}
Validation: consistency check {passed|failed}
```
