---
name: to-prd
description: Turn the current conversation into a PRD and publish it to the project issue tracker — no interview, just synthesis of what you've already discussed.
disable-model-invocation: true
source: mattpocock/skills@2454c95dc305
source_kind: vendored
stage: docs
output: <work_root>/<slug>/prd.md
---

This skill takes the current conversation context and codebase understanding and produces a PRD. Do NOT interview the user — just synthesize what you already know.

Issue tracker publication is optional. If tracker access or label vocabulary is unavailable, create the local artifact and report that publication was skipped.

## Process

1. Explore the repo to understand the current state of the codebase, if you haven't already. Use the project's domain glossary vocabulary throughout the PRD, and respect any ADRs in the area you're touching.

2. Identify the smallest useful verification surface from the existing discussion and codebase evidence. Prefer one high-level observable seam; record uncertainty as a Follow-up instead of expanding the PRD.

3. Write `prd.md` and update `meta.yml` under `<work_root>/<slug>/` following [`../ARTIFACTS.md`](../ARTIFACTS.md). If an issue tracker and `ready-for-agent` label are configured, publish the PRD after the local files exist.

<prd-template>

## 0. Context

### Goal

One paragraph: the problem, who benefits, and the intended outcome.

### Evidence

Repo paths, conversation facts, or `Skipped: existing project context is enough`.

### Risk

| Risk | Trigger | Mitigation |
|------|---------|------------|
| [real risk] | [when it happens] | [how to prevent or recover] |

## 1. Scope

### In scope

- [behavior included]

### Out of scope

- [behavior explicitly excluded]

### Dependencies & Constraints

- **Upstream**: [system/team/artifact] / N/A
- **Breaking change**: Yes ([impact]) / No
- **Assumptions**: [unverified premise] / N/A

## 2. Product Summary

### Business Goal

[measurable outcome]

### Personas + Pain Points

| Persona | Context | Pain Point |
|---------|---------|------------|
| [role] | [work situation] | [current problem] |

## 3. Functional Requirements (FR)

### FR-001: [name]

**使用者價值**: [why this matters]
**Behavior**: [what the system does]
**Data source**: Existing [system/API] / New API [owner] / FU-[ID]
**Permissions / Visibility**: [roles]
**Boundary conditions**:

- [edge case or invariant]

## 4. Non-functional Requirements (NFR)

| Category | Requirement |
|----------|-------------|
| Performance | [target or N/A with reason] |
| Security / Compliance | [requirement or N/A with reason] |
| Accessibility | [requirement or N/A with reason] |
| Compatibility | [requirement or N/A with reason] |

## 5. Error Scenarios (ERR)

### ERR-001: [name]

**Trigger**: [condition]
**Expected behavior**: [system response]
**Recovery**: [user or system recovery path]

## 6. Acceptance Criteria (AC)

### AC-001: [title]

```gherkin
Given [executable precondition]
When [action]
Then [observable result]
```

## 7. Flow

Flow: N/A, because [reason] / [short flow]

## 8. UI/UX

UI: N/A (has_ui=false) / [interaction, states, token/mockup evidence]

## 9. Related Documents

| Document | Link |
|----------|------|
| Spec | N/A |
| QA Plan | N/A |

</prd-template>
