# [功能名稱] PRD

| Field | Value |
|-------|-------|
| Story ID | S-[AREA]-[NN] |
| Version | v1.0.0 |
| Status | Draft |
| Sprint | Sprint [N] / N/A |
| has_ui | true / false |
| Tickets | [#issue] / N/A |

---

## 1. Follow-ups

Blocking FU must be closed before `spec`. Non-blocking FU needs an owner and close-by point.

### FU-001: [decision title]

| Type | Background | Options | AI recommendation | Decision |
|------|------------|---------|-------------------|----------|
| Blocking / Non-blocking | [why this changes scope, behavior, or acceptance] | A: [...] / B: [...] | [option + reason] | Pending / Confirmed: [...] |

---

## 2. Context

### Goal

[One paragraph: problem, beneficiary, and intended outcome.]

### Persona + Pain

| Persona | Context | Pain point |
|---------|---------|------------|
| [role] | [work situation] | [current problem] |

### Success metrics

| Metric | Target | Measurement |
|--------|--------|-------------|
| [metric] | [target value] | [how to observe it] |

### Risk and evidence

| Item | Trigger / Source | Mitigation / Decision |
|------|------------------|-----------------------|
| [real risk] | [when it happens] | [how to prevent or recover] |
| Evidence | [repo path, user statement, external source, or Skipped reason] | [adopted decision] |

---

## 3. Scope

### In scope

- [behavior, workflow, or deliverable included in this PRD]

### Out of scope

- [behavior, workflow, or deliverable explicitly excluded]

---

## 4. Flow

Flow: N/A, because [reason] / [short user or system flow]

```mermaid
flowchart TD
  A[Start] --> B[Action]
  B --> C{Result}
  C -->|Success| D[Expected outcome]
  C -->|Failure| E[ERR-001 recovery]
```

---

## 5. Functional Requirements (FR)

### FR-001: [requirement name]

**使用者價值**: [why this matters to the user or business]

**Behavior**: [what the system does]

**Input**:

| Field | Required | Notes |
|-------|----------|-------|
| [field] | Yes / No | [meaning, constraint, or N/A] |

**Output**:

| Field | Notes |
|-------|-------|
| [field] | [observable result] |

**Data source**: Existing [system/API] / New [owner] / FU-[ID]

**Permissions / Visibility**: [roles]

**Boundary conditions**:

- [edge case or invariant]

---

## 6. Non-functional Requirements (NFR)

| Category | Requirement |
|----------|-------------|
| Performance | [target or N/A + reason] |
| Security / Compliance | [requirement or N/A + reason] |
| Accessibility | [requirement or N/A + reason] |
| Compatibility | [browser, device, API, or N/A + reason] |

---

## 7. Error Scenarios (ERR)

### ERR-001: [error name]

**Trigger**: [condition]

**Expected behavior**: [system response]

**Recovery**: [user or system recovery path]

---

## 8. Acceptance Criteria (AC)

### AC-001: [acceptance title]

```gherkin
Given [executable precondition]
When [user or system action]
Then [observable result]
```

---

## 9. UI / UX

UI: N/A (has_ui=false) / [summary of changed UI]

### Mockup evidence

- [Figma, screenshot, wireframe, existing component path, or N/A + reason]

### Interaction and states

| State / Step | Expected behavior | Copy |
|--------------|-------------------|------|
| Default | [what user sees first] | [user-facing text or N/A] |
| Loading | [loading behavior or N/A + reason] | [copy or N/A] |
| Error | [error behavior or N/A + reason] | [copy or N/A] |
| Empty | [empty behavior or N/A + reason] | [copy or N/A] |

### Design tokens

| Token type | Usage |
|------------|-------|
| Color | [existing token name or N/A + reason] |
| Typography | [existing token name or N/A + reason] |
| Spacing | [existing token name or N/A + reason] |

---

## 10. Dependencies & Constraints

- **Upstream**: [PRD, system, external team, or N/A]
- **Downstream**: [affected features, reports, users, or N/A]
- **Breaking change**: Yes ([impact]) / No
- **Assumptions**: [unverified premise] / N/A

---

## 11. Related Documents

| Document | Link |
|----------|------|
| Spec | `<spec-artifact-path>` / N/A |
| QA Plan | `<qa-artifact-path>` / N/A |
| Design | [link] / N/A |
| Ticket | [#issue] / N/A |

---

## 12. Gate 1 Check

- [ ] Every FR has user value, data source, permissions, and boundary conditions.
- [ ] Every AC uses Given-When-Then and has an executable precondition.
- [ ] ERR covers the main failure and recovery path.
- [ ] Scope, dependencies, breaking change, and assumptions are explicit.
- [ ] Blocking FU is closed; non-blocking FU has owner and close-by point.
- [ ] NFR has measurable target or N/A + reason.
- [ ] UI evidence matches `has_ui`.
- [ ] `prd-interview/references/gate-1.md` result is PASS.
