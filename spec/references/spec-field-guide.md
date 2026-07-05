# Spec Field Guide

Use this guide after Gate 2 preflight and template selection, before filling
`resources/spec-template.md` or `resources/integration-spec-template.md`.

Templates define the required output skeleton. This guide explains how to decide
what belongs in each section, how to fill conditional sections, and what counts
as evidence.

## Semantic Heading Rule

Use semantic heading names as the contract between PRD, Spec, QA, and
implementation. Do not depend on a numbered PRD Flow heading. Find the PRD
Flow section by heading meaning: `Flow`, `流程`, `Journey`, `Interaction`, or
equivalent wording.

## Capability Snapshot

Copy capability flags from `.agent/project-manifest.md`.

| Capability | Fill rule |
|---|---|
| `has_ui` | `true` only when the repo manifest says UI exists and this story affects UI. Evidence is design tokens, UI domain skill, mockup path, or N/A reason. |
| `has_api` | `true` only when the story calls or changes an API/external service. Evidence is manifest `api_reference` or user-confirmed contract source. |
| `typed_contracts` | `true` only when the project has typed contracts or validators. Evidence is `types_entry`, typecheck command, or validator command. |
| `has_e2e` | `true` only when manifest exposes an E2E command and the story needs journey-level proof. |

Capability false means the matching conditional section is `N/A`; do not invent
fake assets, fake interfaces, or fake commands.

## Files

List every source, test, config, migration, documentation, or generated artifact
that the implementation must touch. Use paths found from the architecture map,
manifest roots, domain skills, and nearby repo examples.

Use one row per file or coherent file group:

| Path | Operation | Purpose |
|---|---|---|
| `src/example.ts` | MODIFY | Add transformer used by S1. |

## Contracts

Contracts are the shape guarantees downstream implementation and QA use.

For `typed_contracts: true`, define or reference the project-language contract
from `types_entry` and record the typecheck/validator evidence. For
`typed_contracts: false`, write `N/A (typed_contracts=false)`.

For API Contract, `has_api: true` requires operation identity, request example,
success response, error response, and auth/permission rules from `api_reference`.
If `has_api: false`, write `N/A (has_api=false)`.

For UI Design, `has_ui: true` requires component/view responsibility, states,
interaction, token evidence, and mockup evidence when available. If
`has_ui: false`, write `N/A (has_ui=false)`.

## Flow / Data Flow

Translate the PRD Flow section into technical movement:

```text
user/system input -> validation -> core logic -> persistence/API/UI output
```

When `has_api` and `has_ui` are both true and shapes differ, name the
API-to-UI transformer and map source fields to UI fields. Otherwise record
`N/A` with the reason.

## Errors

Include normal, boundary, and error cases. Every PRD ERR should appear here or
be explicitly marked out of scope with a reason.

Good rows include trigger, expected behavior, and recovery path:

| Case | Trigger | Expected behavior | Recovery |
|---|---|---|---|
| Empty result | API returns `[]` | Empty state appears | User can retry or adjust filters |

## Decisions

Record only choices that affect implementation. A useful decision has context,
the selected option, why it was chosen, rejected alternatives, and reversibility.

Skip obvious restatements like "use the existing app framework" unless there is
a real tradeoff.

## Steps

Steps must be small enough for `plan-sync` and implementers to execute:

- include files and operation markers (`NEW`, `MODIFY`, `DELETE`)
- include dependencies between steps
- include an estimate
- include executable or observable verification

Use semantic IDs such as `S1`, `S2`, not section-number references.

## Test Strategy

Trace PRD AC and ERR to levels that match capability flags.

| Level | Use when |
|---|---|
| Unit | Core logic, validation, data transformation. |
| Integration | `has_api: true` or any external service/contract boundary. |
| Component | `has_ui: true` and UI behavior can be isolated. |
| E2E | `has_e2e: true` and a full journey is necessary after lower levels pass. |

Capability-disabled levels are `N/A`; do not backfill with unrelated tests.

## Gate 2

Gate 2 passes only when the spec is actionable without hidden assumptions:

- Capability Snapshot matches manifest.
- Files, Contracts, API Contract, UI Design, Flow / Data Flow, Errors,
  Decisions, Steps, and Test Strategy are filled or explicitly N/A.
- Contract evidence is objective for enabled capabilities.
- QA can map PRD AC / ERR to the Test Strategy.
- Implementation can start from Steps without relying on PRD section numbers.
