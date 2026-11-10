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
work_status: queued | active | completed | abandoned
delivery_status: not_requested | awaiting_approval | approved | pr_created | merged | deployed
documentation_impact: doc:<workspace-relative project document> | n/a:<bounded reason>
stages:
  prd: { skill: prd-interview, file: prd.md, status: ready }
  spec: { skill: spec, file: spec.md, status: ready }
  qa-plan: { skill: qa, file: qa-plan.md, status: ready }
  plan: { skill: plan-sync, file: plan/plan.md, status: ready }
  implement: { skill: implement, file: implement-report.md, status: done }
  qa-report: { skill: qa, file: qa-report.md, status: validated }
  release: { skill: sync-work, file: qa-report.md, status: awaiting-approval }
inputs:
  - <workspace-relative path or external reference>
```

### Conditional discovery document

A consented Deep exploration may write `brainstorm.md` as a supporting document.
It does not create a lifecycle stage. An existing work item links the document
through `inputs`; when discovery starts before a work item exists, the first PRD,
Spec, or Plan producer creates `meta.yml` and may add `brainstorm.md` to `inputs`.
The map's own Wayfinding Control records consent, remaining budget, and closeout.

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

### Allowed scope

`allowed_paths` in `meta.yml` is an optional comma-separated list on one line of
project-relative globs (`**` crosses folders, `*` does not, a trailing `/` or the bare name of
an existing folder means everything under it, `./` is ignored; no quotes or `#` comments).
`work-items.sh new` records `base_commit`, and `start` replaces it for a queued item.
`verify.sh --work-item` records the files changed outside the list since `base_commit` in
`verification.json`, and `project-status` recomputes them when it reads the item: committed
changes (deletions and both sides of a rename count), excluding commits already on the default
branch (`origin/HEAD`, `origin/main`, `origin/master`, `main`, `master`), plus uncommitted
changes. The work root and generated agent folders are always allowed; files Git ignores are
never seen; uncommitted caches are ignored, and a committed cache is always listed. A change
outside the list needs attention and fails `--strict`. On the default branch itself nothing is
excluded, so commits pulled from others count, and the status says so. `base_commit..HEAD` is
one range per branch: with more than one item that declares `allowed_paths` on it (active, or
completed and undelivered), each list is shown but is not attention on its own. Without
`base_commit`, or when it no longer resolves or is not an ancestor of HEAD after a rebase, only
uncommitted changes are checked and the status says so.

### Backlog and activity

`work_status: queued` is a backlog item: `work-items.sh new <slug> --queued` creates it and
`work-items.sh start <slug>` makes it `active`. Queued items are listed but do not count as
active work. Commands append one line to the item's `activity.jsonl` after they succeed (`new`,
`start`, `complete`, `verify.sh --work-item`, `approve`, `reaffirm`): time, event, result, and
the AI tools and sessions the environment reports. `project-status.sh --ledger` shows one row
per item (add `--json` or `--markdown`). Session ids are what the agent environment reports, not
identity; set `SKILL_COMMONS_SESSION=none` to record tools and time without them.

### Content-bound evidence and approval

`verify.sh --work-item <slug>` writes `verification.json` in the item: the result, a
fingerprint of the verified files and of the acceptance segments it covers
(`--covers prd.md#AC-002`; by default every `AC-` segment in `prd.md` and `spec.md`).
`verification_evidence.py approve --work-item <slug>` writes
`approval.json`, binding the approval to the same segments; `approval_ref` may point
to it as `local:approval.json`. The approval records how it was obtained: `terminal`
(a person typed `yes` at `/dev/tty` with no agent variable set) or `agent-reported`
(`--agent-reported` with `--quote` or `--reason`, for a person with no shell on the
checkout). Approvals written before these levels show `recorded before levels`. A
typed `approval_ref: user:...` string in `meta.yml` carries no level; prefer
`local:approval.json`. Approvals written after an upgrade need the upgraded submodule
in every checkout that reads them. Editing a bound segment makes the evidence or approval
stale in `project-status`; whitespace and punctuation do not count. `reaffirm --ref
<file>#<ID> --reason <why>` accepts an edited segment as meaning the same and is shown
as a count; code has no such exemption. Agents write these files only through these
commands. `--by` names who approved, and the level says how the approval was obtained;
neither is identity verification. Reaffirming an approved segment needs the same
confirmation as `approve`.

`not_requested` and `awaiting_approval` carry no delivery evidence. Every state
after `not_requested` requires `work_status: completed`; abandoned work stays at
`delivery_status: not_requested`. Each registry `allowed_evidence` list is the
exact shape for that state: evidence for a later PR, merge, or deployment event
is rejected until `delivery_status` reaches the corresponding state. Earlier
event detail remains recoverable from Git history rather than being carried
into an unrelated later-state shape.

## Documentation impact

Every completed work item carries exactly one documentation-impact result in the
scalar `documentation_impact` field, in one of two forms:

- `doc:<workspace-relative project document>` — the canonical project document
  this work updated.
- `n/a:<bounded reason>` — one line of at most 200 characters saying why no
  project document changed.

Work-history prose does not count: a path under the work root — any item's report,
journal, or plan, not only this item's — is rejected, because those record what
happened instead of integrating the result into the project's documentation. The
legal result is stated positively: a project document outside the work root.
A named document must also exist: a `doc:` path that resolves to nothing proves
no document was updated and is rejected. The field is a shape, location, and
existence check. It records which document was named; it never proves that
document's content changed.

Completion is a state a re-runnable check accepted, not a claim a report made. A
Plan state, an implementation report, a diff, a hash, or an authored PASS line is
never by itself proof that the work is complete; every execution path ends in a
fresh verification run and its test report. A hash proves an artifact's identity
or integrity, never its meaning.

The rule is forward-only, matching the adoption stance below: a work item whose
`updated_at` is on or after `2026-07-27T00:00:00+08:00` must carry the field when
`work_status: completed`. Work completed before that stays valid without it until
it is edited.

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

- `list [--status queued|active|completed|abandoned]` lists current work items by work status.
- `stale [--days N]` lists only `active` items whose `updated_at` is older than N days.
- `check` validates required metadata fields, work and delivery states, delivery
  evidence, stage values, timestamps, slug-directory alignment, and stage artifact paths.
  `check --item <slug>` checks only `<work_root>/<slug>/meta.yml` and fails when it is
  missing; a work root that itself contains `meta.yml` is a work item and is refused.

The default retention period is a consuming-repository decision. After that period,
a `completed` or `abandoned` work item may be deleted as a whole because Git remains
the recovery source, or moved intact to `<work_root>/_archive/<slug>/`. Never archive
individual files from an otherwise active work item.

## Schema evolution and adoption

Shape gates (for example `scripts/check-prd.py`) apply forward, not retroactively:

1. Unstamped artifacts created before this repository's v3 reconciliation are
   grandfathered as legacy v1 metadata. Their
   `status: shipped` is displayed as completed work with `legacy_shipped`
   delivery; it is not treated as proof of a PR, merge, or deployment. Metadata
   created on or after that date must declare `work-item/v3`. Editing an older
   item does not move it: pre-reconciliation items stay valid under the legacy
   schema, which is still fully validated, until each is migrated on purpose.
   Migration updates both metadata and planning documents: v3 adds lifecycle fields,
   while canonical-v2 replaces the three-file plan and changes the stage path. It is
   deliberate work rather than a side effect of touching a file.

   The date is **`2026-07-25T00:00:00+08:00`**, and it is enforced at
   `scripts/work_items.py` (`V3_ADOPTION_TIME`). The release lineage cut over on
   `2026-07-10T00:00:00+08:00`, but development main forked before v3 existed and
   kept creating items on the legacy schema until the two lines were reconciled on
   07-25. Items authored in a lineage that had no v3 could not have declared it, so
   holding them to 07-10 would report a defect that was never possible to avoid, and
   the only fix would be to backfill a `schema_version` onto metadata never written
   against that contract. The contract text and the checker name the same date, so a
   reader does not have to open the code to learn which one applies.
2. An artifact without a schema stamp is treated as schema version 1. When a
   canonical shape changes in a breaking way, stamp newly written artifacts with
   the new version and leave grandfathered artifacts unstamped.
3. A repository-wide sweep is opt-in. Run a gate across all existing artifacts
   only as a deliberate migration, never as a default check.

## Closeout

Before requesting release approval, a completed work item must:

1. When the execution mode includes a PRD, append a `## Delivery` section with
   candidate/release date, explicit PRD deviations (or `無`), any promoted
   assets, and a PASS link to the mode's final evidence. That acceptance evidence
   is **mode-conditional** on whether the mode has a QA stage: `qa-report.md` for
   `team-feature`, otherwise `implement-report.md`. If an allowed mode has no
   PRD, record the same closeout fields in `implement-report.md`.

   A `qa-report.md` PASS link is never required for a **no-QA execution mode**
   (`qa-plan` absent — `personal-feature`, `bug-fix`, `refactor`), because that
   file is never produced there; requiring it would create an unsatisfiable gate.
   The exemption follows from the mode contract, not from a work item being small.
2. Set `work_status: completed`, `delivery_status: awaiting_approval`, and mark
   completed stages done/validated. Do not add delivery evidence yet.
3. Promote still-valid decisions or terminology from `adr.md` / `glossary.md`
   to the project-level files `domain-modeling` maintains (`CONTEXT.md` and
   `docs/adr/NNNN-<title>.md`), leaving originals in place.
   At the corresponding original section, add a blockquote marker using the
   workspace-relative destination, for example:

   ```markdown
   > promoted-to: docs/adr/0012-api-versioning.md
   ```

   The marker records provenance and prevents an unmarked second source of truth.

For an allowed no-PRD work item, use fresh verification evidence in
`implement-report.md` instead of `qa-report.md`. After explicit
approval, record `approval_ref`; after PR creation, merge, or deployment, advance
`delivery_status` only when its required evidence is available. A local commit or
a blocked PR attempt does not satisfy any of those transitions.
