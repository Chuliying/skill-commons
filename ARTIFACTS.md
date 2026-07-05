# Work-Item Artifact Contract v2

Durable workflow outputs for one feature, fix, or change live together:

```text
<work_root>/<slug>/              # work_root defaults to docs/work
├── meta.yml
├── brainstorm.md
├── prd.md
├── spec.md
├── plan/
│   ├── implementation.md          # tracked mode
│   ├── tasks.md                   # tracked mode
│   ├── notes.md                   # tracked mode
│   └── plan.md                    # Lite mode; alternative to the three files above
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

```yaml
slug: <slug>
title: <one-line title>
created_at: <ISO-8601 timestamp>
updated_at: <ISO-8601 timestamp>
status: active | shipped | abandoned
stages:
  prd: { skill: prd-interview, file: prd.md, status: ready }
  spec: { skill: spec, file: spec.md, status: ready }
  qa-plan: { skill: qa, file: qa-plan.md, status: ready }
  implement: { skill: implement, file: implement-report.md, status: done }
  qa-report: { skill: qa, file: qa-report.md, status: validated }
  release: { skill: finishing-a-development-branch, file: qa-report.md, status: awaiting-approval }
inputs:
  - <workspace-relative path or external reference>
```

Allowed work-item statuses are `active`, `shipped`, and `abandoned`. Each stage
uses one of `pending`, `ready`, `in_progress`, `awaiting-approval`, `approved`,
`blocked`, `done`, `validated`, `skipped`, or `superseded`. Every stage `file` is relative to its work-item
directory and must point to an existing file. Stage entries use the inline mapping
shown above so the dependency-free metadata checker can parse them consistently.

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

Use the same transition for the team design and release stages. Before release
closeout, record the release decision in the relevant closeout artifact and only
then change the work-item to `shipped`. Each human decision is presented with
[`GATE-PACKAGE.md`](GATE-PACKAGE.md).

Lite planning is a formal alternative to tracked planning. A Lite item records:

```yaml
stages:
  plan: { skill: plan-sync, file: plan/plan.md, status: ready }
```

`plan/plan.md` and the tracked three-file plan must not coexist. Lite plans use
the structure in `plan-sync/templates/plan.md` and are validated by the same
`validate_consistency.py` entry point.

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

- `list [--status active|shipped|abandoned]` lists current work items by status.
- `stale [--days N]` lists only `active` items whose `updated_at` is older than N days.
- `check` validates required metadata fields, status values, stage values, timestamps,
  slug-directory alignment, and stage artifact paths.

The default retention period is a consuming-repository decision. After that period,
a `shipped` or `abandoned` work item may be deleted as a whole because Git remains
the recovery source, or moved intact to `<work_root>/_archive/<slug>/`. Never archive
individual files from an otherwise active work item.

## Closeout

Before merge or PR, a shipped work item must:

1. Append a `## Delivery` section to `prd.md` with release date, explicit PRD
   deviations (or `無`), a PASS link to `qa-report.md`, and any promoted assets.
2. Set `meta.yml` to `status: shipped` and mark stages done/validated.
3. Promote still-valid decisions or terminology from `adr.md` / `glossary.md`
   to the project-level ADR or domain-model files, leaving originals in place.
   At the corresponding original section, add a blockquote marker using the
   workspace-relative destination, for example:

   ```markdown
   > promoted-to: docs/decisions/adr-012-api-versioning.md
   ```

   The marker records provenance and prevents an unmarked second source of truth.

For an allowed no-PRD hotfix, skip the Delivery section and use fresh verification
evidence in `implement-report.md` instead of `qa-report.md`; still mark `meta.yml`
`shipped` before merge or PR.
