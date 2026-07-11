# Work-Item Artifact Contract v3

Durable workflow outputs for one feature, fix, or change live together:

```text
<work_root>/<slug>/              # work_root defaults to docs/work
├── meta.yml
├── brainstorm.md
├── prd.md
├── spec.md
├── plan/
│   ├── plan.md                    # canonical planning contract
│   └── journal.md                 # optional semantic decisions/blockers
├── adr.md
├── glossary.md
├── prototype/index.html
├── qa-plan.md
├── implement-report.md
└── qa-report.md
```

The first workflow stage creates a unique, kebab-case `<slug>` without a date.
Every later stage reuses it. If the directory already exists for a different
work item, stop and ask for another slug. A hotfix may contain only `meta.yml`
and `implement-report.md`.

Each work item has one `meta.yml`; stages append or update their own entry:

The machine-owned execution modes, artifact requirements, lifecycle values, and
delivery evidence requirements live in
[`protocol-registry.json`](protocol-registry.json). The example below is the
human-facing `work-item/v3` shape and is checked for conformance in tests.

```yaml
schema_version: work-item/v3
slug: <slug>
title: <one-line title>
created_at: <ISO-8601 timestamp>
updated_at: <ISO-8601 timestamp>
execution_mode: team-feature | personal-feature | refactor | bug-fix
work_status: active | completed | abandoned
delivery_status: not_requested | awaiting_approval | approved | pr_created | merged | deployed
stages:
  prd: { skill: prd-interview, file: prd.md, status: ready }
  spec: { skill: spec, file: spec.md, status: ready }
  qa-plan: { skill: qa, file: qa-plan.md, status: ready }
  plan: { skill: plan-sync, file: plan/plan.md, status: ready }
  implement: { skill: implement, file: implement-report.md, status: done }
  qa-report: { skill: qa, file: qa-report.md, status: validated }
  release: { skill: finishing-a-development-branch, file: qa-report.md, status: awaiting-approval }
inputs:
  - <workspace-relative path or external reference>
```

`work_status` records whether the requested work is complete. `delivery_status`
records a separate, evidence-backed release transition. Completing code never
implies that a PR, merge, or deployment happened. Each stage
uses one of `pending`, `ready`, `in_progress`, `awaiting-approval`, `approved`,
`blocked`, `done`, `validated`, `skipped`, or `superseded`. Every stage `file` is relative to its work-item
directory and must point to an existing file. Stage entries use the inline mapping
shown above so the dependency-free metadata checker can parse them consistently.
For completed work, a mode-required artifact cannot be `skipped` or
`superseded`; those states remain available only where the mode does not require
the artifact.

Human approval is a durable state transition, not a conversational promise:

```yaml
# before the PRD decision
stages:
  prd: { skill: prd-interview, file: prd.md, status: awaiting-approval }
```

```yaml
# after the PRD decision
stages:
  prd: { skill: prd-interview, file: prd.md, status: approved }
```

Use the same transition for the team design and release stages. Each human
decision is presented with [`GATE-PACKAGE.md`](GATE-PACKAGE.md). Release
transitions also update top-level delivery state and evidence:

```yaml
work_status: completed
delivery_status: pr_created
delivery_evidence:
  approval_ref: user:release-approved-2026-07-10
  pr_url: https://github.com/example/project/pull/42
```

Evidence is required only after the corresponding event actually occurs:

- `approved`: `approval_ref`
- `pr_created`: `approval_ref` and `pr_url`
- `merged`: `approval_ref` and the 40-character `merge_sha`
- `deployed`: `approval_ref`, `merge_sha`, and `deployment_id`

`approval_ref` is a typed `user:`, `local:`, or `external:` durable reference;
plain claims such as `yes` are invalid. `deployment_id` is a non-boolean opaque
provider identifier of at least six characters. These are shape checks, not proof
that the external approval or deployment occurred.

`not_requested` and `awaiting_approval` carry no delivery evidence. Every state
after `not_requested` requires `work_status: completed`; abandoned work stays at
`delivery_status: not_requested`. Each registry `allowed_evidence` list is the
exact shape for that state: evidence for a later PR, merge, or deployment event
is rejected until `delivery_status` reaches the corresponding state. Earlier
event detail remains recoverable from Git history rather than being carried
into an unrelated later-state shape.

Canonical planning is the default for new work items. It records:

```yaml
stages:
  plan: { skill: plan-sync, file: plan/plan.md, status: ready }
```

`plan/plan.md` contains the current execution contract. `plan/journal.md` is
optional and records only durable decisions, scope changes, blockers, and
deviations that cannot be recovered from current truth and Git history.
Canonical-v2 `## Sources` entries use exactly one typed reference per line:
`- local: <relative-path>[#<literal-stable-id>]`,
`- user: <durable-opaque-reference>`, or
`- external: <URL-or-durable-opaque-ID>`. Local paths resolve from `plan.md`,
must exist inside the Git workspace even after symlink resolution, and may name
a directory only when no anchor is present. The sibling `meta.yml` must contain
exactly one `plan` stage with `skill: plan-sync` and a `file` resolving to the
current `plan/plan.md`.

v0.7 accepts canonical-v2 only. A plan directory containing retired
`implementation.md`, `tasks.md`, or `notes.md` fails closed with one actionable
message: migrate the current execution truth to `plan/plan.md`, or keep the
consuming repository pinned to skill-commons v0.6 until it can migrate. No
runtime converter or second parser is maintained.

Rules:

1. `output:` frontmatter and the skill body name the same canonical path.
2. Do not create canonical or backup copies under `.agent/`.
3. Time belongs in `meta.yml` and Git history, not directory names.
4. Existing legacy `.agent/artifacts/` directories stay in place as history;
   all new work items use this contract.
5. Non-work-item conversions and standalone references use
   `<docs_root>/reference/<name>.md` plus `<name>.meta.yml` source metadata
   (`docs_root` defaults to `docs`).
6. External publication is optional and secondary; write the local artifact first.
7. At each artifact boundary, update one relevant line in `docs/STATUS.md` when
   that file exists. Do not rewrite status on every conversational turn.

## Lifecycle

Use `bash scripts/work-items.sh [--work-root <path>] <command>` to consume status:

- `list [--status active|completed|abandoned]` lists current work items by work status.
- `stale [--days N]` lists only `active` items whose `updated_at` is older than N days.
- `check` validates required metadata fields, work and delivery states, delivery
  evidence, stage values, timestamps, slug-directory alignment, and stage artifact paths.

The default retention period is a consuming-repository decision. After that period,
a `completed` or `abandoned` work item may be deleted as a whole because Git remains
the recovery source, or moved intact to `<work_root>/_archive/<slug>/`. Never archive
individual files from an otherwise active work item.

## Schema evolution and adoption

Shape gates (for example `scripts/check-prd.py`) apply forward, not retroactively:

1. Unstamped artifacts created before `2026-07-10T00:00:00+08:00` are
   grandfathered as legacy v1 metadata. Their
   `status: shipped` is displayed as completed work with `legacy_shipped`
   delivery; it is not treated as proof of a PR, merge, or deployment. Metadata
   created on or after that cutoff must declare `work-item/v3`; new or edited
   work items use that schema.
2. An artifact without a schema stamp is treated as schema version 1. When a
   canonical shape changes in a breaking way, stamp newly written artifacts with
   the new version and leave grandfathered artifacts unstamped.
3. A repository-wide sweep is opt-in. Run a gate across all existing artifacts
   only as a deliberate migration, never as a default check.

## Closeout

Before requesting release approval, a completed work item must:

1. When the execution mode includes a PRD, append a `## Delivery` section with
   candidate/release date, explicit PRD deviations (or `無`), any promoted
   assets, and a PASS link to the mode's final evidence: `qa-report.md` for
   `team-feature`, otherwise `implement-report.md`. If an allowed mode has no
   PRD, record the same closeout fields in `implement-report.md`.
2. Set `work_status: completed`, `delivery_status: awaiting_approval`, and mark
   completed stages done/validated. Do not add delivery evidence yet.
3. Promote still-valid decisions or terminology from `adr.md` / `glossary.md`
   to the project-level ADR or domain-model files, leaving originals in place.
   At the corresponding original section, add a blockquote marker using the
   workspace-relative destination, for example:

   ```markdown
   > promoted-to: docs/decisions/adr-012-api-versioning.md
   ```

   The marker records provenance and prevents an unmarked second source of truth.

For an allowed no-PRD work item, use fresh verification evidence in
`implement-report.md` instead of `qa-report.md`. After explicit
approval, record `approval_ref`; after PR creation, merge, or deployment, advance
`delivery_status` only when its required evidence is available. A local commit or
a blocked PR attempt does not satisfy any of those transitions.
