---
name: plan-sync
description: |
  建立與維護跨 session、跨 agent 的 durable execution plan。Use for dependent steps, handoff/resume, Goal Mode, or drift. Skip one-off edits; use spec for design without execution state.
  觸發關鍵字: plan-sync, implementation plan, execution plan, task handoff, resume plan, drift check, 實作前規劃, 任務交接, 跨 session, 需求漂移
compatibility: Python 3.10+ for validation and status CLI.
source_kind: original
stage: plan
output: <work_root>/<slug>/plan/plan.md
---

# Plan Sync

Keep one repository execution contract that another session or agent can resume.

> **progress/commentary only:** 簡短告知正在使用；final answer/artifact 不重複 skill name 或 routing taxonomy。

## Select the smallest durable surface

| Situation | Action |
|---|---|
| One-off edit or router micro-task | Skip plan-sync |
| One-time design without execution state | Use `spec` |
| Multiple steps, handoff, resume, or Goal Mode | Create `plan/plan.md` |
| Durable decision, scope change, blocker, or deviation | Add `plan/journal.md` |

`canonical-v2` is the only format. Complexity adds task detail or an optional journal,
never another schema or runtime. Paths and `meta.yml` follow
[`../ARTIFACTS.md`](../ARTIFACTS.md).

## Canonical contract

Write `<work_root>/<slug>/plan/plan.md` from `templates/plan.md`. Record:

- `Plan`: format, intent, scope, non-goals, and positive `Concurrency` (write `1`;
  older plans default to `1`).
- `Sources`: one typed durable reference per entry:
  `- local: <relative-path>[#<literal-stable-id>]`,
  `- user: <durable-opaque-reference>`, or
  `- external: <URL-or-durable-opaque-ID>`.
- `Tasks`: authored execution contracts; `Change Log`: short structural history.

Reference upstream IDs instead of copying PRD, Spec, or QA prose. Every task has stable
`Txx`, title, `Status`, `Depends On`, `Intent`, `Expected Result`, `Definition of Done`,
and replayable `Verification` with an exact command when available.

## Task decomposition

For a behavior-changing feature, prefer a task demoable or verifiable end to end across
its required boundaries. Fit one fresh context where practical and leave the integrated
system supported. Express this with existing fields; add no slice schema.

Documentation-only and standalone maintainer tools use their own observable output,
without a horizontal exception label.

A horizontal exception states why no observable integrated increment exists and names
the next integration checkpoint restoring end-to-end verification. A label alone is
not evidence.

For a wide refactor use expand → migrate → contract: add the new form, migrate bounded
caller batches while checks stay green, then remove the old. Name the integration
checkpoint if a batch cannot stay green alone. Dependency-ready tasks form the frontier.

Enter `in_progress` or `done` only after every dependency is `done`. A `blocked` task
records `Blocker Reason` and typed `Blocker Ref`; resume retains them and adds typed
`Unblocked Ref`. Journal prose cannot clear blocker state.

Before setting a task to `done`, run every Verification item and add matching
records under `#### Verification Evidence`:

```text
- PASS | external:ci-run-123 | bash tests/test_feature.sh
```

Verification text and evidence command must match; result is PASS with a durable
local/external reference. Plan Sync validates reference, shape, and consistency only;
it never executes checks or turns an authored PASS into behavioral proof. Release
confidence needs separately executed verification.

States: `pending`, `in_progress`, `blocked`, `needs_review`, `done`, `superseded`.
`Concurrency` limits active tasks; dependency-ready work determines the next action.
`Depends On` is authoritative, so new plans omit inverse `Blocks` lists.

## Journal without log entropy

Create `journal.md` only when current plan and Git diff cannot recover a fact.
Allowed events: `decision`, `scope_change`, `blocker`, `deviation`.

Skip routine transitions, transcripts, and test output. Put evidence in the task,
implement report, or QA report; link each short event to its task or source.

## Operations

- `create`: resolve the work item, update its plan stage, render the template, run `check`.
- `refresh`: update changed truth; use `needs_review` when old evidence no longer proves it.
- `drift-check`: update truth, journal semantic events, run consistency and compact status.
- `resume`: read Plan, Sources, active task, and dependencies; read journal if still
  ambiguous, then continue from `status`.

## Machine surface

Resolve `<plan-sync-dir>` from the actual skill location:

```bash
python <plan-sync-dir>/scripts/planctl.py check --plan-dir <plan-dir>
python <plan-sync-dir>/scripts/planctl.py status --plan-dir <plan-dir> [--json]
python <plan-sync-dir>/scripts/planctl.py status --plan-dir <plan-dir> --goal-status
```

`check` covers format, tasks, references, dependencies, cycles, sibling plan stage, and
journal. Local Sources resolve from `plan.md`, stay inside the Git workspace through
symlinks, exist, and use exact literal-ID anchors; directories cannot use anchors.
`status` derives ready work, blockers, concurrency, counts, next action, and consistency.

In Goal Mode the host owns lifecycle and budget; Plan Sync owns repository state. Surface
`--goal-status` after meaningful turns. Complete plans report `host_goal=unmanaged`;
this skill never calls a Goal API.

## Handoff gate

Before implementation: current intent, dependencies, verification, blockers, and
deviations are visible; `check` exits zero. The sibling metadata contains a `plan`
stage whose `skill` is `plan-sync` and whose file resolves to this `plan/plan.md`.

Failure means repair the plan before handoff. Report operation, plan path, active task,
key change, and consistency result.
