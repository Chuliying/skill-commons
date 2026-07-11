# Plan: Neutral Goal journey

## Plan

- Format: canonical-v2
- Concurrency: 1
- Intent: Exercise repository state without controlling a host Goal.
- Scope: Create, drift, resume, and complete two dependent tasks.
- Non-goals: No Codex API, Claude API, thread, or host lifecycle calls.

## Sources

- local: ../prd.md#AC-001

## Tasks

### T02 | dependent task listed first

- Status: pending
- Depends On: [T01]

#### Intent

Run only after the prerequisite has verified evidence.

#### Expected Result

Dependency state makes this task ready only after T01 is done.

#### Definition of Done

- The deterministic T02 verification passes.

#### Verification

- bash verify.sh T02

### T01 | prerequisite task listed second

- Status: pending
- Depends On: []

#### Intent

Run the prerequisite before the dependent task.

#### Expected Result

T01 becomes the first ready task despite document order.

#### Definition of Done

- The deterministic T01 verification passes.

#### Verification

- bash verify.sh T01

## Change Log

- 2026-07-10: Created the deterministic neutral journey.
