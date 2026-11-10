---
name: implement
description: |
  Implement a feature, bug fix or refactor with RED-GREEN-REFACTOR. Use when: the router set an Execution Mode and the change needs tests first.
  Trigger keywords: implement, TDD, test first
source: obra/superpowers@d884ae04edebef577e82ff7c4e143debd0bbec99
source_kind: adapted
stage: implement
output: <work_root>/<slug>/implement-report.md
---

# Implement

Run the test-first loop directly, per the router's Execution Mode and conditional inputs.

## Iron Laws

1. No production code before a failing test observed to fail for the right reason.
2. No completion claim without fresh verification evidence.
3. No bug fix without root-cause evidence.

If production code comes before its test, remove it and restart from RED. Only exceptions: throwaway prototype, generated code or pure config, and only with the user's consent first.

## Execution Mode and conditional inputs

The router must set the Execution Mode at dispatch. Artifact requirement, producer and handoff
are defined by the mode record in [`../protocol-registry.json`](../protocol-registry.json);
this skill does not copy the execution matrix. Before starting, only look up and validate inputs; never treat the registry
as an executable workflow, state machine or scheduler.

Artifact requirement meanings:

- `required`: if missing, stop and report; never guess or fabricate.
- `optional`: read if present; continue if not.
- `absent`: this path does not produce it.

Substitute evidence:

- `bug-fix`: `systematic-debugging` root-cause evidence and a reproducible RED.
- `refactor`: characterization tests of existing behavior; follow the Spec's boundaries if it exists.
- `personal-feature`: read PRD/plan if present; a micro-task's contract is the user message and RED.

## Step 1: Environment and boundaries

1. Check Execution Mode and conditional inputs; record each input's state (read, optional-missing, absent) in the report.
2. Read `.agent/project-manifest.md`; if missing, find stack, tests and work root from repo conventions and log the fallback.
3. If the manifest has an architecture map or Domain Skill Names, read only those in scope.
4. When `has_ui: true`, read design tokens; if a mockup exists and the task changes UI, list comparisons before implementing.
5. Change only what the task and failing test define; leave external contracts you were not authorized to change untouched.

## Step 2: RED → GREEN → REFACTOR

Finish one full loop per behavior before the next.

### RED

1. Write one minimal test named for one observable behavior.
2. Run it with manifest `test_cmd` or repo convention.
3. Get an **observed failing test**: it FAILS (not a load error), the failure message matches the expected one, and the cause is missing behavior.
4. If it PASSES at once, fix the test or confirm the behavior is not new; never count it as RED evidence.

### GREEN

1. Write only the minimal production code to pass the current RED; do not build ahead.
2. Rerun the target test, then affected tests; all must PASS.
3. On failure, fix the code; never weaken assertions to fit it.

### REFACTOR

1. Only after GREEN: remove duplication, rename or extract helpers; add no behavior.
2. Rerun tests after each change; stay GREEN.
3. For UI changes, also run the applicable design-token gate.

Prefer real code in tests; if a mock is unavoidable, first read [`references/testing-anti-patterns.md`](references/testing-anti-patterns.md). After three failed fixes in a row on one problem, stop and return to `systematic-debugging` Phase 4.5.

## Step 3: Project patterns and full verification

1. Check file locations, naming, APIs, domain rules, tokens and mockup.
2. Run the manifest's `test_cmd`; run `lint_cmd` if set; require `typecheck_cmd` only when `typed_contracts: true`.
3. Mark a check `N/A` when its manifest capability is false; never fake evidence.

Without output evidence, never use completion wording like "should pass" or "probably works".

## Output

1. Place tests and code per manifest or repo conventions.
2. Write each RED/GREEN/REFACTOR round, commands, output summary and gate results to `<work_root>/<slug>/implement-report.md`.
3. Update the work item `meta.yml` per [`../ARTIFACTS.md`](../ARTIFACTS.md).

## Next Step

- `team-feature` → `qa validate` → `verification-before-completion`.
- Other modes → `verification-before-completion`.
- Fresh-context review needed → `caveman-review`.

## Execution Checklist (required for artifact handoff)

```text
Skill: implement
Executed At: YYYY-MM-DD HH:MM
Files: [added/changed files]
Report: <work_root>/<slug>/implement-report.md

Steps:
Step 1: Environment and boundaries - [PASS/SKIP]
  Evidence: [mode; input status; manifest/fallback]
Step 2: RED-GREEN-REFACTOR - [PASS/SKIP]
  Evidence: [RED expected failure; GREEN/REFACTOR commands, results]
Step 3: Project patterns and full verification - [PASS/SKIP]
  Evidence: [domain/UI rules; full verification output]

Gate:
  type-check: [PASS/FAIL/N/A]
  lint: [PASS/FAIL/N/A]
  test: [PASS/FAIL] (X/Y)
  UI mockup: [PASS/N/A]
```

Without the checklist, this artifact handoff is incomplete.
